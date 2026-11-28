import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fork update isolation policy', () {
    test('does not ship upstream updater, release prompt, or APK installer', () {
      expect(File('lib/services/update_service.dart').existsSync(), isFalse);
      expect(File('lib/services/whats_new_service.dart').existsSync(), isFalse);
      expect(File('lib/widgets/update_dialog.dart').existsSync(), isFalse);
      expect(File('test/services/update_service_test.dart').existsSync(), isFalse);
      expect(File('test/update_download_sources_test.dart').existsSync(), isFalse);

      final startup = File('lib/main.dart').readAsStringSync();
      expect(startup, isNot(contains('UpdateService')));
      expect(startup, isNot(contains('WhatsNewService')));

      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, isNot(contains('REQUEST_INSTALL_PACKAGES')));
      expect(manifest, isNot(contains('installApk')));

      expect(File('.github/workflows/gitee-sync.yml').existsSync(), isFalse);
      expect(File('.github/scripts/gitee_release.py').existsSync(), isFalse);
      expect(File('tools/sync_gitee.sh').existsSync(), isFalse);
    });

    test('keeps only the bundled local changelog in the About page', () {
      final repository =
          File('lib/data/changelog_repository.dart').readAsStringSync();
      final dialogs = File('lib/screens/app_dialogs.dart').readAsStringSync();

      expect(repository, contains("assets/data/changelog.json"));
      expect(dialogs, contains('ChangelogRepository.getAll()'));
      expect(dialogs, isNot(contains('UpdateService')));
      expect(dialogs, isNot(contains('WhatsNewService')));
    });
  });
  group('About content boundary', () {
    test(
      'keeps the About page focused on introduction, local updates, and open-source thanks',
      () {
        final dialogs =
            File('lib/screens/app_dialogs.dart').readAsStringSync();
        final start = dialogs.indexOf('Future<void> showAboutPage(');
        final end = dialogs.indexOf('/// 关于页中的单条更新日志卡片', start);
        expect(start, greaterThanOrEqualTo(0));
        expect(end, greaterThan(start));
        final about = dialogs.substring(start, end);

        expect(about, contains('名称由来与含义'));
        expect(about, contains('项目定位与目标'));
        expect(about, contains('知识内容与功能'));
        expect(about, contains('适用人群'));
        expect(about, contains('使用边界'));
        expect(about, contains('研纪更新记录'));
        expect(about, contains('开源致谢'));
        for (final forbidden in [
          'https://github.com',
          '上游',
          'Fork',
          '同步策略',
          '本项目仓库',
        ]) {
          expect(about, isNot(contains(forbidden)));
        }
      },
    );

    test(
      'shows only verified local history and independent product versions',
      () {
        final changelogFile = File('assets/data/changelog.json');
        final source = changelogFile.readAsStringSync();
        final decoded = jsonDecode(source) as Map<String, dynamic>;
        final entries = decoded['changelog'] as List<dynamic>;
        final versions = entries
            .map((entry) =>
                (entry as Map<String, dynamic>)['version'] as String)
            .toList();

        expect(versions, contains('2.0.0'));
        expect(versions, contains('1.11.30'));
        for (final version in versions) {
          final major = int.tryParse(version.split('.').first) ?? 0;
          expect(
            major >= 2 || version == '1.11.30',
            isTrue,
            reason:
                'About changelog must not reintroduce inherited release $version',
          );
        }
        expect(source, isNot(contains('上游')));
        expect(source, isNot(contains('upstream')));
        expect(source, isNot(contains('jangviktor-web')));
      },
    );

    test(
      'keeps repository integration details out of the README project introduction',
      () {
        final readme = File('README.md').readAsStringSync();
        final start = readme.indexOf('### 项目定位');
        final end = readme.indexOf('### 核心价值主张', start);
        expect(start, greaterThanOrEqualTo(0));
        expect(end, greaterThan(start));
        final introduction = readme.substring(start, end);

        expect(introduction, isNot(contains('https://github.com')));
        expect(introduction, isNot(contains('上游')));
        expect(introduction, isNot(contains('Fork')));
        expect(readme, isNot(contains('保留 GitHub Fork 关系')));
      },
    );
  });
}
