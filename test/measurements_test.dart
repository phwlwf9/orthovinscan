import 'package:flutter_test/flutter_test.dart';
import 'package:orthoai/features/viewer/measurements.dart';

void main() {
  test('distance uses image pixels rather than screen scale', () {
    expect(distancePixels(const Offset(0, 0), const Offset(3, 4)), 5);
    expect(distancePixels(const Offset(100, 50), const Offset(103, 54)), 5);
  });

  test('angle handles perpendicular, straight and degenerate arms', () {
    expect(
      angleDegrees(const Offset(1, 0), Offset.zero, const Offset(0, 1)),
      closeTo(90, 1e-9),
    );
    expect(
      angleDegrees(const Offset(1, 0), Offset.zero, const Offset(-1, 0)),
      closeTo(180, 1e-9),
    );
    expect(angleDegrees(Offset.zero, Offset.zero, const Offset(1, 0)), isNull);
  });

  test('millimeters require valid explicit calibration', () {
    expect(calibratedDistance(20), isNull);
    expect(calibratedDistance(20, mmPerPixel: 0), isNull);
    expect(calibratedDistance(20, mmPerPixel: -1), isNull);
    expect(calibratedDistance(20, mmPerPixel: double.nan), isNull);
    expect(calibratedDistance(-1, mmPerPixel: 0.5), isNull);
    expect(calibratedDistance(20, mmPerPixel: 0.5), 10);
  });
}
