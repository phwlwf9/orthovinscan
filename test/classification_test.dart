import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthoai/features/classification/clinical_knowledge.dart';

void main() {
  late ClinicalKnowledge knowledge;
  const adequate = {'adult': 'yes', 'views': 'yes'};

  setUpAll(() {
    knowledge = ClinicalKnowledge.fromJson(
      jsonDecode(
            File('assets/clinical_rules/ao_ota_2018.json').readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
  });

  test('documents the fixed edition, scope and review status', () {
    expect(knowledge.edition, '2018');
    expect(knowledge.reviewStatus, 'pending_clinician_review');
    expect(knowledge.regions.map((r) => r.id), [
      'distal_radius',
      'proximal_femur',
      'proximal_tibia',
    ]);
    for (final region in knowledge.regions) {
      expect(region.types, hasLength(3));
      expect(
        region.referenceUrls.every((u) => u.startsWith('https://')),
        isTrue,
      );
      expect(region.treatmentSections, isNotEmpty);
    }
  });

  test('unknown observations preserve candidates without confirmation', () {
    final result = knowledge.evaluate('distal_radius', {});
    expect(result.candidates.map((c) => c.code), ['2R3A', '2R3B', '2R3C']);
    expect(result.missing, isNotEmpty);
    expect(result.canConfirm, isFalse);
  });

  test(
    'distal radius narrows extraarticular type, with exclusions explained',
    () {
      final result = knowledge.evaluate('distal_radius', {
        ...adequate,
        'joint': 'no',
      });
      expect(result.candidates.single.code, '2R3A');
      expect(result.candidates.single.evidence, isNotEmpty);
      expect(result.excluded.map((c) => c.code), ['2R3B', '2R3C']);
      expect(result.excluded.every((c) => c.contradictions.isNotEmpty), isTrue);
      expect(result.canConfirm, isTrue);
    },
  );

  test('articular injury without continuity information is insufficient', () {
    final result = knowledge.evaluate('distal_radius', {
      ...adequate,
      'joint': 'yes',
    });
    expect(result.candidates.map((c) => c.code), ['2R3B', '2R3C']);
    expect(result.missing, hasLength(1));
    expect(result.canConfirm, isFalse);
  });

  test('known and unknown are never treated as equivalent', () {
    final unknown = knowledge.evaluate('proximal_tibia', {
      ...adequate,
      'joint': 'yes',
      'continuity': 'unknown',
    });
    final partial = knowledge.evaluate('proximal_tibia', {
      ...adequate,
      'joint': 'yes',
      'continuity': 'connected',
    });
    final complete = knowledge.evaluate('proximal_tibia', {
      ...adequate,
      'joint': 'yes',
      'continuity': 'detached',
    });
    expect(unknown.canConfirm, isFalse);
    expect(partial.candidates.single.code, '41B');
    expect(complete.candidates.single.code, '41C');
    expect(partial.canConfirm, isTrue);
    expect(complete.canConfirm, isTrue);
  });

  test(
    'contradictory observations prevent confirmation even with one match',
    () {
      final result = knowledge.evaluate('distal_radius', {
        ...adequate,
        'joint': 'no',
        'continuity': 'detached',
      });
      expect(result.conflicts, isNotEmpty);
      expect(result.canConfirm, isFalse);
    },
  );

  test('inadequate views and paediatric cases cannot be confirmed', () {
    for (final observations in [
      {...adequate, 'joint': 'no', 'views': 'no'},
      {...adequate, 'joint': 'no', 'adult': 'no'},
      {...adequate, 'joint': 'no', 'adult': 'unknown'},
    ]) {
      expect(
        knowledge.evaluate('distal_radius', observations).canConfirm,
        isFalse,
      );
    }
  });

  test(
    'proximal femur uses anatomical site, not the generic articular rule',
    () {
      for (final entry in {
        'trochanter': '31A',
        'neck': '31B',
        'head': '31C',
      }.entries) {
        final result = knowledge.evaluate('proximal_femur', {
          ...adequate,
          'site': entry.key,
          'combined': 'no',
        });
        expect(result.candidates.single.code, entry.value);
        expect(result.canConfirm, isTrue);
      }
    },
  );

  test(
    'combined femoral injuries are escalated beyond the one-site engine',
    () {
      final result = knowledge.evaluate('proximal_femur', {
        ...adequate,
        'site': 'head',
        'combined': 'yes',
      });
      expect(result.conflicts, isNotEmpty);
      expect(result.canConfirm, isFalse);
    },
  );

  test('invalid answer IDs and unsupported regions fail closed', () {
    final invalid = knowledge.evaluate('distal_radius', {
      ...adequate,
      'joint': 'no',
      'unrecognized': 'yes',
    });
    expect(invalid.conflicts, isNotEmpty);
    expect(invalid.canConfirm, isFalse);
    expect(knowledge.evaluate('unimplemented_region', {}).canConfirm, isFalse);
  });

  test(
    'deterministic results do not depend on observation insertion order',
    () {
      final a = knowledge.evaluate('distal_radius', {
        ...adequate,
        'joint': 'yes',
        'continuity': 'detached',
        'morphology': 'multifragmentary',
      });
      final b = knowledge.evaluate('distal_radius', {
        'morphology': 'multifragmentary',
        'continuity': 'detached',
        'joint': 'yes',
        'views': 'yes',
        'adult': 'yes',
      });
      expect(a.candidates.single.code, b.candidates.single.code);
      expect(a.missing, b.missing);
      expect(a.conflicts, b.conflicts);
      expect(a.canConfirm, b.canConfirm);
    },
  );
}
