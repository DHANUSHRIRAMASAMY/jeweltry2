import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import '../models/jewelry_item.dart';

/// MediaPipe Face Mesh landmark indices used for jewelry placement.
///
/// Necklace/chain placement strategy:
///   - Anchor: chin tip (152) — always at the bottom of the face
///   - Width:  jaw width derived from left-jaw (234) to right-jaw (454)
///             scaled to match how wide the neck appears
///   - Center X: midpoint of left-jaw and right-jaw landmarks
///   - Rotation: face roll (Euler Z) so chain tilts with head tilt
///   - Perspective: cos(yaw) compresses width when head turns
///   - The image CENTER is placed at chin + small downward offset
///     so the top of the chain image sits at the chin/neck junction
class ArOverlayPainter extends CustomPainter {
  // Earlobe indices (kept for reference; actual smoothed positions
  // come from EarSmoother passed in via smoothedLeftLobe/smoothedRightLobe)
  static const int _leftLobe   = 177; // ignore: unused_field
  static const int _rightLobe  = 401; // ignore: unused_field
  // Chin
  static const int _chinTip    = 152;
  // Nose tip (stable horizontal reference)
  static const int _noseTip    = 1;
  // Mouth corners (for earring size)
  static const int _leftMouth  = 61;
  static const int _rightMouth = 291;
  // Jaw edges (widest points of face oval at jaw level)
  static const int _leftJaw    = 234;   // left side of face oval
  static const int _rightJaw   = 454;   // right side of face oval
  // Upper neck / chin sides (just below jaw)
  static const int _leftChin   = 172;   // lower-left jaw
  static const int _rightChin  = 397;   // lower-right jaw

  final FaceMesh? mesh;
  final Face? face;
  final JewelryItem? selectedItem;
  final ui.Image? jewelryImage;      // left earring (or single/necklace)
  final ui.Image? rightJewelryImage; // right earring (null = use jewelryImage)
  final Size imageSize;
  final bool isFrontCamera;
  final Offset? smoothedLeftLobe;
  final Offset? smoothedRightLobe;

