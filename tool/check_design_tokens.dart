// 设计 token 回归门禁：禁止新改动里出现裸 Color(0x…) 与裸 fontSize 数字。
//
// 用法：
//   dart run tool/check_design_tokens.dart        # 只查本工作区相对 HEAD 新增/改动的 lib/*.dart
//   dart run tool/check_design_tokens.dart --all  # 全量扫（会命中历史遗留，仅用于盘点）
//
// 退出码：0 = 通过；1 = 有魔法值；2 = 环境异常。
// 颜色唯一来源 lib/theme/app_colors.dart，字号唯一来源 lib/theme/app_tokens.dart：
// 这两处是 token 定义文件，属于白名单。
import 'dart:io';

const _allowList = <String>[
  'lib/theme/app_colors.dart',
  'lib/theme/app_tokens.dart',
];

final _bareColor = RegExp(r'Color\((?:0x|0X)[0-9a-fA-F]');
final _bareFontSize = RegExp(r'fontSize:\s*\d');

Future<void> main(List<String> args) async {
  final scanAll = args.contains('--all');
  final changed = scanAll ? null : await _changedDartFiles();

  final lib = Directory('lib');
  if (!lib.existsSync()) {
    stderr.writeln('脚本需在项目根目录运行（找不到 lib/）。');
    exit(2);
  }

  final hits = <String>[];
  await for (final entity in lib.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.replaceAll('\\', '/');
    if (changed != null && !changed.contains(rel)) continue;
    if (_allowList.any(rel.startsWith)) continue;

    final lines = await entity.readAsLines();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_bareColor.hasMatch(line)) {
        hits.add('$rel:${i + 1} 裸 Color(0x…) —— 改用 AppColors/context.colors');
      }
      if (_bareFontSize.hasMatch(line)) {
        hits.add('$rel:${i + 1} 裸 fontSize 数字 —— 改用 AppType 档位');
      }
    }
  }

  if (hits.isEmpty) {
    stderr.writeln('OK：无裸 Color(0x…) / 裸 fontSize 数字。');
    exit(0);
  }

  stderr.writeln('发现 ${hits.length} 处魔法值：');
  for (final h in hits.take(80)) {
    stderr.writeln('  $h');
  }
  if (hits.length > 80) stderr.writeln('  …（其余 ${hits.length - 80} 处省略）');
  exit(1);
}

/// 需要检查的文件 = 相对 HEAD 已修改/暂存的 lib/*.dart + 未跟踪的新 lib/*.dart。
Future<Set<String>> _changedDartFiles() async {
  final result = <String>{};

  Future<void> add(List<String> command) async {
    final r = await Process.run('git', command);
    if (r.exitCode != 0) return;
    for (final line in r.stdout.toString().split('\n')) {
      final t = line.trim();
      if (t.endsWith('.dart') && t.startsWith('lib/')) {
        result.add(t.replaceAll('\\', '/'));
      }
    }
  }

  await add(['diff', '--name-only', '--ignore-cr-at-eol', 'HEAD', '--', 'lib']);
  await add(['ls-files', '--others', '--exclude-standard', '--', 'lib']);
  return result;
}