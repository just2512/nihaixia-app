import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('About page explains the Three Chronicles identity and full product scope', () {
    final source = File('lib/screens/app_dialogs.dart').readAsStringSync();
    final start = source.indexOf('Future<void> showAboutPage(');
    final end = source.indexOf('/// 关于页中的单条更新日志卡片', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final about = source.substring(start, end);

    for (final requiredText in [
      '名称由来与含义',
      '倪海厦老师所讲的《天纪》《人纪》《地纪》三纪',
      '研习三纪、整理三纪',
      '项目定位与目标',
      '离线优先学习工具',
      '辅助学习',
      'AI 辅助解读',
      '帮助使用者理解知识内容、梳理不同主题之间的联系、逐步建立系统认识',
      '人纪相关',
      '天纪相关',
      '天纪、人纪、地纪共同构成研纪的核心知识脉络',
      '易经六十四卦',
      '六爻',
      '紫微斗数',
      '八字四柱',
      '小六壬',
      '梅花易数',
      '玉匣灵兆',
      '周公解梦',
      '适用人群',
      '倪师三纪学习者',
      '中医与经方研习者',
      '易学与传统术数爱好者',
      '传统文化跨领域学习者',
      '个人知识整理者',
    ]) {
      expect(about, contains(requiredText), reason: requiredText);
    }

    expect(about, isNot(contains('“纪”取纲纪、条理与记录之意')));
    expect(about, isNot(contains('中医诊疗软件')));
    expect(about, isNot(contains('诊疗软件')));
    expect(about, isNot(contains('医生诊疗')));
    expect(about, isNot(contains('临床判断')));
    expect(about, isNot(contains('面向中医诊疗全过程学习的软件')));
  });

  test('About page retains the original acknowledgements', () {
    final source = File('lib/screens/app_dialogs.dart').readAsStringSync();
    final start = source.indexOf('Future<void> showAboutPage(');
    final end = source.indexOf('/// 关于页中的单条更新日志卡片', start);
    final about = source.substring(start, end);

    expect(
      about,
      contains('感谢倪海厦老师的经方医学讲授与传承，感谢仲景先师留下《伤寒论》等经典。'),
    );
    expect(
      about,
      contains(
        '感谢原始开源项目 jangviktor-web/nihaixia-app 的作者，感谢 ziwei_core、Flutter / Dart 生态中的开源项目作者，以及所有社区贡献者。',
      ),
    );
  });
}
