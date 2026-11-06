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
}
