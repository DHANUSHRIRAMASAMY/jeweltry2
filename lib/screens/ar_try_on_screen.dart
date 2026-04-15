import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:image/image.dart' as img;
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/jewelry_item.dart';
import '../services/local_jewelry_service.dart';
import '../state/ar_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ar_overlay_painter.dart';
import '../widgets/ear_smoother.dart';
import '../widgets/jewelry_card.dart';
import 'jewelry_select_screen.dart';

class ArTryOnScreen extends StatefulWidget {
  final JewelryItem? initialItem;
  const ArTryOnScreen({super.key, this.initialItem});

  @override
  State<ArTryOnScreen> createState() => _ArTryOnScreenState();
}

class _ArTryOnScreenState extends State<ArTryOnScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _controller;
  String? _error;
  bool _cameraReady = false;

  // ── Face Mesh (primary — 468 precise landmarks) ───────────────────────────
  final _meshDetector = FaceMeshDetector(
    option: FaceMeshDetectorOptions.faceMesh,
  );

  // ── Face Detection (fallback — Euler angles for rotation) ─────────────────
  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: false,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.1,
    ),
  );

  FaceMesh? _mesh;       // 468-point mesh for exact landmark positions
  Face? _face;           // classic detection for Euler angles
  Size _imageSize = Size.zero;
  bool _processing = false;

  // ── Ear smoothing ─────────────────────────────────────────────────────────
  final _earSmoother = EarSmoother();
  Offset? _smoothedLeft;
  Offset? _smoothedRight;

  // ── Jewelry ───────────────────────────────────────────────────────────────
  List<JewelryItem> _items = [];
  final Map<String, ui.Image> _cache = {};      // left / single image
  final Map<String, ui.Image> _rightCache = {}; // right image (pairs only)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    ArState.instance.addListener(_onSelectionChanged);
    _startCamera();
    _loadItems();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && !_cameraReady) _startCamera();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    ArState.instance.removeListener(_onSelectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _meshDetector.close();
    _faceDetector.close();
    super.dispose();
  }

  void _onSelectionChanged() {
    final item = ArState.instance.selected;
    if (item != null) _loadJewelryImage(item);
    // Do NOT reset smoother here — it causes earrings to disappear on tap.
    // The smoother will naturally update to the new item's positions.
    if (mounted) setState(() {});
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  void _disposeCamera() {
    try {
      if (_controller?.value.isStreamingImages == true) {
        _controller!.stopImageStream();
      }
    } catch (_) {}
    _controller?.dispose();
    _controller = null;
    if (mounted) setState(() => _cameraReady = false);
  }

  Future<void> _startCamera() async {
    if (mounted) setState(() { _error = null; _cameraReady = false; });
    try {
      var status = await Permission.camera.status;
      if (status.isDenied) status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) setState(() => _error =
            'Camera permission denied.\nEnable it in Settings → Apps → JewelTry → Permissions.');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera found.');
        return;
      }
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final imageFormat = Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888;

      final ctrl = CameraController(
        cam,
        ResolutionPreset.medium,   // medium keeps face-detection stream smooth
        enableAudio: false,
        imageFormatGroup: imageFormat,
      );

      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      _controller = ctrl;
      setState(() => _cameraReady = true);

      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted || _controller == null) return;

      try {
        await _controller!.startImageStream(_onFrame);
      } catch (e) {
        debugPrint('AR: ImageStream error: $e');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e');
    }
  }

  // ── Frame processing ──────────────────────────────────────────────────────

  Future<void> _onFrame(CameraImage image) async {
    if (_processing) return;
    _processing = true;
    try {
      final cam = _controller?.description;
      if (cam == null) return;

      final rotation = InputImageRotationValue.fromRawValue(cam.sensorOrientation)
          ?? InputImageRotation.rotation0deg;

      final WriteBuffer allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final format = InputImageFormatValue.fromRawValue(image.format.raw)
          ?? (Platform.isAndroid
              ? InputImageFormat.nv21
              : InputImageFormat.bgra8888);

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      // Run both detectors in parallel for speed
      final results = await Future.wait([
        _meshDetector.processImage(inputImage),
        _faceDetector.processImage(inputImage),
      ]);

      final meshes = results[0] as List<FaceMesh>;
      final faces  = results[1] as List<Face>;

      if (mounted) {
        // Compute scale factors for smoother
        final double mlW = image.width > image.height
            ? image.height.toDouble() : image.width.toDouble();
        final double mlH = image.width > image.height
            ? image.width.toDouble()  : image.height.toDouble();
        final ctrl = _controller;
        final double canvasW = ctrl != null
            ? ctrl.value.previewSize!.height : mlW;
        final double canvasH = ctrl != null
            ? ctrl.value.previewSize!.width  : mlH;
        final double sx = canvasW / mlW;
        final double sy = canvasH / mlH;
        final bool isFront = ctrl?.description.lensDirection ==
            CameraLensDirection.front;
        final double yawDeg = faces.isNotEmpty
            ? (faces.first.headEulerAngleY ?? 0.0) : 0.0;

        _earSmoother.update(
          mesh: meshes.isNotEmpty ? meshes.first : null,
          sx: sx,
          sy: sy,
          isFrontCamera: isFront,
          canvasWidth: canvasW,
          yawDeg: yawDeg,
        );

        setState(() {
          _mesh = meshes.isNotEmpty ? meshes.first : null;
          _face = faces.isNotEmpty  ? faces.first  : null;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
          _smoothedLeft  = _earSmoother.leftPos;
          _smoothedRight = _earSmoother.rightPos;
        });
      }
    } catch (e) {
      debugPrint('AR: frame error: $e');
    } finally {
      _processing = false;
    }
  }

  // ── Jewelry ───────────────────────────────────────────────────────────────

  Future<void> _loadItems() async {
    final items = await LocalJewelryService().getAllItems();
    if (!mounted) return;
    setState(() => _items = items);
    if (widget.initialItem != null) {
      final match = items.firstWhere(
        (i) => i.id == widget.initialItem!.id,
        orElse: () => widget.initialItem!,
      );
      ArState.instance.select(match);
    }
  }

  void _onItemTap(JewelryItem item) {
    if (ArState.instance.selected?.id == item.id) {
      ArState.instance.clear();
    } else {
      ArState.instance.select(item);
    }
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_cameraReady) return;
    try {
      // 1. Stop the face-detection stream
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }

      final cam = _controller!.description;

      // 2. Spin up a dedicated ultraHigh controller just for the shot
      final hiCtrl = CameraController(
        cam,
        ResolutionPreset.ultraHigh,
        enableAudio: false,
      );
      await hiCtrl.initialize();

      // Let the camera lock focus & exposure
      await Future.delayed(const Duration(milliseconds: 600));

      final xFile = await hiCtrl.takePicture();
      await hiCtrl.dispose();

      // 3. Flip horizontally for front camera
      String finalPath = xFile.path;
      final isFront = cam.lensDirection == CameraLensDirection.front;
      if (isFront) {
        finalPath = await _flipImageHorizontally(xFile.path);
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              JewelrySelectScreen(capturedPhotoPath: finalPath),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 250),
        ),
      );

      // 4. Restart the stream controller when we come back
      if (mounted && _controller != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted && _controller != null) {
          try { await _controller!.startImageStream(_onFrame); } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
        try { await _controller?.startImageStream(_onFrame); } catch (_) {}
      }
    }
  }

  /// Flips [sourcePath] horizontally and saves back as high-quality JPEG.
  static Future<String> _flipImageHorizontally(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final flipped = await Isolate.run(() {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      // Encode as JPEG at quality 95 — sharp and fast
      return img.encodeJpg(img.flipHorizontal(decoded), quality: 95) as List<int>;
    });
    await File(sourcePath).writeAsBytes(flipped);
    return sourcePath;
  }

  Future<void> _loadJewelryImage(JewelryItem item) async {
    // Already fully loaded — nothing to do
    if (_cache.containsKey(item.id) && 
        (item.type != JewelryType.earring || _rightCache.containsKey(item.id))) {
      if (mounted && ArState.instance.selected?.id == item.id) setState(() {});
      return;
    }

    try {
      // Read raw bytes
      final Uint8List bytes;
      if (item.isAsset) {
        final data = await rootBundle.load(item.imagePath);
        bytes = data.buffer.asUint8List();
      } else {
        final file = File(item.imagePath);
        if (!file.existsSync()) return;
        bytes = await file.readAsBytes();
      }

      if (item.type == JewelryType.earring && !item.isAsset) {
        // ── Earring: try to split first, then populate both caches at once ──
        if (item.isPair && item.rightImagePath != null) {
          // Pre-split on upload — load both files
          final rightFile = File(item.rightImagePath!);
          if (rightFile.existsSync()) {
            final rightBytes = await rightFile.readAsBytes();
            final leftCodec  = await ui.instantiateImageCodec(bytes);
            final rightCodec = await ui.instantiateImageCodec(rightBytes);
            _cache[item.id]      = (await leftCodec.getNextFrame()).image;
            _rightCache[item.id] = (await rightCodec.getNextFrame()).image;
          } else {
            // Right file missing — fall back to unsplit
            final codec = await ui.instantiateImageCodec(bytes);
            _cache[item.id] = (await codec.getNextFrame()).image;
          }
        } else {
          // Auto-split using blob detection — do NOT show anything until done
          final split = await Isolate.run(() => _blobSplitToImages(bytes));
          if (split != null) {
            // Split succeeded — populate both caches with individual earrings
            final leftCodec  = await ui.instantiateImageCodec(
                Uint8List.fromList(split.$1));
            final rightCodec = await ui.instantiateImageCodec(
                Uint8List.fromList(split.$2));
            _cache[item.id]      = (await leftCodec.getNextFrame()).image;
            _rightCache[item.id] = (await rightCodec.getNextFrame()).image;
            debugPrint('AR: auto-split ${item.name}');
          } else {
            // No clear gap — single earring, use same image for both ears
            final codec = await ui.instantiateImageCodec(bytes);
            final image = (await codec.getNextFrame()).image;
            _cache[item.id]      = image;
            _rightCache[item.id] = image; // same image, painter will flip right
            debugPrint('AR: single earring ${item.name}');
          }
        }
      } else {
        // ── Non-earring (necklace, chain) ────────────────────────
        final codec = await ui.instantiateImageCodec(bytes);
        _cache[item.id] = (await codec.getNextFrame()).image;
      }
    } catch (e) {
      debugPrint('AR: image load error (${item.name}): $e');
    }

    if (mounted && ArState.instance.selected?.id == item.id) {
      setState(() {});
    }
  }

  /// Blob-detection split — same algorithm as LocalJewelryService._blobSplit.
  /// Returns (leftPngBytes, rightPngBytes) or null if only one blob found.
  static (List<int>, List<int>)? _blobSplitToImages(Uint8List bytes) {
    final src = img.decodeImage(bytes);
    if (src == null) return null;

    final w = src.width;
    final h = src.height;

    // Column opacity histogram
    final colOpacity = List<int>.filled(w, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (src.getPixel(x, y).a > 10) colOpacity[x]++;
      }
    }

    // Find split column (minimum opacity in middle 60%)
    final startX = (w * 0.20).round();
    final endX   = (w * 0.80).round();
    int splitX = w ~/ 2;
    int minVal = colOpacity[splitX];
    for (int x = startX; x < endX; x++) {
      if (colOpacity[x] < minVal) {
        minVal = colOpacity[x];
        splitX = x;
      }
    }

    // If the gap column still has many opaque pixels, it's probably a single
    // earring — don't split
    final totalOpaque = colOpacity.fold(0, (a, b) => a + b);
    final avgOpacity  = totalOpaque / w;
    if (minVal > avgOpacity * 0.5) return null; // no clear gap found

    final leftCrop  = img.copyCrop(src, x: 0,      y: 0, width: splitX,     height: h);
    final rightCrop = img.copyCrop(src, x: splitX, y: 0, width: w - splitX, height: h);

    return (img.encodePng(_trim(leftCrop)), img.encodePng(_trim(rightCrop)));
  }

  static img.Image _trim(img.Image src) {
    final w = src.width;
    final h = src.height;
    int top = 0, bottom = h - 1, left = 0, right = w - 1;
    outer: for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (src.getPixel(x, y).a > 10) { top = y; break outer; }
      }
    }
    outer: for (int y = h - 1; y >= 0; y--) {
      for (int x = 0; x < w; x++) {
        if (src.getPixel(x, y).a > 10) { bottom = y; break outer; }
      }
    }
    outer: for (int x = 0; x < w; x++) {
      for (int y = 0; y < h; y++) {
        if (src.getPixel(x, y).a > 10) { left = x; break outer; }
      }
    }
    outer: for (int x = w - 1; x >= 0; x--) {
      for (int y = 0; y < h; y++) {
        if (src.getPixel(x, y).a > 10) { right = x; break outer; }
      }
    }
    const pad = 4;
    final x0 = (left   - pad).clamp(0, w - 1);
    final y0 = (top    - pad).clamp(0, h - 1);
    final x1 = (right  + pad).clamp(0, w - 1);
    final y1 = (bottom + pad).clamp(0, h - 1);
    if (x1 <= x0 || y1 <= y0) return src;
    return img.copyCrop(src, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorView(error: _error!, onRetry: _startCamera);

    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final selected = ArState.instance.selected;
    final has3d = selected?.has3dModel ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── Tab bar ───────────────────────────────────────────────────────
          Container(
            color: Colors.black,
            padding: EdgeInsets.only(top: topPad),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: AppColors.gold,
                    indicatorWeight: 2.5,
                    labelColor: AppColors.gold,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                    tabs: [
                      const Tab(
                        icon: Icon(Icons.camera_alt_outlined, size: 18),
                        text: 'Try On',
                        iconMargin: EdgeInsets.only(bottom: 2),
                      ),
                      Tab(
                        icon: Icon(Icons.view_in_ar_rounded,
                            size: 18,
                            color: has3d ? null : Colors.white24),
                        child: Text('3D View',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: has3d ? null : Colors.white24)),
                      ),
                    ],
                    onTap: (i) {
                      if (i == 1 && !has3d) {
                        _tabController.animateTo(0);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'No 3D model for this item. Shop owner can upload a .glb file.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ),
                if (selected != null)
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(selected.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),

          // ── Tab views ─────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _ArCameraTab(
                  controller: _controller,
                  cameraReady: _cameraReady,
                  mesh: _mesh,
                  face: _face,
                  imageSize: _imageSize,
                  selected: selected,
                  jewelryImage: selected != null ? _cache[selected.id] : null,
                  rightJewelryImage: selected != null ? _rightCache[selected.id] : null,
                  items: _items,
                  onItemTap: _onItemTap,
                  smoothedLeftLobe: _smoothedLeft,
                  smoothedRightLobe: _smoothedRight,
                  onCapture: _capturePhoto,
                ),
                _ViewerTab3d(selected: selected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── AR Camera Tab ─────────────────────────────────────────────────────────────

class _ArCameraTab extends StatelessWidget {
  final CameraController? controller;
  final bool cameraReady;
  final FaceMesh? mesh;
  final Face? face;
  final Size imageSize;
  final JewelryItem? selected;
  final ui.Image? jewelryImage;
  final ui.Image? rightJewelryImage;
  final List<JewelryItem> items;
  final ValueChanged<JewelryItem> onItemTap;
  final Offset? smoothedLeftLobe;
  final Offset? smoothedRightLobe;
  final VoidCallback onCapture;

  const _ArCameraTab({
    required this.controller,
    required this.cameraReady,
    required this.mesh,
    required this.face,
    required this.imageSize,
    required this.selected,
    required this.jewelryImage,
    required this.rightJewelryImage,
    required this.items,
    required this.onItemTap,
    required this.onCapture,
    this.smoothedLeftLobe,
    this.smoothedRightLobe,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final isFront = controller?.description.lensDirection ==
        CameraLensDirection.front;

    return Stack(
      children: [
        // Camera preview
        if (cameraReady && controller != null)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller!.value.previewSize!.height,
                height: controller!.value.previewSize!.width,
                child: CameraPreview(controller!),
              ),
            ),
          )
        else
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.gold),
                    SizedBox(height: 14),
                    Text('Starting camera…',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),

        // AR overlay — same FittedBox space as preview
        if (cameraReady && controller != null)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller!.value.previewSize!.height,
                height: controller!.value.previewSize!.width,
                child: CustomPaint(
                  size: Size(
                    controller!.value.previewSize!.height,
                    controller!.value.previewSize!.width,
                  ),
                  painter: ArOverlayPainter(
                    mesh: mesh,
                    face: face,
                    selectedItem: selected,
                    jewelryImage: jewelryImage,
                    rightJewelryImage: rightJewelryImage,
                    imageSize: imageSize,
                    isFrontCamera: isFront,
                    smoothedLeftLobe: smoothedLeftLobe,
                    smoothedRightLobe: smoothedRightLobe,
                  ),
                ),
              ),
            ),
          ),

        // Face hint
        if (mesh == null && selected != null && cameraReady)
          Positioned(
            top: 16, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('Position your face in frame',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),
          ),

        // Capture button — sits above the jewelry panel
        if (cameraReady)
          Positioned(
            bottom: 160 + bottomPad,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: onCapture,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white38, width: 3),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black38,
                          blurRadius: 12,
                          offset: Offset(0, 4))
                    ],
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Colors.black87, size: 30),
                ),
              ),
            ),
          ),

        // Bottom jewelry carousel
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _JewelryPanel(
            items: items,
            selected: selected,
            bottomPad: bottomPad,
            onTap: onItemTap,
          ),
        ),
      ],
    );
  }
}

