import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:orthoai/core/case_repository.dart';
import 'package:orthoai/core/models.dart';
import 'package:orthoai/features/report/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Authenticated local case storage', () {
    late Directory directory;
    late CaseRepository repository;
    final key = List<int>.generate(32, (i) => i);
    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'orthoai-storage-test-',
      );
      repository = await CaseRepository.forTesting(directory, key);
    });
    tearDown(() async => directory.delete(recursive: true));

    CaseRecord example({String id = 'OA-123'}) => CaseRecord(
      id: id,
      createdAt: DateTime.utc(2026, 11, 9),
      regionId: 'distal_radius',
      findings: 'Sensitive educational finding',
      observations: {'articular': 'extra'},
      clinical: {'side': 'left'},
      images: [
        CaseImage(
          id: 'image-1',
          originalBytes: Uint8List.fromList([1, 2, 3]),
          pngBytes: Uint8List.fromList([4, 5, 6]),
          sourceFormat: 'PNG',
          session: {'brightness': 0.2},
        ),
      ],
    );

    test(
      'round trip keeps images and findings but never stores plaintext',
      () async {
        final record = example();
        await repository.save(record);
        final encoded = await File(
          '${directory.path}/OA-123.ortho',
        ).readAsString();
        expect(encoded, isNot(contains(record.findings)));
        expect(encoded, isNot(contains('distal_radius')));
        final restored = await repository.load('OA-123');
        expect(restored.toJson(), record.toJson());
        expect((await repository.list()).single.id, 'OA-123');
        record.findings = 'Updated finding';
        await repository.save(record);
        expect((await repository.load('OA-123')).findings, 'Updated finding');
        await repository.delete('OA-123');
        expect(await repository.list(), isEmpty);
        expect(await directory.list().toList(), isEmpty);
      },
    );

    test(
      'wrong key and tampering fail without destroying original data',
      () async {
        final record = example();
        await repository.save(record);
        final file = File('${directory.path}/OA-123.ortho');
        final original = await file.readAsString();
        final wrongKey = await CaseRepository.forTesting(
          directory,
          List<int>.filled(32, 99),
        );
        await expectLater(
          wrongKey.load(record.id),
          throwsA(isA<CaseStorageException>()),
        );
        await expectLater(
          wrongKey.save(record),
          throwsA(isA<CaseStorageException>()),
        );
        expect(await file.readAsString(), original);
        final envelope = jsonDecode(original) as Map<String, dynamic>;
        final ciphertext = base64Decode(envelope['ciphertext'] as String);
        ciphertext[0] ^= 1;
        envelope['ciphertext'] = base64Encode(ciphertext);
        await file.writeAsString(jsonEncode(envelope));
        await expectLater(
          repository.load(record.id),
          throwsA(isA<CaseStorageException>()),
        );
        expect(await file.exists(), isTrue);
      },
    );

    test('case identifiers cannot escape app storage', () async {
      final record = CaseRecord(id: '../escape', createdAt: DateTime.now());
      await expectLater(
        repository.save(record),
        throwsA(isA<CaseStorageException>()),
      );
      await expectLater(
        repository.delete('../escape'),
        throwsA(isA<CaseStorageException>()),
      );
      expect(await directory.list().toList(), isEmpty);
    });

    test(
      'history retains lightweight summaries and preserves unreadable cases',
      () async {
        await repository.save(example(id: 'OA-GOOD'));
        await repository.save(example(id: 'OA-BAD'));
        final damagedFile = File('${directory.path}/OA-BAD.ortho');
        final envelope =
            jsonDecode(await damagedFile.readAsString())
                as Map<String, dynamic>;
        final mac = base64Decode(envelope['mac'] as String);
        mac[0] ^= 1;
        envelope['mac'] = base64Encode(mac);
        final damagedContents = jsonEncode(envelope);
        await damagedFile.writeAsString(damagedContents);

        final history = await repository.list();
        expect(history.map((record) => record.id), ['OA-GOOD']);
        expect(repository.unreadableIds, ['OA-BAD']);
        expect(await damagedFile.readAsString(), damagedContents);
        final summary = history.single;
        expect(summary.images, isEmpty);
        expect(summary.imageCount, 1);
        expect(summary.summaryImageCount, 1);
        expect(summary.toJson().containsKey('summaryImageCount'), isFalse);
        await expectLater(
          repository.save(summary),
          throwsA(isA<CaseStorageException>()),
        );
        final loaded = await repository.load('OA-GOOD');
        expect(loaded.summaryImageCount, isNull);
        expect(loaded.images.single.pngBytes, [4, 5, 6]);
        expect(loaded.imageCount, 1);
        summary.clinical['side'] = 'right';
        expect(loaded.clinical['side'], 'left');
        expect(loaded.toJson(), example(id: 'OA-GOOD').toJson());

        await repository.delete('OA-BAD');
        expect(await repository.list(), hasLength(1));
        expect(repository.unreadableIds, isEmpty);
      },
    );
  });

  test(
    'unknown clinical findings are not normal and red flags are explicit',
    () {
      expect(clinicalLabel('vascular', null), contains('Chưa rõ'));
      expect(redFlags({}), isEmpty);
      expect(
        redFlags({'vascular': 'compromised', 'open': 'open'}),
        hasLength(2),
      );
    },
  );

  test(
    'offline Vietnamese PDF handles missing data and annotated image',
    () async {
      final image = im.Image(width: 32, height: 32);
      im.fill(image, color: im.ColorRgb8(80, 90, 100));
      final png = Uint8List.fromList(im.encodePng(image));
      final record = CaseRecord(
        id: 'OA-PDF-1',
        createdAt: DateTime.utc(2026, 11, 9),
        findings: 'Ghi nhận gãy đầu dưới xương quay — cần đánh giá thêm.',
        images: [
          CaseImage(
            id: 'image-1',
            originalBytes: Uint8List.fromList([0]),
            pngBytes: png,
            annotatedBytes: png,
            sourceFormat: 'PNG',
          ),
        ],
      );
      final bytes = await ReportService.build(
        record,
        regionName: 'Đầu dưới xương quay',
        treatmentNotes: [],
        references: ['https://surgeryreference.aofoundation.org/'],
        missing: ['Chưa xác nhận phân loại', 'Chưa có phim nghiêng'],
      );
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(10000));
      expect(RegExp(r'/Type\s*/Page\b').hasMatch(latin1.decode(bytes)), isTrue);
      // The report only receives raster derivatives, never original DICOM data.
      expect(latin1.decode(bytes), isNot(contains('DICM')));
    },
  );
}
