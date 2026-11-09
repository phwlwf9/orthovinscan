import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/classification/clinical_knowledge.dart';
import 'case_repository.dart';
import 'models.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.knowledge,
    required this.prefs,
  });
  final CaseRepository repository;
  final ClinicalKnowledge knowledge;
  final SharedPreferences prefs;
  List<CaseRecord> cases = [];
  CaseRecord? current;
  bool dirty = false;
  int _revision = 0;
  Future<void>? _saving;
  bool get saving => _saving != null;
  bool get english => prefs.getString('language') == 'en';
  bool get consented => prefs.getBool('consent.v1') ?? false;
  ThemeMode get themeMode => switch (prefs.getString('theme')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  String tr(String vi, String en) => english ? en : vi;
  Future<void> initialize() async {
    cases = await repository.list();
    notifyListeners();
  }

  Future<void> consent() async {
    await prefs.setBool('consent.v1', true);
    notifyListeners();
  }

  Future<void> language(bool en) async {
    await prefs.setString('language', en ? 'en' : 'vi');
    notifyListeners();
  }

  Future<void> theme(String value) async {
    await prefs.setString('theme', value);
    notifyListeners();
  }

  CaseRecord newCase() {
    _revision++;
    final now = DateTime.now();
    current = CaseRecord(
      id: 'OA-${now.microsecondsSinceEpoch.toRadixString(36).toUpperCase()}',
      createdAt: now,
    );
    dirty = true;
    notifyListeners();
    return current!;
  }

  Future<bool> edit(CaseRecord record) async {
    final attempt = ++_revision;
    final loaded = record.summaryImageCount != null
        ? await repository.load(record.id)
        : CaseRecord.fromJson(record.toJson());
    if (attempt != _revision) return false;
    current = loaded;
    dirty = false;
    notifyListeners();
    return true;
  }

  void changed({bool invalidate = false}) {
    _revision++;
    if (invalidate) current?.invalidateConfirmation();
    current?.updatedAt = DateTime.now();
    dirty = true;
    notifyListeners();
  }

  Future<void> save() {
    final pending = _saving;
    if (pending != null) return pending;
    final operation = _saveCurrent();
    _saving = operation;
    notifyListeners();
    return operation.whenComplete(() {
      _saving = null;
      notifyListeners();
    });
  }

  Future<void> _saveCurrent() async {
    final record = current;
    if (record == null) return;
    record.updatedAt = DateTime.now();
    final savedRevision = _revision;
    final snapshot = CaseRecord.fromJson(record.toJson());
    await repository.save(snapshot);
    cases = await repository.list();
    if (current?.id == snapshot.id && _revision == savedRevision) dirty = false;
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final pending = _saving;
    if (pending != null) await pending;
    await repository.delete(id);
    cases = await repository.list();
    if (current?.id == id) {
      current = null;
      dirty = false;
    }
    notifyListeners();
  }
}
