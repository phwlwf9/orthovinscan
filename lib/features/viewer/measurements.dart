import 'dart:math' as math;
import 'dart:ui';

/// Distance between two points expressed in image pixels, independent of zoom.
double distancePixels(Offset a, Offset b) => (b - a).distance;

/// The smaller angle at [vertex], or null when either arm has zero length.
double? angleDegrees(Offset a, Offset vertex, Offset b) {
  final armA = a - vertex;
  final armB = b - vertex;
  final denominator = armA.distance * armB.distance;
  if (!denominator.isFinite || denominator <= 0) return null;
  final cosine = ((armA.dx * armB.dx + armA.dy * armB.dy) / denominator).clamp(
    -1.0,
    1.0,
  );
  return math.acos(cosine) * 180 / math.pi;
}

/// Returns millimeters only if an explicit, finite, positive calibration exists.
/// Uncalibrated images must be labeled in pixels by the caller.
double? calibratedDistance(double pixels, {double? mmPerPixel}) {
  if (!pixels.isFinite ||
      pixels < 0 ||
      mmPerPixel == null ||
      !mmPerPixel.isFinite ||
      mmPerPixel <= 0) {
    return null;
  }
  return pixels * mmPerPixel;
}
