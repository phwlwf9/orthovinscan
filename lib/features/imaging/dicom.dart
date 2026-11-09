import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class DicomException implements Exception {
  const DicomException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Patient-relative labels of the stored image, before any viewer rotation.
/// Direction cosines follow DICOM's LPS patient coordinate system.
class DicomOrientation {
  const DicomOrientation({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });
  final String top;
  final String bottom;
  final String left;
  final String right;

  @override
  String toString() =>
      'Top: $top · Bottom: $bottom · Left: $left · Right: $right';
}

/// Narrow, explicit DICOM Part 10 decoder. Unsupported transfer syntaxes,
/// color, multi-frame, encapsulated pixels, and undefined-length metadata
/// sequences fail closed rather than being silently interpreted.
class DicomImage {
  DicomImage._({
    required this.rows,
    required this.columns,
    required this.values,
    required this.monochrome1,
    required this.defaultWindowCenter,
    required this.defaultWindowWidth,
    required this.transferSyntax,
    this.spacingX,
    this.spacingY,
    this.orientation,
  });
  final int rows;
  final int columns;
  final Float64List values;
  final bool monochrome1;
  final double defaultWindowCenter;
  final double defaultWindowWidth;
  final String transferSyntax;
  final double? spacingX;
  final double? spacingY;
  final DicomOrientation? orientation;

  static DicomImage decode(Uint8List bytes, {int maxPixels = 24000000}) {
    if (bytes.length < 132 ||
        String.fromCharCodes(bytes.sublist(128, 132)) != 'DICM') {
      throw const DicomException(
        'Chỉ hỗ trợ DICOM Part 10 có tiền tố DICM / DICOM Part 10 preamble required.',
      );
    }
    final data = ByteData.sublistView(bytes);
    var cursor = 132;
    var explicit = true;
    var inMeta = true;
    String? syntax;
    final fields = <int, Uint8List>{};
    Uint8List? pixels;
    const supported = {'1.2.840.10008.1.2', '1.2.840.10008.1.2.1'};
    const longVr = {
      'OB',
      'OD',
      'OF',
      'OL',
      'OV',
      'OW',
      'SQ',
      'SV',
      'UC',
      'UN',
      'UR',
      'UT',
      'UV',
    };
    const validVr = {
      'AE',
      'AS',
      'AT',
      'CS',
      'DA',
      'DS',
      'DT',
      'FD',
      'FL',
      'IS',
      'LO',
      'LT',
      'OB',
      'OD',
      'OF',
      'OL',
      'OV',
      'OW',
      'PN',
      'SH',
      'SL',
      'SQ',
      'SS',
      'ST',
      'SV',
      'TM',
      'UC',
      'UI',
      'UL',
      'UN',
      'UR',
      'US',
      'UT',
      'UV',
    };
    const retainedTags = {
      0x00280002,
      0x00280004,
      0x00280008,
      0x00280010,
      0x00280011,
      0x00280030,
      0x00280100,
      0x00280101,
      0x00280102,
      0x00280103,
      0x00281050,
      0x00281051,
      0x00281052,
      0x00281053,
      0x00281056,
      0x00200037,
      0x20500020,
    };
    while (cursor < bytes.length) {
      if (cursor + 8 > bytes.length) {
        throw const DicomException(
          'DICOM bị cắt cụt / Truncated DICOM element.',
        );
      }
      final group = data.getUint16(cursor, Endian.little);
      final element = data.getUint16(cursor + 2, Endian.little);
      if (inMeta && group != 0x0002) {
        inMeta = false;
        syntax ??= '1.2.840.10008.1.2';
        if (!supported.contains(syntax)) {
          throw const DicomException(
            'Transfer syntax DICOM chưa hỗ trợ: chỉ nhận implicit/explicit little-endian không nén. / Unsupported transfer syntax.',
          );
        }
        explicit = syntax == '1.2.840.10008.1.2.1';
      }
      final tag = (group << 16) | element;
      int length;
      int header;
      if (explicit) {
        final vr = String.fromCharCodes(bytes.sublist(cursor + 4, cursor + 6));
        if (!validVr.contains(vr)) {
          throw const DicomException(
            'DICOM có VR không hợp lệ / Invalid DICOM value representation.',
          );
        }
        if (longVr.contains(vr)) {
          if (cursor + 12 > bytes.length) {
            throw const DicomException(
              'DICOM bị cắt cụt / Truncated DICOM element.',
            );
          }
          header = 12;
          length = data.getUint32(cursor + 8, Endian.little);
        } else {
          header = 8;
          length = data.getUint16(cursor + 6, Endian.little);
        }
      } else {
        header = 8;
        length = data.getUint32(cursor + 4, Endian.little);
      }
      if (length == 0xffffffff) {
        throw const DicomException(
          'Không hỗ trợ chuỗi DICOM độ dài không xác định hoặc pixel nén. / Undefined-length sequences or compressed pixels unsupported.',
        );
      }
      if (tag == 0x00283000 || tag == 0x00283010 || tag == 0x20500010) {
        throw const DicomException(
          'DICOM LUT chưa hỗ trợ / Modality, VOI, or presentation LUT unsupported.',
        );
      }
      final start = cursor + header;
      final end = start + length;
      if (end > bytes.length) {
        throw const DicomException('DICOM bị cắt cụt / Truncated DICOM value.');
      }
      if (tag == 0x00020010) {
        syntax = _text(Uint8List.sublistView(bytes, start, end));
        if (!supported.contains(syntax)) {
          throw const DicomException(
            'Transfer syntax DICOM chưa hỗ trợ: chỉ nhận implicit/explicit little-endian không nén. / Unsupported transfer syntax.',
          );
        }
      } else if (retainedTags.contains(tag)) {
        if (fields.containsKey(tag)) {
          throw const DicomException(
            'Thẻ DICOM quan trọng bị lặp / Duplicate critical DICOM tag.',
          );
        }
        fields[tag] = Uint8List.sublistView(bytes, start, end);
      } else if (tag == 0x7fe00010) {
        pixels = Uint8List.sublistView(bytes, start, end);
        break;
      }
      cursor = end;
    }
    int ushort(int tag, {int? fallback}) {
      final raw = fields[tag];
      if (raw == null && fallback != null) return fallback;
      if (raw == null || raw.length != 2) {
        throw const DicomException(
          'Thiếu thông số pixel DICOM / Missing or invalid DICOM pixel descriptor.',
        );
      }
      return ByteData.sublistView(raw).getUint16(0, Endian.little);
    }

    double number(int tag, {required double fallback}) {
      final raw = fields[tag];
      if (raw == null) return fallback;
      final value = double.tryParse(_text(raw).split('\\').first);
      if (value == null || !value.isFinite) {
        throw const DicomException(
          'Thông số DICOM không hợp lệ / Invalid numeric DICOM descriptor.',
        );
      }
      return value;
    }

    final rows = ushort(0x00280010);
    final columns = ushort(0x00280011);
    if (rows <= 0 || columns <= 0 || rows * columns > maxPixels) {
      throw const DicomException(
        'Kích thước DICOM không hợp lệ hoặc quá 24 MP / Invalid or excessive DICOM dimensions.',
      );
    }
    if (ushort(0x00280002, fallback: 1) != 1) {
      throw const DicomException(
        'Chỉ hỗ trợ DICOM đơn sắc / Only monochrome DICOM is supported.',
      );
    }
    final frames = number(0x00280008, fallback: 1);
    if (frames != 1) {
      throw const DicomException(
        'Chỉ hỗ trợ DICOM đơn khung / Multi-frame DICOM unsupported.',
      );
    }
    final photometric = fields[0x00280004] == null
        ? ''
        : _text(fields[0x00280004]!);
    if (photometric != 'MONOCHROME1' && photometric != 'MONOCHROME2') {
      throw const DicomException(
        'Photometric DICOM chưa hỗ trợ / Unsupported DICOM photometric interpretation.',
      );
    }
    final presentationShape = fields[0x20500020];
    if (presentationShape != null) {
      final expected = photometric == 'MONOCHROME1' ? 'INVERSE' : 'IDENTITY';
      if (_text(presentationShape) != expected) {
        throw const DicomException(
          'Presentation LUT không phù hợp / Unsupported presentation LUT shape.',
        );
      }
    }
    final allocated = ushort(0x00280100);
    final stored = ushort(0x00280101);
    final highBit = ushort(0x00280102);
    final signed = ushort(0x00280103);
    if ((allocated != 8 && allocated != 16) ||
        stored < 1 ||
        stored > allocated ||
        highBit >= allocated ||
        highBit < stored - 1 ||
        signed > 1) {
      throw const DicomException(
        'Kiểu pixel DICOM chưa hỗ trợ hoặc không hợp lệ / Unsupported or invalid DICOM bit layout.',
      );
    }
    final needed = rows * columns * (allocated ~/ 8);
    if (pixels == null ||
        pixels.length < needed ||
        pixels.length > needed + (needed.isOdd ? 1 : 0)) {
      throw const DicomException(
        'Dữ liệu pixel DICOM thiếu hoặc không khớp / DICOM pixel length mismatch.',
      );
    }
    final slope = number(0x00281053, fallback: 1);
    final intercept = number(0x00281052, fallback: 0);
    if (slope == 0) {
      throw const DicomException(
        'Rescale slope DICOM không hợp lệ / Invalid DICOM rescale slope.',
      );
    }
    final values = Float64List(rows * columns);
    final pixelData = ByteData.sublistView(pixels);
    final mask = (1 << stored) - 1;
    final shift = highBit - stored + 1;
    var minimum = double.infinity;
    var maximum = double.negativeInfinity;
    for (var i = 0; i < values.length; i++) {
      var value = allocated == 8
          ? pixelData.getUint8(i)
          : pixelData.getUint16(i * 2, Endian.little);
      value = (value >> shift) & mask;
      if (signed == 1 && (value & (1 << (stored - 1))) != 0) {
        value -= 1 << stored;
      }
      final rescaled = value * slope + intercept;
      if (!rescaled.isFinite) {
        throw const DicomException(
          'Giá trị pixel DICOM không hợp lệ / Invalid rescaled DICOM value.',
        );
      }
      values[i] = rescaled;
      minimum = math.min(minimum, rescaled);
      maximum = math.max(maximum, rescaled);
    }
    if (fields.containsKey(0x00281050) != fields.containsKey(0x00281051)) {
      throw const DicomException(
        'Window/level DICOM không đầy đủ / Incomplete DICOM window/level.',
      );
    }
    final voiFunction = fields[0x00281056];
    if (voiFunction != null && _text(voiFunction) != 'LINEAR') {
      throw const DicomException(
        'Chỉ hỗ trợ cửa sổ DICOM LINEAR / Nonlinear DICOM VOI unsupported.',
      );
    }
    final center = number(0x00281050, fallback: (minimum + maximum + 1) / 2);
    final width = number(
      0x00281051,
      fallback: math.max(1, maximum - minimum + 1),
    );
    if (width < 1) {
      throw const DicomException(
        'Window width DICOM phải >= 1 / Invalid DICOM window width.',
      );
    }
    double? spacingX, spacingY;
    final spacingRaw = fields[0x00280030];
    if (spacingRaw != null) {
      final parts = _text(spacingRaw).split('\\').map(double.tryParse).toList();
      if (parts.length == 2 &&
          parts.every((x) => x != null && x.isFinite && x > 0)) {
        spacingY = parts[0];
        spacingX = parts[1];
      }
    }
    return DicomImage._(
      rows: rows,
      columns: columns,
      values: values,
      monochrome1: photometric == 'MONOCHROME1',
      defaultWindowCenter: center,
      defaultWindowWidth: width,
      transferSyntax: syntax ?? '1.2.840.10008.1.2',
      spacingX: spacingX,
      spacingY: spacingY,
      orientation: _orientation(fields[0x00200037]),
    );
  }

  /// Standard linear VOI window, including rescale and MONOCHROME1 inversion.
  Uint8List render({double? center, double? width}) {
    final c = center ?? defaultWindowCenter;
    final w = width ?? defaultWindowWidth;
    if (!c.isFinite || !w.isFinite || w < 1) {
      throw const DicomException(
        'Window/level không hợp lệ / Invalid window/level.',
      );
    }
    final image = img.Image(width: columns, height: rows, numChannels: 3);
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      double displayed;
      if (value <= c - 0.5 - (w - 1) / 2) {
        displayed = 0;
      } else if (value > c - 0.5 + (w - 1) / 2) {
        displayed = 255;
      } else {
        displayed = ((value - (c - 0.5)) / (w - 1) + 0.5) * 255;
      }
      final grey = (monochrome1 ? 255 - displayed : displayed).round().clamp(
        0,
        255,
      );
      image.setPixelRgb(i % columns, i ~/ columns, grey, grey, grey);
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  static String _text(Uint8List value) =>
      String.fromCharCodes(value).replaceAll('\u0000', '').trim();

  static DicomOrientation? _orientation(Uint8List? raw) {
    if (raw == null) return null;
    final p = _text(raw).split('\\').map(double.tryParse).toList();
    if (p.length != 6 || p.any((n) => n == null || !n.isFinite)) return null;
    final row = p.take(3).cast<double>().toList();
    final column = p.skip(3).cast<double>().toList();
    double norm(List<double> vector) =>
        math.sqrt(vector.fold<double>(0, (s, v) => s + v * v));
    final dot = row[0] * column[0] + row[1] * column[1] + row[2] * column[2];
    if ((norm(row) - 1).abs() > 0.02 ||
        (norm(column) - 1).abs() > 0.02 ||
        dot.abs() > 0.02) {
      return null;
    }
    String label(List<double> vector, double sign) {
      final indices = [0, 1, 2]
        ..sort((a, b) => vector[b].abs().compareTo(vector[a].abs()));
      const positive = ['L', 'P', 'H'];
      const negative = ['R', 'A', 'F'];
      return indices
          .where((i) => vector[i].abs() > 0.2)
          .map((i) => vector[i] * sign > 0 ? positive[i] : negative[i])
          .join();
    }

    return DicomOrientation(
      top: label(column, -1),
      bottom: label(column, 1),
      left: label(row, -1),
      right: label(row, 1),
    );
  }
}
