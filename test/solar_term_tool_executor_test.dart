import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/assistant_tool_result.dart';
import 'package:nihaisha_app/services/solar_term_service.dart';
import 'package:nihaisha_app/services/solar_term_tool_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('指定节气查询复用现有知识资产并保留原始字段和来源', () async {
    final result = await SolarTermToolExecutor.execute({'term': '立春'});

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.toolId, 'solar_terms');
    expect(result.validateFor('solar_terms'), isEmpty);
    expect(result.validateArgumentsMatch({'term': '立春'}), isEmpty);
    expect(result.sourceIds, const [
      SolarTermToolExecutor.sourceId,
      SolarTermToolExecutor.knowledgeSourceId,
    ]);
    expect(result.values['查询类型'], '指定节气知识');
    expect(result.values['目标节气'], '立春');
    expect(result.values['公历约期'], getTermApproxDate('立春'));
    expect(result.values['太阳黄经'], '315°');
    expect(result.values['通用养生常识'], isNotEmpty);
    expect(result.values['倪师讲座相关整理'], contains('【推断】'));
    expect(result.values['节气三候'], isNotEmpty);
    expect(result.values['起居调摄'], contains('【推断】'));
    expect(result.values['食疗资料'], isNotEmpty);
    expect(result.disclaimer, contains('不构成个体诊断、治疗或用药建议'));
  });

  test('不指定节气时返回 App 当前节气服务的真实节点和倒计时', () async {
    final expected = getCurrentSolarTerm();
    final result = await SolarTermToolExecutor.execute(const {});

    expect(result.status, AssistantToolExecutionStatus.succeeded);
    expect(result.validateFor('solar_terms'), isEmpty);
    expect(result.validateArgumentsMatch(const {}), isEmpty);
    expect(result.values['查询类型'], '当前节气');
    expect(result.values['当前节气'], expected.currentTerm);
    expect(result.values['下一节气'], expected.nextTerm);
    expect(result.values['进入当前节气天数'], expected.daysInto.toString());
    expect(result.values['距下一节气天数'], expected.daysLeft.toString());
    expect(result.values['当前节气养生提示'], expected.healthTip);
    expect(result.sourceIds, contains(SolarTermToolExecutor.knowledgeSourceId));
  });

  test('拒绝未知节气名称，不把未知名称当作当前节气', () async {
    final result = await SolarTermToolExecutor.execute({'term': '不存在的节气'});

    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.values['未执行原因'], contains('无法识别节气'));
    expect(result.sourceIds, isEmpty);
  });

  test('拒绝未声明参数，不将用户自由文本当作执行参数', () async {
    final result = await SolarTermToolExecutor.execute({
      'term': '立春',
      'rawPrompt': '请自行推断用户的体质并给出处方',
    });

    expect(result.status, AssistantToolExecutionStatus.failed);
    expect(result.values['未执行原因'], contains('未声明'));
    expect(result.sourceIds, isEmpty);
  });
}
