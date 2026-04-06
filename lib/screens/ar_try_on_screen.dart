import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/jewelry_item.dart';
import '../services/local_jewelry_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ar_overlay_painter.dart';
import '../widgets/jewelry_card.dart';

class ArTryOnScreen extends StatefulWidget {
  final JewelryItem? initialItem;
  const ArTryOnScreen({super.key, this.initialItem});

  @override
  State<ArTryOnScreen> createState() => _ArTryOnScreenState();
}

class _ArTryOnScreenState extends State<ArTryOnScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _cameraReady = false;

  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  Face? _face;
  Size _imageSize = Size.zero;
  bool _processing = false;

  List<JewelryItem> _items = [];
  JewelryItem? _selected;
  ui.Image? _jewelryImage;
  final Map<String, ui.Image> _cache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
    _loadItems();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Only dispose on actual pause (app backgrounded), not on inactive
      // (which fires for permission dialogs, phone calls, etc.)
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      // Small delay so the permission system has time to persist the grant
      // before we call availableCameras() / Permission.camera.status
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_cameraReady) _startCamera();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _detector.close();
    super.dispose();
  }

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
      // Check current status first — don't re-request if already granted
      var status = await Permission.camera.status;
      if (status.isDenied) {
        // First time — show the system dialog
        status = await Permission.camera.request();
      }
      if (!status.isGranted) {
        if (mounted) setState(() => _error = 'Camera permission denied.\nEnable it in Settings → Apps → JewelTry → Permissions.');
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

      // ResolutionPreset.medium matches the default phone camera FOV.
      // Higher presets use a narrower FOV on many devices, causing zoom effect.
      final ctrl = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        // yuv420 tells CameraX to only bind PREVIEW + IMAGE_ANALYSIS surfaces,
        // skipping the JPEG STILL_CAPTURE surface that causes the
        // "No supported surface combination" error on some devices.
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }

      _controller = ctrl;
      // Render CameraPreview first so the Flutter texture binds to CameraX surface.
      setState(() => _cameraReady = true);

      // Wait for surface attachment before starting the ML Kit stream.
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted || _controller == null) return;

      // startImageStream can fail on some devices when the surface combination
      // is not supported (too many use cases). Catch it gracefully — the preview
      // still works, face detection just won't run.
      try {
        await _controller!.startImageStream(_onFrame);
      } catch (streamError) {
        debugPrint('ImageStream not supported on this device: $streamError');
        // Preview works fine without the stream — AR overlay won't show
        // but the camera is functional.
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e');
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing) return;
    _processing = true;
    try {
      final cam = _controller?.description;
      if (cam == null) return;
      final rotation = InputImageRotationValue.fromRawValue(cam.sensorOrientation);
      if (rotation == null) return;
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return;
      final input = InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
      final faces = await _detector.processImage(input);
      if (mounted) {
        setState(() {
          _face = faces.isNotEmpty ? faces.first : null;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        });
      }
    } catch (_) {
    } finally {
      _processing = false;
    }
  }

  Future<void> _loadItems() async {
    final items = await LocalJewelryService().getAllItems();
    if (!mounted) return;
    setState(() => _items = items);
    if (widget.initialItem != null) {
      final match = items.firstWhere(
        (i) => i.id == widget.initialItem!.id,
        orElse: () => widget.initialItem!,
      );
      _pick(match);
    }
  }

  Future<void> _pick(JewelryItem item) async {
    setState(() { _selected = item; _jewelryImage = _cache[item.id]; });
    if (_cache.containsKey(item.id)) return;
    try {
      final Uint8List bytes;
      if (item.isAsset) {
        final d = await rootBundle.load(item.imagePath);
        bytes = d.buffer.asUint8List();
      } else {
        bytes = await File(item.imagePath).readAsBytes();
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _cache[item.id] = frame.image;
      if (mounted && _selected?.id == item.id) {
        setState(() => _jewelryImage = frame.image);
      }
    } catch (e) {
      debugPrint('Image load error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _startCamera);
    }

    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final bottomPad = mq.padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen camera preview — no forced aspect ratio, no scaling.
          // CameraPreview fills its parent and uses the controller's native ratio.
          // StackFit.expand is NOT used so the preview is not stretched.
          if (_cameraReady && _controller != null)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  // Give CameraPreview its natural size based on the sensor resolution.
                  // controller.value.previewSize is the actual pixel dimensions.
                  width: _controller!.value.previewSize!.height,
                  height: _controller!.value.previewSize!.width,
                  child: CameraPreview(_controller!),
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

          // AR overlay — same full-screen rect
          if (_cameraReady && _controller != null)
            Positioned.fill(
              child: CustomPaint(
                painter: ArOverlayPainter(
                  face: _face,
                  selectedItem: _selected,
                  jewelryImage: _jewelryImage,
                  imageSize: _imageSize,
                  isFrontCamera: true,
                ),
              ),
            ),

          // Face hint
          if (_face == null && _selected != null && _cameraReady)
            Positioned(
              top: topPad + 70,
              left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('Position your face in frame',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
            ),

          // Bottom jewelry panel
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Color(0x30000000), blurRadius: 20, offset: Offset(0, -4))],
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
                    child: _items.isEmpty
                        ? const Center(
                            child: Text('No jewelry added yet',
                                style: TextStyle(color: AppColors.textHint, fontSize: 13)))
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final item = _items[i];
                              return JewelryCard(
                                item: item,
                                selected: _selected?.id == item.id,
                                onTap: () {
                                  if (_selected?.id == item.id) {
                                    setState(() { _selected = null; _jewelryImage = null; });
                                  } else {
                                    _pick(item);
                                  }
                                },
                              );
                            },
                          ),
                  ),
                  SizedBox(height: 10 + bottomPad),
                ],
              ),
            ),
          ),

          // Back button
          Positioned(
            top: topPad + 12, left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isPermission = error.contains('permission') || error.contains('Permission');
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
                        color: Colors.white38,
                        size: 64,
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
