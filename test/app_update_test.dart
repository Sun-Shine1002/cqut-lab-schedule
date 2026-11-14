import 'dart:convert';

import 'package:cqut_lab_schedule/services/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final valid = {
    'versionName': '0.2.1',
    'versionCode': 3,
    'notes': '更新课表',
    'apkUrl': 'https://github.com/OWNER/REPO/releases/download/v0.2.1/cqut.apk',
    'sha256': 'AB' * 32,
  };

  test('reads the exact release asset URL and normalizes SHA-256', () {
    final release = AppRelease.fromJson(jsonEncode(valid));
    expect(release.versionCode, 3);
    expect(release.apkUrl.path, endsWith('/v0.2.1/cqut.apk'));
    expect(release.sha256, 'ab' * 32);
  });

  test('rejects insecure URLs, invalid hashes, and unusable versions', () {
    for (final invalid in [
      {'apkUrl': 'http://github.com/cqut.apk'},
      {'apkUrl': 'https://user@example.org/cqut.apk'},
      {'apkUrl': 'https://github.com/cqut.zip'},
      {'sha256': '0' * 63},
      {'versionCode': -1},
      {'versionCode': '3'},
    ]) {
      expect(
        () => AppRelease.fromJson(jsonEncode({...valid, ...invalid})),
        throwsFormatException,
      );
    }
  });
}
