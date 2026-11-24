import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;

  test('Android Release signing requires the original local keystore', () {
    final gradle = File('$root/android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('rootProject.file("key.properties")'));
    expect(gradle, contains('releaseKeyPropertiesFile.isFile'));
    expect(gradle, contains('Release signing is required'));
    expect(gradle, contains('missingSigningFields'));
    expect(gradle, contains('releaseKeystoreFile?.isFile != true'));
    expect(gradle, contains('signingConfig = signingConfigs.getByName("release")'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
  });

  test('Android Release requires a real non-test production issuer Key Ring', () {
    final gradle = File('$root/android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('YANJI_LICENSE_KEY_RING='));
    expect(gradle, contains('providers.gradleProperty("dart-defines")'));
    expect(gradle, contains('at least one production issuer public key is required'));
    expect(gradle, contains('test-issuer-01'));
    expect(gradle, contains('A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg'));
    expect(gradle, contains('03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8'));
    expect(gradle, contains('at least one active or standby production issuer is required'));
  });
  test('the CI workflow verifies the missing-key Release guard without publishing APKs', () {
    final workflow = File('$root/.github/workflows/flutter-tests.yml').readAsStringSync();

    expect(workflow, contains('Verify Release build is blocked without local signing material'));
    expect(workflow, contains(':app:assembleRelease --dry-run'));
    expect(workflow, contains('Release signing is required'));
    expect(workflow, contains('no Release APK was built'));
  });

  test('the template requires restoring the existing signing identity', () {
    final template = File('$root/android/key.properties.template').readAsStringSync();

    expect(template, contains('Do NOT generate a new keystore'));
    expect(template, contains('storeFile=../nihaisha.jks'));
    expect(template, contains('storeType=PKCS12'));
  });
}
