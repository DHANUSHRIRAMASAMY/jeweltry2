import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/jewelry_item.dart';

class ArOverlayPainter extends CustomPainter {
  final Face? face;
  final JewelryItem? selectedItem;
  final ui.Image? jewelryImage;
  final Size imageSize;
  final bool isFrontCamera;

  ArOverlayPainter({
    required this.face,
    required this.selectedItem,
    required this.jewelryImage,
    required this.imageSize,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (face == null || jewelryImage == null || selectedItem == null) return;
    if (imageSize.width == 0 || imageSize.height == 0) return;

    // Scale from camera image coords → screen coords
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    switch (selectedItem!.type) {
      case JewelryType.earring:
        _drawEarrings(canvas, size, scaleX, scaleY);
        break;
      case JewelryType.necklace:
      case JewelryType.chain:
        _drawNecklace(canvas, size, scaleX, scaleY);
        break;
    }
  }

  // ── Earrings ──────────────────────────────────────────────────────────────

  void _drawEarrings(Canvas canvas, Size size, double scaleX, double scaleY) {
    final leftEar = face!.landmarks[FaceLandmarkType.leftEar];
    final rightEar = face!.landmarks[FaceLandmarkType.rightEar];
    if (leftEar == null || rightEar == null) return;

    final faceW = face!.boundingBox.width * scaleX;
    final earW = (faceW * 0.13 * selectedItem!.scale).clamp(18.0, 90.0);
    final earH = earW * (jewelryImage!.height / jewelryImage!.width);

    // Head roll angle (Z rotation) for rotation compensation
    final rollRad = _rollRadians();

    for (final ear in [leftEar, rightEar]) {
      final cx = ear.position.x * scaleX;
      final cy = ear.position.y * scaleY + earH * 0.5;

      _drawRotatedImage(
        canvas,
        center: Offset(cx, cy),
        width: earW,
        height: earH,
        rotationRad: rollRad,
      );
    }
  }

  // ── Necklace / Chain ──────────────────────────────────────────────────────

  void _drawNecklace(Canvas canvas, Size size, double scaleX, double scaleY) {
    final bottomMouth = face!.landmarks[FaceLandmarkType.bottomMouth];
    if (bottomMouth == null) return;

    final faceW = face!.boundingBox.width * scaleX;
    final neckW = (faceW * 1.15 * selectedItem!.scale).clamp(60.0, 320.0);
    final neckH = neckW * (jewelryImage!.height / jewelryImage!.width);

    final chinY = bottomMouth.position.y * scaleY;
    final centerX = face!.boundingBox.center.dx * scaleX;
    // Position necklace below chin — offset by ~60% of its height
    final centerY = chinY + neckH * 0.6;

    final rollRad = _rollRadians();

    _drawRotatedImage(
      canvas,
      center: Offset(centerX, centerY),
      width: neckW,
      height: neckH,
      rotationRad: rollRad,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Head roll in radians from ML Kit's headEulerAngleZ (degrees).
  double _rollRadians() {
    final deg = face!.headEulerAngleZ ?? 0.0;
    // Front camera mirrors horizontally, so negate the roll
    return isFrontCamera
        ? deg * math.pi / 180.0
        : -deg * math.pi / 180.0;
  }

  /// Draw [jewelryImage] centered at [center], rotated by [rotationRad].
  void _drawRotatedImage(
    Canvas canvas, {
    required Offset center,
    required double width,
    required double height,
    required double rotationRad,
  }) {
    final src = Rect.fromLTWH(
      0, 0,
      jewelryImage!.width.toDouble(),
      jewelryImage!.height.toDouble(),
    );
    final dst = Rect.fromCenter(
        center: Offset.zero, width: width, height: height);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationRad);
    canvas.drawImageRect(jewelryImage!, src, dst, Paint());
    canvas.restore();
  }

  @override
  bool shouldRepaint(ArOverlayPainter old) =>
      old.face != face ||
      old.selectedItem != selectedItem ||
      old.jewelryImage != jewelryImage ||
      old.imageSize != imageSize;
}
