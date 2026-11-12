import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android backup rules exclude only local AI model and TRACE files', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final legacyRules = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final extractionRules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android:fullBackupContent="@xml/backup_rules"'),
    );
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, isNot(contains('android:allowBackup="false"')));

    for (final rules in [legacyRules, extractionRules]) {
      expect(rules, contains('path="ai_models/"'));
      expect(rules, contains('path="ai_trace.jsonl"'));
      expect(rules, contains('path="ai_trace.jsonl.tmp"'));
      expect(rules, isNot(contains('domain="database"')));
    }

    // AI and non-AI records share nihaisha.db. Excluding the database domain
    // would silently remove backup coverage for bookmarks and diagnosis data.
    expect(legacyRules, contains('<full-backup-content>'));
    expect(extractionRules, contains('<cloud-backup>'));
    expect(extractionRules, contains('<device-transfer>'));
  });
}
