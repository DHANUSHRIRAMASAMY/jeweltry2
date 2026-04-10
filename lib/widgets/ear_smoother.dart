import 'package:flutter/material.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

/// Holds smoothed positions for both earlobes and exposes
/// confidence-gated visibility flags.
///
/// Call [update] every frame with the latest mesh (or null).
/// Read [leftPos], [rightPos], [showLeft], [showRight] for rendering.
class EarSmoother {
  // Exponential smoothing factor: 0.5 = responsive tracking with mild smoothing
  static const double _alpha = 0.5;

  // Z-depth threshold: mesh Z values are scaled to image size.
  // A frontal face has Z values roughly in the range -100 to +100.
  // We only hide if Z is very large positive (clearly facing away).
  static const double _zHiddenThreshold = 150.0;

  // Yaw threshold beyond which the far ear is definitely hidden
  static const double _yawHideThreshold = 45.0;

  // How many consecutive frames of absence before we hide the earring
  // Keep low (2) so earrings appear quickly on first detection
  static const int _missingFramesToHide = 2;

  Offset? _leftSmoothed;
  Offset? _rightSmoothed;
  int _leftMissingFrames = 0;
  int _rightMissingFrames = 0;

  // Public outputs
  Offset? get leftPos  => _leftSmoothed;
  Offset? get rightPos => _rightSmoothed;
  bool get showLeft  => _leftSmoothed  != null;
  bool get showRight => _rightSmoothed != null;

  /// Update smoother with the latest mesh and scale factors.
  /// [sx], [sy] convert ML Kit coords to canvas coords.
  /// [isFrontCamera] flips x for front camera mirror.
  /// [canvasWidth] needed for the x-flip.
  /// [yawDeg] from Face detector for coarse visibility gate.
  void update({
    required FaceMesh? mesh,
    required double sx,
    required double sy,
    required bool isFrontCamera,
    required double canvasWidth,
    required double yawDeg,
    // Mesh point indices
    int leftLobeIndex  = 177,
    int rightLobeIndex = 401,
  }) {
    final leftRaw  = _extractPoint(mesh, leftLobeIndex,  sx, sy, isFrontCamera, canvasWidth);
    final rightRaw = _extractPoint(mesh, rightLobeIndex, sx, sy, isFrontCamera, canvasWidth);

    // Coarse yaw gate: if head turns > threshold, far ear is hidden
    final bool leftVisible  = yawDeg < _yawHideThreshold;
    final bool rightVisible = yawDeg > -_yawHideThreshold;

    // Z-depth gate: check if the lobe point is facing away
    final bool leftZOk  = _zOk(mesh, leftLobeIndex);
    final bool rightZOk = _zOk(mesh, rightLobeIndex);

    _updateSide(
      raw: (leftRaw != null && leftVisible && leftZOk) ? leftRaw : null,
      smoothed: _leftSmoothed,
      missingFrames: _leftMissingFrames,
      onUpdate: (s, f) { _leftSmoothed = s; _leftMissingFrames = f; },
    );

    _updateSide(
      raw: (rightRaw != null && rightVisible && rightZOk) ? rightRaw : null,
      smoothed: _rightSmoothed,
      missingFrames: _rightMissingFrames,
      onUpdate: (s, f) { _rightSmoothed = s; _rightMissingFrames = f; },
    );
  }

  void _updateSide({
    required Offset? raw,
    required Offset? smoothed,
    required int missingFrames,
    required void Function(Offset? smoothed, int missingFrames) onUpdate,
  }) {
    if (raw != null) {
      // Point detected — smooth it
      final next = smoothed == null
          ? raw  // first detection: snap immediately
          : Offset(
              smoothed.dx * (1 - _alpha) + raw.dx * _alpha,
              smoothed.dy * (1 - _alpha) + raw.dy * _alpha,
            );
      onUpdate(next, 0);
    } else {
      // Point missing this frame
      final newMissing = missingFrames + 1;
      if (newMissing >= _missingFramesToHide) {
        onUpdate(null, newMissing); // hide after N consecutive misses
      } else {
        onUpdate(smoothed, newMissing); // keep last position briefly
      }
    }
  }

  Offset? _extractPoint(
    FaceMesh? mesh,
    int index,
    double sx,
    double sy,
    bool isFrontCamera,
    double canvasWidth,
  ) {
    if (mesh == null) return null;
    final pts = mesh.points;
    if (index < 0 || index >= pts.length) return null;
    final pt = pts[index];
    final x = isFrontCamera ? canvasWidth - pt.x * sx : pt.x * sx;
    final y = pt.y * sy;
    return Offset(x, y);
  }

  bool _zOk(FaceMesh? mesh, int index) {
    if (mesh == null) return false;
    final pts = mesh.points;
    if (index < 0 || index >= pts.length) return false;
    // Z is negative when facing camera; large positive Z = facing away
    return pts[index].z < _zHiddenThreshold;
  }

  /// Reset all smoothing state (call when face is lost or item changes).
  void reset() {
    _leftSmoothed  = null;
    _rightSmoothed = null;
    _leftMissingFrames  = 0;
    _rightMissingFrames = 0;
  }
}
