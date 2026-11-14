import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/data/sanshan_lingqian_data.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/sanshan_lingqian_tool_executor.dart';

void main() {
  test('抽签由 App 随机索引本地 92 签，并返回同一条签文与来源', () {
    const seed = 73;
    final expectedIndex = Random(seed).nextInt(kSanShanLingqian.length);
    final sign = SanshanLingqianToolExecutor.draw(random: Random(seed));
    final result = SanshanLingqianToolExecutor.resultForSign(sign);

    expect(sign.id, kSanShanLingqian[expectedIndex].id);
    expect(sign.id, inInclusiveRange(1, 92));
    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'sanshan_lingqian');
    expect(result.values['签号'], sign.id.toString());
    expect(result.values['签题'], sign.title);
    expect(result.values['签诗'], sign.verse);
    expect(result.values['签级'], sign.luck.label);
    expect(result.values['签谱范围'], '本地三山国王祖庙传承 92 签签谱');
    expect(result.sourceIds, ['${SanshanLingqianToolExecutor.dataSourcePrefix}${sign.id}']);
    expect(result.validateFor('sanshan_lingqian'), isEmpty);
    expect(result.validateArgumentsMatch(const {}), isEmpty);
    expect(result.disclaimer, contains('不是现实吉凶保证'));
  });

  test('Headless 执行仅接受空参数，模型不能指定或伪造签号', () async {
    final invalid = await SanshanLingqianToolExecutor.execute(const {'sign_id': '1'});
    expect(invalid.status, AssistantToolExecutionStatus.failed);
    expect(invalid.sourceIds, isEmpty);
    expect(invalid.values['未执行原因'], contains('不能接受模型指定签号'));

    final result = await SanshanLingqianToolExecutor.execute(const {});
    final id = int.parse(result.values['签号']!);
    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.sourceIds, ['${SanshanLingqianToolExecutor.dataSourcePrefix}$id']);
    expect(kSanShanLingqian.any((sign) => sign.id == id), isTrue);
    expect(
      result.values['签诗'],
      kSanShanLingqian.firstWhere((sign) => sign.id == id).verse,
    );
  });
}
