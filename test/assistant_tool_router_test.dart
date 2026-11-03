import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';

void main() {
  test('问诊模式只把明确结构化辨证请求交给规则问诊', () {
    expect(
      AssistantToolRouter.match('请开始结构化辨证问诊', AssistantMode.consultation)?.id,
      'structured_diagnosis',
    );
    expect(
      AssistantToolRouter.match('我想了解六经辨证的概念', AssistantMode.consultation),
      isNull,
    );
  });

  test('工具模式按明确动作路由五运六气和剂量换算', () {
    expect(
      AssistantToolRouter.match('帮我推算五运六气', AssistantMode.tools)?.id,
      'yunqi',
    );
    expect(
      AssistantToolRouter.match('帮我做经方剂量换算', AssistantMode.tools)?.id,
      'dosage',
    );
  });

  test('玄学模式只路由明确排盘或起卦动作', () {
    expect(
      AssistantToolRouter.match('帮我排一个紫微斗数命盘', AssistantMode.metaphysics)?.id,
      'ziwei',
    );
    expect(
      AssistantToolRouter.match('帮我排八字', AssistantMode.metaphysics)?.id,
      'bazi',
    );
    expect(
      AssistantToolRouter.match('易经六十四卦是什么', AssistantMode.metaphysics),
      isNull,
    );
    expect(
      AssistantToolRouter.match('帮我用易经起卦', AssistantMode.metaphysics)?.id,
      'yijing',
    );
  });

  test('学习模式不会因为提到工具名称而自动跳转', () {
    expect(
      AssistantToolRouter.match('介绍一下五运六气', AssistantMode.learning),
      isNull,
    );
  });
}
