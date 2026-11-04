import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/services/tcm_interview_adapter.dart';

void main() {
  group('TcmInterviewAdapter', () {
    test('温病/寒热问题只暴露诊断引擎已有的规范 key', () {
      final adapter = TcmInterviewAdapter();
      expect(
        adapter.temperatureOptions.map((option) => option.key).toList(),
        DiagnosticRules.temperaturePatterns.map((option) => option.key).toList(),
      );
    });

    test('拒绝不存在的辨经 key', () {
      final adapter = TcmInterviewAdapter();
      expect(
        () => adapter.answerTemperature('invented_pattern'),
        throwsArgumentError,
      );
    });

    test('舌脉选项来自 canonical 引擎选项，组合脉保留主兼关系', () {
      final adapter = TcmInterviewAdapter();
      expect(adapter.tongueCoatingOptions, isNotEmpty);
      expect(adapter.tongueShapeOptions, isNotEmpty);
      expect(adapter.pulseOptions, isNotEmpty);

      adapter.answerTonguePulse(
        tongueCoating: '白厚',
        tongueShape: '淡白',
        primaryPulse: '弦',
        secondaryPulse: '滑',
      );
      final restored = TcmInterviewAdapter(snapshot: adapter.createSnapshot());
      expect(restored.createSnapshot().tongueCoating, '白厚');
      expect(restored.createSnapshot().tongueShape, '淡白');
      expect(restored.createSnapshot().pulseType, '弦');
      expect(restored.createSnapshot().pulseTypeSecondary, '滑');
    });

    test('十问答案必须与引擎规范选项完全一致', () {
      final adapter = TcmInterviewAdapter();
      final first = adapter.tenQuestionPrompts.first;
      expect(
        () => adapter.answerTenQuestion(first.id, '任意自然语言直接写入'),
        throwsArgumentError,
      );
      expect(
        () => adapter.answerTenQuestion(first.id, first.options.first),
        returnsNormally,
      );
    });

    test('历史快照恢复后继续使用原来的引擎状态', () {
      final original = TcmInterviewAdapter();
      final first = original.tenQuestionPrompts.first;
      original.answerTenQuestion(first.id, first.options.first);
      final restored = TcmInterviewAdapter(snapshot: original.createSnapshot());

      expect(restored.questionIndex, original.questionIndex);
      expect(restored.createSnapshot().answers, original.createSnapshot().answers);
    });

    test('脏腑证据通过独立只读接口暴露', () {
      final adapter = TcmInterviewAdapter();
      final evidence = adapter.buildZangFuEvidence();
      expect(evidence.organMappingStatus, 'MISSING');
      expect(evidence.hasAnsweredEvidence, isFalse);
    });
  });
}