// ── 3D Viewer Tab ─────────────────────────────────────────────────────────────

class _ViewerTab3d extends StatelessWidget {
  final JewelryItem? selected;
  const _ViewerTab3d({required this.selected});

  @override
  Widget build(BuildContext context) {
    if (selected == null) {
      return const _EmptyViewer(
          message: 'Select a jewelry item from the Try On tab first');
    }
    if (!selected!.has3dModel) {
      return _EmptyViewer(
        message:
            'No 3D model for "${selected!.name}".\nShop owner can upload a .glb file.',
        icon: Icons.view_in_ar_outlined,
      );
    }
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Column(
        children: [
          Expanded(
            child: ModelViewer(
              src: 'file://${selected!.glbPath}',
              alt: selected!.name,
              autoRotate: true,
              autoRotateDelay: 1000,
              cameraControls: true,
              shadowIntensity: 0.8,
              shadowSoftness: 1.0,
              exposure: 1.0,
              backgroundColor: const Color(0xFF1A1A2E),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            color: Colors.black,
            child: Row(
              children: [
                const Icon(Icons.view_in_ar_rounded,
                    color: AppColors.gold, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selected!.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const Text('Drag to rotate · Pinch to zoom',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color:
                            const Color(0xFF4CAF50).withValues(alpha: 0.4)),
                  ),
                  child: const Text('3D',
                      style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyViewer extends StatelessWidget {
  final String message;
  final IconData icon;
  const _EmptyViewer(
      {required this.message, this.icon = Icons.touch_app_outlined});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white24, size: 56),
              const SizedBox(height: 16),
              Text(message,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom jewelry panel ──────────────────────────────────────────────────────

class _JewelryPanel extends StatelessWidget {
  final List<JewelryItem> items;
  final JewelryItem? selected;
  final double bottomPad;
  final ValueChanged<JewelryItem> onTap;
  const _JewelryPanel({
    required this.items,
    required this.selected,
    required this.bottomPad,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Color(0x30000000),
              blurRadius: 20,
              offset: Offset(0, -4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: items.isEmpty
                ? const Center(
                    child: Text('No jewelry added yet',
                        style: TextStyle(
                            color: AppColors.textHint, fontSize: 13)))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return Stack(
                        children: [
                          JewelryCard(
                            item: item,
                            selected: selected?.id == item.id,
                            onTap: () => onTap(item),
                          ),
                          if (item.has3dModel)
                            Positioned(
                              top: 4, right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('3D',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          SizedBox(height: 10 + bottomPad),
        ],
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isPermission =
        error.contains('permission') || error.contains('Permission');
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPermission
                            ? Icons.camera_alt_outlined
                            : Icons.no_photography_outlined,
                        color: Colors.white38, size: 64,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isPermission
                            ? 'Camera Access Required'
                            : 'Camera could not start',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isPermission
                            ? 'Allow camera access to try on jewelry in real time.'
                            : 'Something went wrong. Please try again.',
                        style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                            height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Try Again'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      if (isPermission) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => openAppSettings(),
                            icon: const Icon(Icons.settings_outlined,
                                size: 18, color: Colors.white54),
                            label: const Text('Open Settings',
                                style: TextStyle(color: Colors.white54)),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Colors.white24),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
