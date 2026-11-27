import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';

void main() {
  group('经典条文来源 manifest 完整性', () {
    late Map<String, dynamic> manifest;
    late List<Map<String, dynamic>> records;

    setUpAll(() {
      final file = File('docs/classic-rule-source-manifest.json');
      expect(file.existsSync(), isTrue, reason: '来源 manifest 必须随仓库版本管理');
      manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      records = (manifest['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
    });

    test('活跃规则来源记录数量、条件键唯一且编号口径一致', () {
      expect(records, hasLength(12));
      final keys = records.map((record) => record['conditionKey']).toList();
      expect(keys.toSet(), hasLength(keys.length));
      for (final record in records) {
        expect(record['conditionKey'], isA<String>());
        expect(record['conditionKey'], isNotEmpty);
        expect(record['numberingScheme'], manifest['numberingScheme']);
        expect(record['classification'], isA<String>());
        expect(record['applicability'], isA<String>());
        expect(record['status'], isA<String>());
      }
    });

    test('manifest 条件键必须与当前规则表 canonical IDs 一一对应', () {
      final manifestKeys = records
          .map((record) => record['conditionKey'] as String)
          .toSet();
      final activeRuleKeys = DiagnosticRules.combinedPatterns
          .map((rule) => rule.condition)
          .toSet();

      expect(
        manifestKeys.every((key) => key.startsWith('combined.')),
        isTrue,
      );
      expect(manifestKeys, activeRuleKeys);
    });

    test('在线转录核对不得冒充纸本版本、页码或影像核验', () {
      for (final record in records) {
        expect(record['localAssetPath'], 'MISSING');
        expect(record['baseEdition'], 'MISSING');
        expect(record['volume'], 'MISSING');
        expect(record['page'], 'MISSING');
        expect(record['primaryImageVerification'], 'MISSING');
      }
      expect(
        manifest['candidatePrintEdition']['status'],
        'CANDIDATE_WORKING_BASE_EDITION_NOT_PAGE_VERIFIED',
      );
      expect(
        manifest['globalMissingFields'],
        containsAll(['baseEditionExactCopy', 'volume', 'page', 'imageLocator']),
      );
    });

    test('来源缺失规则不得伪造条号、链接或方剂', () {
      final missing = records.where((record) => record['status'] == 'MISSING');
      expect(missing, isNotEmpty);
      for (final record in missing) {
        expect(record['articleNumber'], isNull);
        expect(record['url'], isNull);
        expect(record['formula'], isNull);
        expect(record['sourceVerificationStatus'], 'MISSING');
      }
    });

    test('第268条明确保留原文无方剂边界', () {
      final record = records.singleWhere(
        (item) => item['conditionKey'] == CombinedPatternCondition.threeYangSleep,
      );
      expect(record['articleNumber'], 268);
      expect(record['classification'], 'EXPLICIT_COMBINED_NO_FORMULA_IN_CLAUSE');
      expect(record['formula'], isNull);
      expect(record['formulaInOriginalText'], isFalse);
      expect(record['applicability'], contains('上关上'));
    });
  });
}
