import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Plaintext export copies are kept in app cache after explicit consent.
/// Remove leftovers on the next cold start; recipients control their copies.
class ExportCache {
  static Future<void> clear() async {
    final temp = await getTemporaryDirectory();
    for (final name in ['orthoai_exports', 'share_plus']) {
      final directory = Directory('${temp.path}/$name');
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  static Future<File> prepare(Uint8List bytes, String name) async {
    final temp = await getTemporaryDirectory();
    final directory = Directory(
      '${temp.path}/orthoai_exports/${DateTime.now().microsecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    return File('${directory.path}/$safeName').writeAsBytes(bytes, flush: true);
  }
}
