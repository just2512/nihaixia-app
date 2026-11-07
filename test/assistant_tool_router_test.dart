import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/ziwuliuzhu_screen.dart';

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

  test('旧结构化辨证页面入口必须 fail closed，问诊只能在统一对话内继续', () {
    final tool = AssistantToolRouter.byId('structured_diagnosis');
    expect(tool, isNotNull);
    expect(() => tool!.builder(), throwsA(isA<StateError>()));
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

  test('玄学角色名称和子午流注工具回传配置一致', () {
    expect(AssistantMode.metaphysics.label, '玄学大师');
    final tool = AssistantToolRouter.match(
      '帮我做子午流注开穴',
      AssistantMode.tools,
    );
    expect(tool?.id, 'ziwu_liuzhu');
    final screen = tool!.builder();
    expect(screen, isA<ZiWuLiuZhuScreen>());
    expect((screen as ZiWuLiuZhuScreen).returnResultOnComplete, isTrue);
  });

  test('学习模式不会因为提到工具名称而自动跳转', () {
    expect(
      AssistantToolRouter.match('介绍一下五运六气', AssistantMode.learning),
      isNull,
    );
  });

  test('自动调度遇到多个明确工具动作时必须返回歧义而不是抢先执行', () {
    const request = '先帮我排紫微斗数，再推算五运六气';
    final matches = AssistantToolRouter.matchAll(
      request,
      AssistantMode.automatic,
    );
    expect(matches.map((tool) => tool.id), containsAll(['ziwei', 'yunqi']));
    expect(AssistantToolRouter.match(request, AssistantMode.automatic), isNull);
  });

  test('自动调度可识别单一工具动作，学习提问不因工具名误触发', () {
    expect(
      AssistantToolRouter.match('请帮我排一个紫微斗数命盘', AssistantMode.automatic)?.id,
      'ziwei',
    );
    expect(
      AssistantToolRouter.match('请解释紫微斗数的历史来源', AssistantMode.automatic),
      isNull,
    );
  });

  test('工具澄清短答必须由调用方验证唯一候选', () {
    final candidates = AssistantToolRouter.matchAliases(
      '紫微斗数和八字',
      AssistantMode.metaphysics,
    );
    expect(candidates.map((tool) => tool.id), containsAll(['ziwei', 'bazi']));
    expect(candidates.length, 2);
  });
  test('工具参数契约拒绝非法日期、未声明字段和错误工具标识', () {
    final tool = AssistantToolRouter.yunqi;
    expect(
      const AssistantToolArguments(
        toolId: 'yunqi',
        values: {'date': '2026-02-30'},
      ).validateAgainst(tool),
      isNotEmpty,
    );
    expect(
      const AssistantToolArguments(
        toolId: 'yunqi',
        values: {'date': '2026-11-06', 'rawPrompt': 'run arbitrary'},
      ).validateAgainst(tool),
      isNotEmpty,
    );
    expect(
      const AssistantToolArguments(toolId: 'bazi').validateAgainst(tool),
      isNotEmpty,
    );
    expect(
      const AssistantToolArguments(
        toolId: 'yunqi',
        values: {'date': '2026-11-06'},
      ).validateAgainst(tool),
      isEmpty,
    );
  });


  test('必填参数在没有传参时也会被拒绝', () {
    final tool = AssistantToolDefinition(
      id: 'test_required',
      title: '测试工具',
      description: '测试必填参数。',
      modes: const {AssistantMode.tools},
      aliases: const ['测试工具'],
      actionWords: const ['执行'],
      builder: () => const SizedBox.shrink(),
      parameters: const [
        AssistantToolParameter(
          key: 'count',
          label: '数量',
          type: AssistantToolParameterType.integer,
          isRequired: true,
        ),
      ],
    );
    expect(
      const AssistantToolArguments(toolId: 'test_required')
          .validateAgainst(tool),
      contains('缺少必填参数：数量'),
    );
    expect(
      const AssistantToolArguments(
        toolId: 'test_required',
        values: {'count': '3'},
      ).validateAgainst(tool),
      isEmpty,
    );
  });

}
