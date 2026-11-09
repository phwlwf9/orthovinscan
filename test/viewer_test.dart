import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:orthoai/features/viewer/viewer_screen.dart';

void main() {
  Uint8List sample() =>
      Uint8List.fromList(img.encodePng(img.Image(width: 120, height: 60)));

  testWidgets('DICOM spacing requires explicit clinician confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(imageBytes: sample(), pixelSpacingMm: .25),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đơn vị: pixel · Chưa hiệu chuẩn mm'), findsOneWidget);
    expect(find.byTooltip('Lưu ảnh và chú thích'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rotation preserves normalized measurements and exports real PNGs',
    (tester) async {
      ViewerResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<ViewerResult>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ViewerScreen(
                        imageBytes: sample(),
                        initialSession: {
                          'marks': [
                            {
                              'tool': 'distance',
                              'points': [
                                [.1, .1],
                                [.8, .5],
                              ],
                            },
                          ],
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoay'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Lưu ảnh và chú thích'));
        for (var i = 0; i < 30 && result == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      final edited = img.decodePng(result!.editedPng)!;
      expect(edited.width, 60);
      expect(edited.height, 120);
      expect(img.decodePng(result!.annotatedPng), isNotNull);
      final marks = result!.session['marks'] as List;
      final first = ((marks.single as Map)['points'] as List).first as List;
      expect(first[0], closeTo(.9, 1e-9));
      expect(first[1], closeTo(.1, 1e-9));
      expect(result!.session.containsKey('calibration'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
