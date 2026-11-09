import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// App-private, authenticated encrypted storage. The encryption key is kept in
/// platform secure storage; it is never bundled with or exported in case files.
class CaseRepository {
  CaseRepository._(this.directory, this._key);
  final Directory directory;
  final SecretKey _key;
  final AesGcm _cipher = AesGcm.with256bits();

  /// Files that could not be authenticated/read in the latest history refresh.
  /// They remain on disk; one damaged case does not lock every other case.
  final List<String> unreadableIds = [];
  static const _keyName = 'orthoai.case-key.v1';
  static final _validId = RegExp(r'^[A-Za-z0-9_-]{1,96}$');

  static Future<CaseRepository> open() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/encrypted_cases_v1');
    await directory.create(recursive: true);
    const secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
    var encoded = await secure.read(key: _keyName);
    if (encoded == null) {
      final existing = await directory.list().any(
        (entry) => entry is File && entry.path.endsWith('.ortho'),
      );
      if (existing) {
        throw const CaseStorageException(
          'The storage key is unavailable. Existing cases were preserved.',
        );
      }
      final random = Random.secure();
      encoded = base64Encode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      await secure.write(key: _keyName, value: encoded);
    }
    try {
      final bytes = base64Decode(encoded);
      if (bytes.length != 32) throw const FormatException();
      return CaseRepository._(directory, SecretKey(bytes));
    } on FormatException {
      throw const CaseStorageException(
        'The storage key is invalid. Existing cases were preserved.',
      );
    }
  }

  /// Deterministic key injection is solely for tests, never production storage.
  static Future<CaseRepository> forTesting(
    Directory directory,
    List<int> key,
  ) async {
    if (key.length != 32) throw ArgumentError('AES-256 requires a 32-byte key');
    await directory.create(recursive: true);
    return CaseRepository._(directory, SecretKey(List<int>.from(key)));
  }

  File _file(String id) {
    if (!_validId.hasMatch(id)) {
      throw const CaseStorageException('Invalid anonymized case identifier.');
    }
    return File('${directory.path}/$id.ortho');
  }

  Future<List<CaseRecord>> list() async {
    unreadableIds.clear();
    final files = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.ortho'))
        .toList();
    final cases = <CaseRecord>[];
    for (final file in files) {
      final basename = file.uri.pathSegments.last;
      final id = basename.substring(0, basename.length - 6);
      try {
        // Decode one case at a time; do not retain every image in history.
        cases.add((await load(id)).summary());
      } on CaseStorageException {
        unreadableIds.add(id);
      }
    }
    cases.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return cases;
  }

  Future<CaseRecord> load(String id) async {
    final file = _file(id);
    try {
      final envelope =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (envelope['version'] != 1) throw const FormatException();
      final box = SecretBox(
        base64Decode(envelope['ciphertext'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        mac: Mac(base64Decode(envelope['mac'] as String)),
      );
      final plaintext = await _cipher.decrypt(
        box,
        secretKey: _key,
        aad: utf8.encode('OrthoAI/case/v1/$id'),
      );
      final decoded =
          jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
      final record = CaseRecord.fromJson(decoded);
      if (record.id != id) throw const FormatException();
      return record;
    } catch (_) {
      throw const CaseStorageException(
        'Cannot decrypt or read this case. The file was preserved.',
      );
    }
  }

  Future<void> save(CaseRecord record) async {
    if (record.summaryImageCount != null) {
      throw const CaseStorageException(
        'Load the complete case before editing or saving a history summary.',
      );
    }
    final destination = _file(record.id);
    // Never silently overwrite a file that this installation cannot decrypt.
    if (await destination.exists()) await load(record.id);
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(record.toJson())),
      secretKey: _key,
      aad: utf8.encode('OrthoAI/case/v1/${record.id}'),
    );
    final encoded = jsonEncode({
      'version': 1,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
    final suffix = Random.secure().nextInt(0x7fffffff);
    final temporary = File('${destination.path}.$suffix.tmp');
    try {
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> delete(String id) async {
    final file = _file(id);
    if (await file.exists()) await file.delete();
  }
}

class CaseStorageException implements Exception {
  const CaseStorageException(this.message);
  final String message;
  @override
  String toString() => message;
}
