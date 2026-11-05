import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_engine.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/models/diagnosis.dart';

void main() {
  group('合病条件键 canonicalization', () {
    test('所有历史条件键都映射到唯一 canonical ID', () {
      for (final entry in CombinedPatternCondition.legacyAliases.entries) {
        expect(
          CombinedPatternCondition.canonicalize(entry.key),
          entry.value,
          reason: 'legacy key ${entry.key}',
        );
      }
    });

    test('canonical ID 保持不变，未知 ID 不被猜测转换', () {
      for (final canonical in CombinedPatternCondition.legacyAliases.values.toSet()) {
        expect(CombinedPatternCondition.canonicalize(canonical), canonical);
      }
      expect(
        CombinedPatternCondition.canonicalize('combined.future.unknown'),
        'combined.future.unknown',
      );
      expect(CombinedPatternCondition.canonicalize(null), isNull);
    });

    test('恢复旧版快照时立即归一化历史条件键', () {
      final engine = DiagnosticEngine()
        ..restoreSnapshot(EngineSnapshot(
          stage: DiagnosticStage.meridianLocation,
          selectedSymptoms: const [],
          meridianDirection: '太阳',
          combinedPatternCondition: 'sun+yangming_vomit',
          answers: const {},
          tenQuestionIndex: 0,
        ));

      expect(
        engine.createSnapshot().combinedPatternCondition,
        CombinedPatternCondition.sunYangmingVomit,
      );
    });
  });
}
