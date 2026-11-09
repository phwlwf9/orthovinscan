import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:orthoai/core/app_controller.dart';
import 'package:orthoai/core/case_repository.dart';
import 'package:orthoai/core/models.dart';
import 'package:orthoai/features/case_workspace.dart';
import 'package:orthoai/features/classification/clinical_knowledge.dart';
import 'package:orthoai/features/imaging/imaging_service.dart';
import 'package:orthoai/features/viewer/viewer_screen.dart';
import 'package:orthoai/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'image, annotation, clinical assessment, classification, references and PDF workflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({'consent.v1': true});
      final setup = await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp('orthoai-ui-');
        final repository = await CaseRepository.forTesting(
          directory,
          List<int>.filled(32, 42),
        );
        final controller = AppController(
          repository: repository,
          knowledge: await ClinicalKnowledge.load(),
          prefs: await SharedPreferences.getInstance(),
        );
        await controller.initialize();
        return (directory, repository, controller);
      });
      final (directory, repository, controller) = setup!;
      addTearDown(() async => directory.delete(recursive: true));
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const OrthoApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ca mới'), findsOneWidget);
      await tester.tap(find.text('Ca mới'));
      await tester.pumpAndSettle();
      expect(find.byType(CaseWorkspace), findsOneWidget);
      expect(controller.current, isNotNull);

      // This is a synthetic test fixture, not an X-ray or a model prediction.
      final raster = img.Image(width: 120, height: 240);
      img.fill(raster, color: img.ColorRgb8(90, 90, 90));
      final png = Uint8List.fromList(img.encodePng(raster));
      final prepared = ImagingService.prepare(png, 'synthetic-fixture.png');
      expect(prepared.width, 120);
      expect(prepared.height, 240);
      controller.current!.images.add(
        CaseImage(
          id: 'synthetic-ui-fixture',
          originalBytes: png,
          pngBytes: prepared.pngBytes,
          sourceFormat: prepared.sourceFormat,
          warning: prepared.warning,
        ),
      );
      controller.changed(invalidate: true);
      await tester.pumpAndSettle();

      // Native pickers/camera are outside this host test; the real import
      // decoder and viewer/annotation/export code run without mocks here.
      await tester.tap(find.text('Xem & đo'));
      await tester.pumpAndSettle();
      expect(find.byType(ViewerScreen), findsOneWidget);
      await tester.tap(find.text('Di chuyển / phóng to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đo khoảng cách').last);
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(InteractiveViewer).first);
      final drawing = await tester.startGesture(center - const Offset(40, 40));
      await drawing.moveBy(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 20));
      await drawing.moveBy(const Offset(30, 30));
      await tester.pump(const Duration(milliseconds: 20));
      await drawing.moveBy(const Offset(30, 30));
      await drawing.up();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Lưu ảnh và chú thích'));
        for (
          var i = 0;
          i < 300 && controller.current!.images.single.annotatedBytes == null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.byType(ViewerScreen), findsNothing);
      final image = controller.current!.images.single;
      expect(img.decodePng(image.annotatedBytes!), isNotNull);
      expect(image.annotatedBytes, isNot(equals(image.editedBytes)));
      expect((image.session['marks'] as List).single['tool'], 'distance');
      expect(image.session.containsKey('calibration'), isFalse);

      Future<void> tab(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      Future<void> chooseIn(Finder scroll, Key key, String label) async {
        final field = find.byKey(key);
        await tester.scrollUntilVisible(field, 200, scrollable: scroll);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await tab('Lâm sàng');
      final clinicalScroll = find
          .descendant(
            of: find.byType(ClinicalPanel),
            matching: find.byType(Scrollable),
          )
          .first;
      await chooseIn(clinicalScroll, const ValueKey('age.null'), 'Người lớn');
      await chooseIn(clinicalScroll, const ValueKey('side.null'), 'Trái');
      expect(controller.current!.clinical['side'], 'left');
      expect(controller.current!.clinical['vascular'], isNull);

      await tab('Báo cáo');
      final findings = find
          .descendant(
            of: find.byType(ReportPanel),
            matching: find.byType(TextFormField),
          )
          .first;
      await tester.enterText(
        findings,
        'Quan sát kiểm thử tổng hợp do người dùng nhập.',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();

      await tab('Phân loại');
      final panel = find.byType(ClassificationPanel);
      final panelScroll = find
          .descendant(of: panel, matching: find.byType(Scrollable))
          .first;

      await chooseIn(
        panelScroll,
        const ValueKey<String?>(null),
        'Đầu dưới xương quay',
      );
      await chooseIn(
        panelScroll,
        const ValueKey('distal_radius.adult.null'),
        'Có',
      );
      await chooseIn(
        panelScroll,
        const ValueKey('distal_radius.views.null'),
        'Có',
      );
      await chooseIn(
        panelScroll,
        const ValueKey('distal_radius.joint.null'),
        'Không',
      );
      expect(controller.current!.confirmedCode, isNull);
      expect(
        controller.knowledge
            .evaluate('distal_radius', controller.current!.observations)
            .candidates
            .single
            .code,
        '2R3A',
      );

      final confirm = find.text('Bác sĩ xác nhận phân loại');
      await tester.scrollUntilVisible(confirm, 250, scrollable: panelScroll);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận của bác sĩ'), findsOneWidget);
      expect(controller.current!.confirmedCode, isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận'));
      await tester.pumpAndSettle();
      expect(controller.current!.confirmedCode, '2R3A');
      expect(controller.current!.confirmedAt, isNotNull);
      expect(find.text('Bác sĩ đã xác nhận: 2R3A'), findsOneWidget);

      await tab('Hướng xử trí');
      expect(find.text('Hỗ trợ xem xét hướng điều trị'), findsOneWidget);
      final treatmentScroll = find
          .descendant(
            of: find.byType(TreatmentPanel),
            matching: find.byType(Scrollable),
          )
          .first;
      final reference = find.descendant(
        of: find.byType(TreatmentPanel),
        matching: find.text('Open in AO Surgery Reference'),
      );
      await tester.scrollUntilVisible(
        reference,
        250,
        scrollable: treatmentScroll,
      );
      final referenceButton = find
          .ancestor(
            of: reference,
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          )
          .first;
      expect(tester.widget<TextButton>(referenceButton).onPressed, isNotNull);
      final referenceUrl = Uri.parse(
        controller.knowledge.region('distal_radius').referenceUrls.first,
      );
      expect(referenceUrl.scheme, 'https');
      expect(referenceUrl.host, 'surgeryreference.aofoundation.org');

      await tab('Báo cáo');
      expect(find.text('Tạo & xem PDF'), findsOneWidget);
      final pdf = await tester.runAsync(() => makeReport(controller));
      expect(String.fromCharCodes(pdf!.take(5)), '%PDF-');
      expect(pdf.length, greaterThan(10000));

      // File I/O and authenticated encryption run on real asynchronous tasks.
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Lưu ca'));
        for (var i = 0; i < 300 && controller.dirty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.dirty, isFalse);
      final saved = await tester.runAsync(
        () => repository.load(controller.current!.id),
      );
      expect(saved!.confirmedCode, '2R3A');
      expect(saved.observations['joint'], 'no');
      expect(saved.images.single.pngBytes, prepared.pngBytes);
      expect(saved.images.single.annotatedBytes, image.annotatedBytes);
      expect(
        (saved.images.single.session['marks'] as List).single['tool'],
        'distance',
      );
      expect(saved.clinical['side'], 'left');
      expect(saved.findings, 'Quan sát kiểm thử tổng hợp do người dùng nhập.');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
