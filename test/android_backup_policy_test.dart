import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android app disables cloud backup and device transfer for private data', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final fullBackup = File('android/app/src/main/res/xml/backup_rules.xml').readAsStringSync();
    final extraction = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));

    for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
      expect(fullBackup, contains('<exclude domain="$domain" path="."'));
      expect(extraction, contains('<exclude domain="$domain" path="."'));
    }
    for (final domain in [
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    ]) {
      expect(extraction, contains('<exclude domain="$domain" path="."'));
    }
  });
}
