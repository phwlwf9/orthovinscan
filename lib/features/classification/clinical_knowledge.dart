import 'dart:convert';

import 'package:flutter/services.dart';

/// Reviewed-source metadata is distinct from clinical validation of this app.
/// Only coarse adult AO/OTA 2018 types are encoded in the initial rule set.
class ClinicalKnowledge {
  ClinicalKnowledge.fromJson(Map<String, dynamic> json)
    : version = json['version'] as String,
      edition = json['edition'] as String,
      reviewStatus = json['review_status'] as String,
      regions = (json['regions'] as List<dynamic>)
          .map((e) => RegionRule.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  final String version;
  final String edition;
  final String reviewStatus;
  final List<RegionRule> regions;

  static Future<ClinicalKnowledge> load() async {
    final text = await rootBundle.loadString(
      'assets/clinical_rules/ao_ota_2018.json',
    );
    return ClinicalKnowledge.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  RegionRule region(String id) => regions.firstWhere((r) => r.id == id);

  ClassificationResult evaluate(
    String regionId,
    Map<String, String> observations,
  ) {
    final matchingRegions = regions.where((r) => r.id == regionId);
    if (matchingRegions.isEmpty) {
      return ClassificationResult(
        candidates: const [],
        excluded: const [],
        missing: const ['Vùng giải phẫu chưa được hỗ trợ.'],
        missingEn: const ['Unsupported anatomical region.'],
        conflicts: const [],
        conflictsEn: const [],
        canConfirm: false,
      );
    }
    final selectedRegion = matchingRegions.single;
    final missing = <String>[];
    final missingEn = <String>[];
    final conflicts = <String>[];
    final conflictsEn = <String>[];

    // Reject invalid values rather than silently treating them as observations.
    for (final entry in observations.entries) {
      final qs = selectedRegion.questions.where((q) => q.id == entry.key);
      if (qs.isEmpty || !qs.single.options.any((o) => o.id == entry.value)) {
        conflicts.add('Giá trị quan sát không hợp lệ: ${entry.key}.');
        conflictsEn.add('Invalid observation value: ${entry.key}.');
      }
    }
    for (final q in selectedRegion.questions) {
      if (!q.isVisible(observations)) continue;
      final value = observations[q.id];
      if (q.required && (value == null || value == 'unknown')) {
        missing.add(q.labelVi);
        missingEn.add(q.labelEn);
      }
    }
    for (final conflict in selectedRegion.conflictRules) {
      if (conflict.matches(observations)) {
        conflicts.add(conflict.messageVi);
        conflictsEn.add(conflict.messageEn);
      }
    }
    if (observations['adult'] == 'no') {
      conflicts.add('Bộ quy tắc này chỉ áp dụng cho gãy xương người lớn.');
      conflictsEn.add('This rule set covers adult fractures only.');
    }
    if (observations['views'] == 'no') {
      missing.add('Cần hình ảnh đủ chất lượng và tư thế để đánh giá.');
      missingEn.add('Adequate views and image quality are required.');
    }

    final candidates = <CandidateRule>[];
    final excluded = <CandidateRule>[];
    for (final rule in selectedRegion.types) {
      final evidence = <String>[];
      final evidenceEn = <String>[];
      final contradictions = <String>[];
      final contradictionsEn = <String>[];
      for (final criterion in rule.criteria.entries) {
        final actual = observations[criterion.key];
        if (actual == null || actual == 'unknown') continue;
        final question = selectedRegion.questions.firstWhere(
          (q) => q.id == criterion.key,
        );
        final expectedOption = question.options.firstWhere(
          (o) => o.id == criterion.value,
        );
        if (actual == criterion.value) {
          evidence.add('${question.labelVi}: ${expectedOption.labelVi}');
          evidenceEn.add('${question.labelEn}: ${expectedOption.labelEn}');
        } else {
          contradictions.add(
            '${question.labelVi}: cần ${expectedOption.labelVi.toLowerCase()}',
          );
          contradictionsEn.add(
            '${question.labelEn}: requires ${expectedOption.labelEn.toLowerCase()}',
          );
        }
      }
      final candidate = CandidateRule(
        code: rule.code,
        labelVi: rule.labelVi,
        labelEn: rule.labelEn,
        evidence: evidence,
        evidenceEn: evidenceEn,
        contradictions: contradictions,
        contradictionsEn: contradictionsEn,
        referenceUrls: rule.referenceUrls,
      );
      if (contradictions.isEmpty) {
        candidates.add(candidate);
      } else {
        excluded.add(candidate);
      }
    }
    return ClassificationResult(
      candidates: candidates,
      excluded: excluded,
      missing: missing,
      missingEn: missingEn,
      conflicts: conflicts,
      conflictsEn: conflictsEn,
      canConfirm:
          candidates.length == 1 && missing.isEmpty && conflicts.isEmpty,
    );
  }
}

class ClassificationResult {
  const ClassificationResult({
    required this.candidates,
    required this.excluded,
    required this.missing,
    required this.missingEn,
    required this.conflicts,
    required this.conflictsEn,
    required this.canConfirm,
  });
  final List<CandidateRule> candidates;
  final List<CandidateRule> excluded;
  final List<String> missing;
  final List<String> missingEn;
  final List<String> conflicts;
  final List<String> conflictsEn;
  final bool canConfirm;
}

class CandidateRule {
  const CandidateRule({
    required this.code,
    required this.labelVi,
    required this.labelEn,
    required this.evidence,
    required this.evidenceEn,
    required this.contradictions,
    required this.contradictionsEn,
    required this.referenceUrls,
  });
  final String code;
  final String labelVi;
  final String labelEn;
  final List<String> evidence;
  final List<String> evidenceEn;
  final List<String> contradictions;
  final List<String> contradictionsEn;
  final List<String> referenceUrls;
}

class RegionRule {
  RegionRule.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      nameVi = json['name_vi'] as String,
      nameEn = json['name_en'] as String,
      summaryVi = json['summary_vi'] as String,
      summaryEn = json['summary_en'] as String,
      referenceUrls = List<String>.from(json['reference_urls'] as List),
      questions = (json['questions'] as List)
          .map((e) => QuestionRule.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      types = (json['types'] as List)
          .map((e) => TypeRule.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      conflictRules = (json['conflicts'] as List)
          .map((e) => ConflictRule.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      treatmentSections = (json['treatment_sections'] as List)
          .map((e) => TreatmentSection.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
  final String id;
  final String nameVi;
  final String nameEn;
  final String summaryVi;
  final String summaryEn;
  final List<String> referenceUrls;
  final List<QuestionRule> questions;
  final List<TypeRule> types;
  final List<ConflictRule> conflictRules;
  final List<TreatmentSection> treatmentSections;
}

class QuestionRule {
  QuestionRule.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      labelVi = json['label_vi'] as String,
      labelEn = json['label_en'] as String,
      required = json['required'] as bool,
      appliesWhen = Map<String, String>.from(
        json['applies_when'] as Map? ?? const {},
      ),
      options = (json['options'] as List)
          .map((e) => OptionRule.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
  final String id;
  final String labelVi;
  final String labelEn;
  final bool required;
  final Map<String, String> appliesWhen;
  final List<OptionRule> options;
  bool isVisible(Map<String, String> observations) =>
      appliesWhen.entries.every((e) => observations[e.key] == e.value);
}

class OptionRule {
  OptionRule.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      labelVi = json['label_vi'] as String,
      labelEn = json['label_en'] as String;
  final String id;
  final String labelVi;
  final String labelEn;
}

class TypeRule {
  TypeRule.fromJson(Map<String, dynamic> json)
    : code = json['code'] as String,
      labelVi = json['label_vi'] as String,
      labelEn = json['label_en'] as String,
      criteria = Map<String, String>.from(json['criteria'] as Map),
      referenceUrls = List<String>.from(json['reference_urls'] as List);
  final String code;
  final String labelVi;
  final String labelEn;
  final Map<String, String> criteria;
  final List<String> referenceUrls;
}

class ConflictRule {
  ConflictRule.fromJson(Map<String, dynamic> json)
    : conditions = Map<String, String>.from(json['conditions'] as Map),
      messageVi = json['message_vi'] as String,
      messageEn = json['message_en'] as String;
  final Map<String, String> conditions;
  final String messageVi;
  final String messageEn;
  bool matches(Map<String, String> values) =>
      conditions.entries.every((e) => values[e.key] == e.value);
}

class TreatmentSection {
  TreatmentSection.fromJson(Map<String, dynamic> json)
    : titleVi = json['title_vi'] as String,
      titleEn = json['title_en'] as String,
      bodyVi = json['body_vi'] as String,
      bodyEn = json['body_en'] as String,
      sourceUrls = List<String>.from(json['source_urls'] as List);
  final String titleVi;
  final String titleEn;
  final String bodyVi;
  final String bodyEn;
  final List<String> sourceUrls;
}
