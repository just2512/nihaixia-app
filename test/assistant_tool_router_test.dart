import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/ziwuliuzhu_screen.dart';
import 'package:nihaisha_app/models/assistant_message_metadata.dart';

void main() {
  test('工具注册表 ID 唯一且每个 ID 都能精确恢复同一工具定义', () {
    final tools = AssistantToolRouter.all;
    final ids = tools.map((tool) => tool.id).toList(growable: false);
    expect(ids, isNotEmpty);
    expect(ids.toSet(), hasLength(ids.length));
    for (final tool in tools) {
      expect(AssistantToolRouter.byId(tool.id), same(tool));
      expect(tool.id.trim(), isNotEmpty);
      expect(tool.title.trim(), isNotEmpty);
      expect(tool.aliases, isNotEmpty);
      expect(tool.actionWords, isNotEmpty);
    }
  });

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


  test('五运六气注册项同时保留页面入口并提供 Headless 执行器', () async {
    final tool = AssistantToolRouter.yunqi;
    expect(tool.builderWithArguments, isNotNull);
    expect(tool.headlessExecutor, isNotNull);

    const arguments = {'date': '2026-11-12'};
    final result = await tool.headlessExecutor!(arguments);
    expect(result.toolId, 'yunqi');
    expect(result.validateFor('yunqi'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.sourceIds, ['local-engine:yunqi']);
    expect(AssistantToolRouter.ziwei.headlessExecutor, isNull);
  });

  test('每日黄历注册项提供受日期约束的 Headless 执行器', () async {
    final tool = AssistantToolRouter.almanac;
    expect(tool.headlessExecutor, isNotNull);
    expect(tool.parameters.single.key, 'date');
    expect(tool.parameters.single.isRequired, isTrue);

    const arguments = {'date': '2026-11-12'};
    final result = tool.headlessExecutor!(arguments);
    expect(result.toolId, 'almanac');
    expect(result.validateFor('almanac'), isEmpty);
    expect(result.validateArgumentsMatch(arguments), isEmpty);
    expect(result.values['公历'], '2026-11-12');
    expect(result.sourceIds, ['local-engine:almanac']);
    expect(AssistantToolRouter.ziwei.headlessExecutor, isNull);
  });

  test('八字注册项要求四项出生参数并提供 Headless 执行器', () {
    final tool = AssistantToolRouter.bazi;
    expect(tool.headlessExecutor, isNotNull);
    expect(tool.parameters.map((parameter) => parameter.key), [
      'birth_date',
      'birth_time',
      'gender',
      'birthplace',
    ]);
    const valid = AssistantToolArguments(
      toolId: 'bazi',
      values: {
        'birth_date': '1990-01-02',
        'birth_time': '08:30',
        'gender': 'male',
        'birthplace': '上海市',
      },
    );
    expect(valid.validateAgainst(tool), isEmpty);
    const invalidTime = AssistantToolArguments(
      toolId: 'bazi',
      values: {
        'birth_date': '1990-01-02',
        'birth_time': '25:70',
        'gender': 'male',
        'birthplace': '上海市',
      },
    );
    expect(invalidTime.validateAgainst(tool), isNotEmpty);
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

  test('助手消息元数据往返保留知识状态、来源引用和工具重试参数', () {
    const metadata = AssistantMessageMetadata(
      mode: 'tools',
      selectedMode: 'automatic',
      toolId: 'yunqi',
      toolStatus: 'FAILED',
      sourceIds: ['neijing:chapter-1', 'medical_case:internal-seq:42'],
      toolArguments: {'date': '2026-11-07', 'location': 'Shanghai'},
      knowledgeStatus: 'PARTIAL',
      replayable: false,
    );

    final restored = AssistantMessageMetadata.decode(metadata.encode());
    expect(restored.mode, 'tools');
    expect(restored.selectedMode, 'automatic');
    expect(restored.toolId, 'yunqi');
    expect(restored.toolStatus, 'FAILED');
    expect(restored.sourceIds, metadata.sourceIds);
    expect(restored.toolArguments, metadata.toolArguments);
    expect(restored.knowledgeStatus, 'PARTIAL');
    expect(restored.replayable, isFalse);
  });

  test('旧版分号元数据仍可恢复模式与工具标识', () {
    final restored = AssistantMessageMetadata.decode(
      'mode=tools;selectedMode=automatic;tool=yunqi;tool_choice=false;replayable=false',
    );
    expect(restored.mode, 'tools');
    expect(restored.selectedMode, 'automatic');
    expect(restored.toolId, 'yunqi');
    expect(restored.replayable, isFalse);
    expect(restored.sourceIds, isEmpty);
    expect(restored.knowledgeStatus, isNull);
  });

  test('学习与工具角色明确要求知识综合和已执行结果解释', () {
    expect(AssistantMode.learning.promptHint, contains('总结、比较、归纳和解释'));
    expect(AssistantMode.learning.promptHint, contains('明确区分课程讲稿、古籍文本、医案'));
    expect(AssistantMode.tools.promptHint, contains('工具结果返回对话后'));
    expect(AssistantMode.tools.promptHint, contains('区分 App 确定性计算与 AI 解释'));
    expect(AssistantMode.consultation.promptHint, contains('解释、归纳该结果'));
    expect(AssistantMode.metaphysics.promptHint, contains('基于回传字段归纳结构'));
  });

}
