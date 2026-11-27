import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/changelog_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled changelog contains only explicitly project-owned entries', () {
    final decoded = jsonDecode(
      File('assets/data/changelog.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final entries = decoded['changelog'] as List<dynamic>;

    expect(entries, isNotEmpty);
    expect(
      entries.every(
        (entry) =>
            entry is Map<String, dynamic> && entry['project_owned'] == true,
      ),
      isTrue,
    );
    expect(
      entries.any(
        (entry) =>
            entry is Map<String, dynamic> && entry['version'] == '2.0.0',
      ),
      isTrue,
    );

    final serialized = jsonEncode(decoded);
    expect(serialized, isNot(contains('jangviktor-web/nihaixia-app')));
    expect(serialized, isNot(contains('上游版本源')));
    expect(serialized, isNot(contains('versionCode')));
    expect(serialized, isNot(contains('applicationId')));
  });

  test('About changelog repository loads project-owned entries only', () async {
    await ChangelogRepository.load();

    final entries = ChangelogRepository.getAll();
    expect(entries, isNotEmpty);
    expect(entries.every((entry) => entry.version.isNotEmpty), isTrue);
    expect(entries.map((entry) => entry.version), contains('2.0.0'));
  });

  test('About page contains only product introduction, updates and thanks', () {
    final source = File('lib/screens/app_dialogs.dart').readAsStringSync();

    expect(source, contains("const Text('项目介绍'"));
    expect(source, contains("const Text('版本更新'"));
    expect(source, contains("const Text('开源致谢'"));

    for (final forbidden in [
      'https://github.com/',
      'jangviktor-web/nihaixia-app',
      '上游开源项目',
      '复制上游地址',
      '本项目仓库地址',
      'Fork 关系',
      '人工评估、审查和同步',
      '上游变更',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
