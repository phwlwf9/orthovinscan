import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:orthoai/features/imaging/dicom.dart';
import 'package:orthoai/features/imaging/imaging_service.dart';
import 'package:orthoai/features/imaging/inference.dart';

Uint8List _us(int value) =>
    (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List();
Uint8List _str(String value, {bool uid = false}) => Uint8List.fromList([
  ...value.codeUnits,
  if (value.length.isOdd) uid ? 0 : 32,
]);
Uint8List _element(
  int group,
  int tag,
  String vr,
  Uint8List value, {
  bool explicit = true,
}) {
  final long = {'OB', 'OW', 'SQ', 'UN', 'UT'}.contains(vr);
  final length = explicit && long ? 12 : 8;
  final header = ByteData(length)
    ..setUint16(0, group, Endian.little)
    ..setUint16(2, tag, Endian.little);
  if (explicit) {
    header.setUint8(4, vr.codeUnitAt(0));
    header.setUint8(5, vr.codeUnitAt(1));
    if (long) {
      header.setUint32(8, value.length, Endian.little);
    } else {
      header.setUint16(6, value.length, Endian.little);
    }
  } else {
    header.setUint32(4, value.length, Endian.little);
  }
  return Uint8List.fromList([...header.buffer.asUint8List(), ...value]);
}

Uint8List _dicom({
  bool explicit = true,
  String? syntax,
  bool inverse = false,
  bool signed = false,
  int frames = 1,
  int allocated = 16,
  int stored = 12,
  int highBit = 11,
  List<int> values = const [0, 100, 200, 300],
  bool orientation = false,
  int columns = 2,
  String? voi,
  String? presentationShape,
}) {
  final pixelBytes = BytesBuilder();
  for (final value in values) {
    pixelBytes.add(allocated == 8 ? [value] : _us(value));
  }
  if (pixelBytes.length.isOdd) pixelBytes.addByte(0);
  final content = BytesBuilder()
    ..add(Uint8List(128))
    ..add('DICM'.codeUnits)
    ..add(
      _element(
        2,
        0x10,
        'UI',
        _str(
          syntax ?? (explicit ? '1.2.840.10008.1.2.1' : '1.2.840.10008.1.2'),
          uid: true,
        ),
      ),
    );
  void e(int tag, String vr, Uint8List value, [int group = 0x28]) =>
      content.add(_element(group, tag, vr, value, explicit: explicit));
  if (orientation) e(0x37, 'DS', _str('1\\0\\0\\0\\1\\0'), 0x20);
  e(2, 'US', _us(1));
  e(4, 'CS', _str(inverse ? 'MONOCHROME1' : 'MONOCHROME2'));
  e(8, 'IS', _str('$frames'));
  e(0x10, 'US', _us(2));
  e(0x11, 'US', _us(columns));
  e(0x30, 'DS', _str('0.5\\0.5'));
  e(0x100, 'US', _us(allocated));
  e(0x101, 'US', _us(stored));
  e(0x102, 'US', _us(highBit));
  e(0x103, 'US', _us(signed ? 1 : 0));
  if (voi != null) e(0x1056, 'CS', _str(voi));
  if (presentationShape != null) e(0x20, 'CS', _str(presentationShape), 0x2050);
  e(0x10, 'OW', pixelBytes.takeBytes(), 0x7fe0);
  return content.takeBytes();
}

void main() {
  test('JPEG/PNG import creates a real metadata-free display copy', () {
    final source = img.Image(width: 4, height: 4)
      ..setPixelRgb(1, 1, 80, 120, 160);
    final prepared = ImagingService.prepare(
      Uint8List.fromList(img.encodePng(source)),
      'xray.png',
    );
    expect(prepared.width, 4);
    expect(prepared.height, 4);
    expect(prepared.pixelSpacingMm, isNull);
    expect(img.decodePng(prepared.pngBytes)!.getPixel(1, 1).g, 120);
  });

  test('JPEG EXIF rotation is applied and identifiers are removed', () {
    final source = img.Image(width: 4, height: 2);
    source.exif.imageIfd.orientation = 6;
    source.exif.imageIfd.imageDescription = 'TEST_PRIVATE_IDENTIFIER';
    final jpeg = Uint8List.fromList(img.encodeJpg(source));
    final prepared = ImagingService.prepare(jpeg, 'photo.heic');
    // The OS may return a converted JPEG for an original HEIC selection.
    expect(prepared.sourceFormat, 'JPEG');
    expect(prepared.width, 2);
    expect(prepared.height, 4);
    expect(
      String.fromCharCodes(prepared.pngBytes),
      isNot(contains('TEST_PRIVATE_IDENTIFIER')),
    );
    expect(
      img.decodePng(prepared.pngBytes)!.exif.imageIfd.imageDescription,
      isNull,
    );
  });

  test('empty, corrupt, unsupported, and disguised files fail explicitly', () {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      Uint8List.fromList('not an image'.codeUnits),
    ]) {
      expect(
        () => ImagingService.prepare(bytes, 'test.jpg'),
        throwsA(isA<ImagingException>()),
      );
    }
    expect(
      () => ImagingService.prepare(
        Uint8List.fromList('HEIC'.codeUnits),
        'test.heic',
      ),
      throwsA(isA<ImagingException>()),
    );
  });

  test('DICOM explicit and implicit little endian produce expected pixels', () {
    for (final explicit in [true, false]) {
      final decoded = DicomImage.decode(_dicom(explicit: explicit));
      expect(decoded.values, [0, 100, 200, 300]);
      final rendered = img.decodePng(decoded.render())!;
      expect(rendered.getPixel(0, 0).r, 0);
      expect(rendered.getPixel(1, 1).r, 255);
      expect(decoded.spacingX, 0.5);
    }
  });

  test('DICOM signed stored bits and shifted high bit are respected', () {
    final decoded = DicomImage.decode(
      _dicom(signed: true, highBit: 14, values: [0xff8, 0, 8, 0x3ff8]),
    );
    // Stored 12 bits occupy bits 3..14; sign-extension happens after shifting.
    expect(decoded.values, [511, 0, 1, 2047]);
    final negative = DicomImage.decode(
      _dicom(signed: true, values: [0xfff, 0x800, 0, 0x7ff]),
    );
    expect(negative.values, [-1, -2048, 0, 2047]);
  });

  test(
    'MONOCHROME1 is inverted and window/level acts on original intensity',
    () {
      final decoded = DicomImage.decode(_dicom(inverse: true));
      final rendered = img.decodePng(
        decoded.render(center: 150.5, width: 301),
      )!;
      expect(rendered.getPixel(0, 0).r, 255);
      expect(rendered.getPixel(1, 1).r, 0);
      final narrow = img.decodePng(decoded.render(center: 100, width: 1))!;
      expect(narrow.getPixel(0, 0).r, 255);
      expect(narrow.getPixel(1, 0).r, 0);
      expect(() => decoded.render(width: 0), throwsA(isA<DicomException>()));
    },
  );

  test(
    'compatible DICOM presentation shape is honored without double inversion',
    () {
      final normal = DicomImage.decode(_dicom(presentationShape: 'IDENTITY'));
      final inverse = DicomImage.decode(
        _dicom(inverse: true, presentationShape: 'INVERSE'),
      );
      expect(img.decodePng(normal.render())!.getPixel(0, 0).r, 0);
      expect(img.decodePng(inverse.render())!.getPixel(0, 0).r, 255);
      expect(
        () => DicomImage.decode(_dicom(presentationShape: 'INVERSE')),
        throwsA(isA<DicomException>()),
      );
    },
  );

  test('DICOM orientation labels and unvalidated calibration are separate', () {
    final prepared = ImagingService.prepare(
      _dicom(orientation: true),
      'test.dcm',
    );
    expect(prepared.pixelSpacingMm, isNull);
    expect(prepared.dicom!.spacingY, .5);
    expect(prepared.dicom!.orientation!.top, 'A');
    expect(prepared.dicom!.orientation!.right, 'L');
    expect(prepared.warning, contains('calibration'));
  });

  test(
    'unsupported DICOM compression, frames, dimensions, and truncation fail closed',
    () {
      for (final bytes in [
        _dicom(syntax: '1.2.840.10008.1.2.4.50'),
        _dicom(frames: 2),
        _dicom(columns: 3),
        _dicom(voi: 'SIGMOID'),
        Uint8List.fromList(_dicom().sublist(0, _dicom().length - 1)),
      ]) {
        expect(() => DicomImage.decode(bytes), throwsA(isA<DicomException>()));
      }
    },
  );

  test(
    'future preprocessing is deterministic and preserves letterbox transform',
    () {
      final source = img.Image(width: 4, height: 2);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      final prepared = ImagingService.prepare(
        Uint8List.fromList(img.encodePng(source)),
        'test.png',
      );
      final input = ImagePreprocessing.grayscaleLetterbox(
        prepared,
        width: 4,
        height: 4,
      );
      expect(input.padY, 1);
      expect(input.padX, 0);
      expect(input.scale, 1);
      expect(input.tensor[0], 0);
      expect(input.tensor[4], closeTo(1, .001));
    },
  );

  test('unavailable inference never fabricates candidate diagnoses', () async {
    const service = UnavailableFractureInferenceService();
    expect(service.availability, InferenceAvailability.unavailable);
    expect(service.manifest, isNull);
    final source = img.Image(width: 2, height: 2);
    final prepared = ImagingService.prepare(
      Uint8List.fromList(img.encodePng(source)),
      'test.png',
    );
    await expectLater(
      service.analyze(prepared, view: 'AP'),
      throwsA(isA<ImagingException>()),
    );
  });
}