  const ArOverlayPainter({
    required this.mesh,
    required this.face,
    required this.selectedItem,
    required this.jewelryImage,
    required this.imageSize,
    required this.isFrontCamera,
    this.rightJewelryImage,
    this.smoothedLeftLobe,
    this.smoothedRightLobe,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (jewelryImage == null || selectedItem == null) return;
    if (imageSize.width == 0 || imageSize.height == 0) return;
    if (canvasSize.width == 0 || canvasSize.height == 0) return;

    // For earrings, wait until rightJewelryImage is also ready
    // to avoid briefly showing the unsplit pair image
    if (selectedItem!.type == JewelryType.earring &&
        rightJewelryImage == null) return;

    // ML Kit returns coords in the rotated (portrait) frame.
    final double mlW = imageSize.width > imageSize.height
        ? imageSize.height : imageSize.width;
    final double mlH = imageSize.width > imageSize.height
        ? imageSize.width  : imageSize.height;

    final double sx = canvasSize.width  / mlW;
    final double sy = canvasSize.height / mlH;

    // Euler angles from classic face detector (more stable than mesh)
    final double rollRad = _rollRad();
    final double yawDeg  = face?.headEulerAngleY ?? 0.0;
    final double yawRad  = yawDeg * math.pi / 180.0;
    final double perspX  = math.cos(yawRad).abs().clamp(0.15, 1.0);

    // If mesh is available use it; otherwise fall back to face bounding box
    if (mesh != null) {
      _drawWithMesh(canvas, canvasSize, sx, sy, rollRad, yawDeg, perspX);
    } else if (face != null) {
      _drawWithFallback(canvas, canvasSize, sx, sy, rollRad, yawDeg, perspX);
    }
  }

  @override
  bool shouldRepaint(ArOverlayPainter old) =>
      old.mesh != mesh ||
      old.face != face ||
      old.selectedItem?.id != selectedItem?.id ||
      old.jewelryImage != jewelryImage ||
      old.rightJewelryImage != rightJewelryImage ||
      old.imageSize != imageSize ||
      old.smoothedLeftLobe  != smoothedLeftLobe ||
      old.smoothedRightLobe != smoothedRightLobe;

  // ── Mesh-based drawing (precise) ──────────────────────────────────────────

  void _drawWithMesh(Canvas canvas, Size cs, double sx, double sy,
      double rollRad, double yawDeg, double perspX) {
    switch (selectedItem!.type) {
      case JewelryType.earring:
        _earringsMesh(canvas, cs, sx, sy, rollRad, yawDeg, perspX);
      case JewelryType.necklace:
      case JewelryType.chain:
        _necklaceMesh(canvas, cs, sx, sy, rollRad, perspX, scaleFactor: 1.6);
      case JewelryType.pendant:
        _necklaceMesh(canvas, cs, sx, sy, rollRad, perspX, scaleFactor: 1.0);
    }
  }

  void _earringsMesh(Canvas canvas, Size cs, double sx, double sy,
      double rollRad, double yawDeg, double perspX) {
    if (jewelryImage == null) return;

    // ── Determine ear positions ───────────────────────────────────────────
    // Priority: smoothed positions → mesh points 177/401 → face landmarks
    Offset? leftPos  = smoothedLeftLobe;
    Offset? rightPos = smoothedRightLobe;

    // Try mesh points 177 (left lobe) and 401 (right lobe)
    if (leftPos == null && yawDeg < 45) {
      final pt = _meshPoint(177);
      if (pt != null) leftPos = _toCanvas(pt.x * sx, pt.y * sy, cs);
    }
    if (rightPos == null && yawDeg > -45) {
      final pt = _meshPoint(401);
      if (pt != null) rightPos = _toCanvas(pt.x * sx, pt.y * sy, cs);
    }

    // Final fallback: use classic face landmarks (always available)
    if (face != null) {
      final faceH = face!.boundingBox.height * sy;
      final lobeDropY = faceH * 0.15; // lobe is below the ear midpoint
      if (leftPos == null && yawDeg < 45) {
        final lm = face!.landmarks[FaceLandmarkType.leftEar];
        if (lm != null) {
          leftPos = _toCanvas(lm.position.x * sx, lm.position.y * sy, cs)
              .translate(0, lobeDropY);
        }
      }
      if (rightPos == null && yawDeg > -45) {
        final lm = face!.landmarks[FaceLandmarkType.rightEar];
        if (lm != null) {
          rightPos = _toCanvas(lm.position.x * sx, lm.position.y * sy, cs)
              .translate(0, lobeDropY);
        }
      }
    }

    // ── Earring size ──────────────────────────────────────────────────────
    double earW;
    final leftMouth  = _meshPoint(_leftMouth);
    final rightMouth = _meshPoint(_rightMouth);
    if (leftMouth != null && rightMouth != null) {
      final mouthWidth = ((rightMouth.x - leftMouth.x) * sx).abs();
      earW = (mouthWidth * 0.55 * selectedItem!.scale).clamp(28.0, 120.0);
    } else if (face != null) {
      final faceW = face!.boundingBox.width * sx;
      earW = (faceW * 0.22 * selectedItem!.scale).clamp(28.0, 110.0);
    } else {
      earW = 55.0 * sx;
    }

    final leftImg  = jewelryImage!;
    final rightImg = rightJewelryImage ?? jewelryImage!;
    final bool flipRight = rightJewelryImage == null;

    // ── Draw ──────────────────────────────────────────────────────────────
    if (leftPos != null) {
      final earH = earW * (leftImg.height / leftImg.width);
      _drawImageDirect(canvas, leftImg,
          leftPos.translate(0, earH * 0.5), earW, earH, rollRad, perspX,
          flipH: false);
    }
    if (rightPos != null) {
      final earH = earW * (rightImg.height / rightImg.width);
      _drawImageDirect(canvas, rightImg,
          rightPos.translate(0, earH * 0.5), earW, earH, rollRad, perspX,
          flipH: flipRight);
    }
  }

  void _necklaceMesh(Canvas canvas, Size cs, double sx, double sy,
      double rollRad, double perspX, {required double scaleFactor}) {
    final chinPt      = _meshPoint(_chinTip);
    final nosePt      = _meshPoint(_noseTip);
    final leftJawPt   = _meshPoint(_leftJaw);
    final rightJawPt  = _meshPoint(_rightJaw);
    final leftChinPt  = _meshPoint(_leftChin);
    final rightChinPt = _meshPoint(_rightChin);

    // ── Width: use jaw-edge distance as the neckline width reference ────────
    // jaw width in canvas pixels
    double jawW = 0;
    if (leftJawPt != null && rightJawPt != null) {
      jawW = ((rightJawPt.x - leftJawPt.x) * sx).abs();
    } else if (mesh != null) {
      jawW = mesh!.boundingBox.width * sx;
    }
    // Chain width = jaw width × scaleFactor (slightly wider than jaw)
    final neckW = (jawW * scaleFactor * selectedItem!.scale)
        .clamp(80.0, 520.0);
    final neckH = neckW * _aspect();

    // ── Center X: midpoint of jaw edges (follows face turn naturally) ───────
    double rawCx;
    if (leftJawPt != null && rightJawPt != null) {
      rawCx = ((leftJawPt.x + rightJawPt.x) / 2.0) * sx;
    } else if (nosePt != null) {
      rawCx = nosePt.x * sx;
    } else {
      rawCx = mesh!.boundingBox.center.dx * sx;
    }
    final double centerX = isFrontCamera ? cs.width - rawCx : rawCx;

    // ── Anchor Y: chin tip + small downward offset ──────────────────────────
    // We want the TOP of the chain image to sit at the chin/neck junction.
    // Image center = chin_y + (chin-to-nose distance × 0.10) + neckH * 0.5
    // The 0.10 factor is a tiny nudge so the chain clears the chin.
    double anchorY;
    if (chinPt != null && nosePt != null) {
      final chinY    = chinPt.y * sy;
      final noseY    = nosePt.y * sy;
      final faceLen  = (chinY - noseY).abs();
      // Place image center just below chin so top of image = neckline
      anchorY = chinY + faceLen * 0.08 + neckH * 0.5;
    } else if (chinPt != null) {
      anchorY = chinPt.y * sy + neckH * 0.5;
    } else if (leftChinPt != null && rightChinPt != null) {
      anchorY = ((leftChinPt.y + rightChinPt.y) / 2.0) * sy + neckH * 0.5;
    } else {
      anchorY = mesh!.boundingBox.bottom * sy + neckH * 0.5;
    }

    _drawImage(canvas, Offset(centerX, anchorY), neckW, neckH, rollRad, perspX);
  }

  // ── Fallback drawing (no mesh — uses face bounding box) ───────────────────

  void _drawWithFallback(Canvas canvas, Size cs, double sx, double sy,
      double rollRad, double yawDeg, double perspX) {
    if (face == null) return;
    final faceW = face!.boundingBox.width  * sx;
    final faceH = face!.boundingBox.height * sy;

    switch (selectedItem!.type) {
      case JewelryType.earring:
        if (jewelryImage == null) return;
        final leftLm  = face!.landmarks[FaceLandmarkType.leftEar];
        final rightLm = face!.landmarks[FaceLandmarkType.rightEar];
        final earW = (faceW * 0.22 * selectedItem!.scale).clamp(28.0, 110.0);
        final lobeY = faceH * 0.15;
        final leftImg  = jewelryImage!;
        final rightImg = rightJewelryImage ?? jewelryImage!;
        final bool flipRight = rightJewelryImage == null;
        if (yawDeg < 40 && leftLm != null) {
          final earH = earW * (leftImg.height / leftImg.width);
          final pos = _toCanvas(leftLm.position.x * sx,
              leftLm.position.y * sy, cs).translate(0, lobeY + earH * 0.5);
          _drawImageDirect(canvas, leftImg, pos, earW, earH, rollRad, perspX,
              flipH: false);
        }
        if (yawDeg > -40 && rightLm != null) {
          final earH = earW * (rightImg.height / rightImg.width);
          final pos = _toCanvas(rightLm.position.x * sx,
              rightLm.position.y * sy, cs).translate(0, lobeY + earH * 0.5);
          _drawImageDirect(canvas, rightImg, pos, earW, earH, rollRad, perspX,
              flipH: flipRight);
        }
      case JewelryType.necklace:
      case JewelryType.chain:
      case JewelryType.pendant:
        final noseBaseLm    = face!.landmarks[FaceLandmarkType.noseBase];
        final bottomMouthLm = face!.landmarks[FaceLandmarkType.bottomMouth];
        final scaleFactor = selectedItem!.type == JewelryType.pendant
            ? 1.0 : 1.6;
        final w = (faceW * scaleFactor * selectedItem!.scale)
            .clamp(100.0, 520.0);
        final h = w * _aspect();
        double rawCx = noseBaseLm != null
            ? noseBaseLm.position.x * sx
            : face!.boundingBox.center.dx * sx;
        final cx = isFrontCamera ? cs.width - rawCx : rawCx;
        double anchorY;
        if (noseBaseLm != null && bottomMouthLm != null) {
          final noseY  = noseBaseLm.position.y * sy;
          final mouthY = bottomMouthLm.position.y * sy;
          // Estimate chin = mouth + 0.6 × (mouth-nose distance)
          final chinEst = mouthY + (mouthY - noseY).abs() * 0.6;
          anchorY = chinEst + h * 0.5;
        } else {
          anchorY = face!.boundingBox.bottom * sy + h * 0.5;
        }
        _drawImage(canvas, Offset(cx, anchorY), w, h, rollRad, perspX);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Get a mesh point by index. Returns null if mesh is null or index OOB.
  FaceMeshPoint? _meshPoint(int index) {
    if (mesh == null) return null;
    final pts = mesh!.points;
    if (index < 0 || index >= pts.length) return null;
    return pts[index];
  }

  Offset _toCanvas(double scaledX, double scaledY, Size cs) =>
      Offset(isFrontCamera ? cs.width - scaledX : scaledX, scaledY);

  double _aspect() =>
      jewelryImage == null ? 1.0 :
      jewelryImage!.height.toDouble() / jewelryImage!.width.toDouble();

  double _rollRad() {
    final deg = face?.headEulerAngleZ ?? 0.0;
    return isFrontCamera ? -deg * math.pi / 180.0 : deg * math.pi / 180.0;
  }

  void _drawImage(Canvas canvas, Offset center, double w, double h,
      double rollRad, double perspX) {
    if (jewelryImage == null) return;
    _drawImageDirect(canvas, jewelryImage!, center, w, h, rollRad, perspX);
  }

  void _drawImageDirect(Canvas canvas, ui.Image image, Offset center,
      double w, double h, double rollRad, double perspX,
      {bool flipH = false}) {
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromCenter(
        center: Offset.zero, width: w * perspX, height: h);
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (rollRad.abs() > 0.005) canvas.rotate(rollRad);
    if (flipH) canvas.scale(-1.0, 1.0); // mirror horizontally for right ear
    canvas.drawImageRect(image, src, dst, paint);
    canvas.restore();
  }
}
