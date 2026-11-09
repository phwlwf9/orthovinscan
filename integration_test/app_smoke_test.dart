import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:orthoai/core/app_controller.dart';
import 'package:orthoai/core/models.dart';
import 'package:orthoai/features/case_workspace.dart';
import 'package:orthoai/main.dart' as app;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Run on a dedicated test device/emulator:
/// `flutter test integration_test/app_smoke_test.dart -d <device-id>`
/// Uses real native app bootstrap and encrypted storage. Image acquisition is
/// seeded with a synthetic PNG; camera and file-picker require separate checks.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native consent, navigation, classification and secure save', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('consent.v1');
    await prefs.setString('language', 'vi');
    await app.main();
    await tester.pumpAndSettle();

    final checkbox = find.byType(CheckboxListTile);
    await tester.scrollUntilVisible(checkbox, 180);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bắt đầu'));
    await tester.tap(find.text('Bắt đầu'));
    await tester.pumpAndSettle();
    expect(find.text('Ca mới'), findsOneWidget);

    await tester.tap(find.text('Tài liệu'));
    await tester.pumpAndSettle();
    expect(find.text('Tài liệu chuyên môn'), findsOneWidget);
    expect(find.text('AO Surgery Reference'), findsOneWidget);
    await tester.tap(find.text('Tổng quan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ca mới'));
    await tester.pumpAndSettle();
    expect(find.byType(CaseWorkspace), findsOneWidget);
    final controller = tester
        .element(find.byType(CaseWorkspace))
        .read<AppController>();
    final caseId = controller.current!.id;
    addTearDown(() async {
      await controller.delete(caseId);
    });

    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 16, height: 16)),
    );
    controller.current!.images.add(
      CaseImage(
        id: 'integration-synthetic-fixture',
        originalBytes: png,
        pngBytes: png,
        sourceFormat: 'PNG',
      ),
    );
    controller.changed(invalidate: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phân loại'));
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
          of: find.byType(ClassificationPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> choose(Key key, String label) async {
      final field = find.byKey(key);
      await tester.scrollUntilVisible(field, 180, scrollable: scroll);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose(const ValueKey<String?>(null), 'Đầu dưới xương quay');
    await choose(const ValueKey('distal_radius.adult.null'), 'Có');
    await choose(const ValueKey('distal_radius.views.null'), 'Có');
    await choose(const ValueKey('distal_radius.joint.null'), 'Không');
    expect(controller.current!.confirmedCode, isNull);
    final confirm = find.text('Bác sĩ xác nhận phân loại');
    await tester.scrollUntilVisible(confirm, 200, scrollable: scroll);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Xác nhận của bác sĩ'), findsOneWidget);
    expect(controller.current!.confirmedCode, isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận'));
    await tester.pumpAndSettle();
    expect(controller.current!.confirmedCode, '2R3A');

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Lưu ca'));
      for (var i = 0; i < 100 && controller.dirty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
    expect(controller.dirty, isFalse);
    final saved = await tester.runAsync(
      () => controller.repository.load(caseId),
    );
    expect(saved!.confirmedCode, '2R3A');
    expect(saved.images.single.pngBytes, png);
    expect(tester.takeException(), isNull);
  });
}
