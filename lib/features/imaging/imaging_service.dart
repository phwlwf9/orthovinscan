import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'dicom.dart';

/// An intentionally metadata-free display copy. Never includes patient tags.
class PreparedRadiograph {
  const PreparedRadiograph({
    required this.pngBytes,
    required this.width,
    required this.height,
    required this.sourceFormat,
    this.pixelSpacingMm,
    this.warning,
    this.dicom,
  });

  final Uint8List pngBytes;
  final int width;
  final int height;
  final String sourceFormat;

  /// Null until spacing has been independently validated by the clinician.
  /// DICOM's unvalidated PixelSpacing is available on [dicom] for inspection.
  final double? pixelSpacingMm;
  final String? warning;
  final DicomImage? dicom;
}

class ImagingException implements Exception {
  const ImagingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImagingService {
  static const maxInputBytes = 50 * 1024 * 1024;
  static const maxPixels = 24000000;

  /// Validates, auto-orients JPEG/PNG, and creates a fresh PNG without EXIF.
  /// This method is synchronous; callers should show their import progress UI.
  static PreparedRadiograph prepare(Uint8List bytes, String filename) {
    if (bytes.isEmpty) {
      throw const ImagingException('Tệp rỗng / Empty file.');
    }
    if (bytes.length > maxInputBytes) {
      throw const ImagingException('Tệp vượt quá 50 MB / File exceeds 50 MB.');
    }
    final extension = filename.toLowerCase().split('.').last;
    final hasDicomPreamble =
        bytes.length >= 132 &&
        String.fromCharCodes(bytes.sublist(128, 132)) == 'DICM';
    if (hasDicomPreamble || extension == 'dcm' || extension == 'dicom') {
      try {
        final dicom = DicomImage.decode(bytes, maxPixels: maxPixels);
        final png = dicom.render();
        final warnings = <String>[
          'DICOM: cần xác nhận hướng ảnh và hiệu chuẩn kích thước trước khi đo mm. '
              '/ Confirm orientation and calibration before measuring in mm.',
          if (dicom.orientation == null)
            'DICOM không có hướng bệnh nhân đáng tin cậy / Patient orientation unavailable.',
        ];
        return PreparedRadiograph(
          pngBytes: png,
          width: dicom.columns,
          height: dicom.rows,
          sourceFormat: 'DICOM',
          dicom: dicom,
          warning: warnings.join('\n'),
        );
      } on DicomException catch (error) {
        throw ImagingException(error.message);
      }
    }
    final isJpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10;
    if (!isJpeg && !isPng) {
      throw const ImagingException(
        'Định dạng chưa hỗ trợ. Dùng JPEG/PNG hoặc DICOM đơn khung không nén. '
        'HEIC cần được hệ điều hành chuyển sang JPEG/PNG. '
        '/ Unsupported format: use JPEG/PNG or uncompressed single-frame DICOM.',
      );
    }
    try {
      // Read dimensions before decoding to limit decompression allocations.
      final decoder = isPng ? img.PngDecoder() : img.JpegDecoder();
      final info = decoder.startDecode(bytes);
      if (info == null ||
          info.width <= 0 ||
          info.height <= 0 ||
          info.width * info.height > maxPixels) {
        throw const ImagingException(
          'Ảnh không hợp lệ hoặc quá 24 megapixel / Invalid image or over 24 MP.',
        );
      }
      final decoded = decoder.decodeFrame(0);
      if (decoded == null) {
        throw const ImagingException(
          'Không giải mã được ảnh / Cannot decode image.',
        );
      }
      final oriented = img
          .bakeOrientation(decoded)
          .convert(format: img.Format.uint8, numChannels: 4);
      // Constructing a new image strips EXIF, ICC and text fields from output.
      final clean = img.Image(
        width: oriented.width,
        height: oriented.height,
        numChannels: 3,
      );
      for (final pixel in oriented) {
        final alpha = pixel.a / 255;
        clean.setPixelRgb(
          pixel.x,
          pixel.y,
          (pixel.r * alpha).round(),
          (pixel.g * alpha).round(),
          (pixel.b * alpha).round(),
        );
      }
      return PreparedRadiograph(
        pngBytes: Uint8List.fromList(img.encodePng(clean)),
        width: clean.width,
        height: clean.height,
        sourceFormat: isJpeg ? 'JPEG' : 'PNG',
        warning: qualityWarning(clean),
      );
    } on ImagingException {
      rethrow;
    } catch (_) {
      throw const ImagingException(
        'Ảnh hỏng hoặc không hợp lệ / Corrupt or invalid image.',
      );
    }
  }

  /// A simple photographic screening heuristic, not a diagnostic quality score.
  static String? qualityWarning(img.Image image) {
    final scale = math.min(1.0, 128 / math.max(image.width, image.height));
    final small = img.copyResize(
      image,
      width: math.max(1, (image.width * scale).round()),
      height: math.max(1, (image.height * scale).round()),
    );
    if (small.width < 3 || small.height < 3) {
      return 'Ảnh quá nhỏ / Image too small.';
    }
    double sum = 0, sumSquares = 0;
    var clipped = 0, count = 0;
    double luminance(int x, int y) {
      final p = small.getPixel(x, y);
      return 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
    }

    for (var y = 1; y < small.height - 1; y++) {
      for (var x = 1; x < small.width - 1; x++) {
        final center = luminance(x, y);
        final laplacian =
            luminance(x - 1, y) +
            luminance(x + 1, y) +
            luminance(x, y - 1) +
            luminance(x, y + 1) -
            4 * center;
        sum += laplacian;
        sumSquares += laplacian * laplacian;
        if (center < 3 || center > 252) clipped++;
        count++;
      }
    }
    final variance = sumSquares / count - math.pow(sum / count, 2);
    final warnings = <String>[];
    if (variance < 16) {
      warnings.add(
        'Ảnh có thể mờ hoặc ít chi tiết / Possible blur or low detail',
      );
    }
    if (clipped / count > 0.55) {
      warnings.add(
        'Nhiều vùng quá sáng/tối / Extensive clipped highlights or shadows',
      );
    }
    if (warnings.isEmpty) return null;
    return '${warnings.join('. ')}. Kiểm tra ảnh gốc; phép kiểm này không xác nhận chất lượng chẩn đoán. '
        '/ Check the original; this heuristic does not validate diagnostic quality.';
  }
}
