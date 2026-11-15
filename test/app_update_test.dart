import 'dart:async';
import 'dart:convert';

import 'package:cqut_lab_schedule/services/app_update.dart';
import 'package:cqut_lab_schedule/services/app_update_url_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mirror = Uri.https('updates.example.org', '/updates/update.json');
  final official = Uri.https(
    'github.com',
    '/OWNER/REPO/releases/latest/download/update.json',
  );
  const installed = AppUpdateInfo(
    versionName: '0.2.0',
    versionCode: 2,
    cachePath: '',
  );
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

  test(
    'uses the mirror without depending on GitHub for a mirrored update',
    () async {
      final checked = <Uri>[];
      final release = await AppUpdate.checkSources(
        installed,
        mirrorFeed: mirror,
        githubFeed: official,
        read: (uri, _) async {
          checked.add(uri);
          return jsonEncode({
            ...valid,
            'mirrorApkUrl': 'https://updates.example.org/updates/v3/cqut.apk',
          });
        },
      );
      expect(checked, [mirror]);
      final selected = release!;
      expect(selected.preferredSource, UpdateDownloadSource.mirror);
      expect(
        selected.downloadUrl(UpdateDownloadSource.mirror).origin,
        mirror.origin,
      );
      expect(
        selected.downloadUrl(UpdateDownloadSource.github).toString(),
        valid['apkUrl'],
      );
    },
  );

  test(
    'uses the official feed when the mirror times out or needs to catch up',
    () async {
      for (final timesOut in [true, false]) {
        final checked = <Uri>[];
        final release = await AppUpdate.checkSources(
          installed,
          mirrorFeed: mirror,
          githubFeed: official,
          read: (uri, timeout) async {
            checked.add(uri);
            if (uri == official) return jsonEncode(valid);
            if (timesOut) throw TimeoutException('mirror unavailable', timeout);
            return jsonEncode({
              ...valid,
              'versionCode': 2,
              'mirrorApkUrl': 'https://updates.example.org/updates/v2/cqut.apk',
            });
          },
        );
        expect(checked, [mirror, official]);
        expect(release?.preferredSource, UpdateDownloadSource.github);
      }
    },
  );

  test('ignores a cross-origin mirror URL on valid official metadata', () {
    final release = AppRelease.fromJson(
      jsonEncode({
        ...valid,
        'mirrorApkUrl': 'https://elsewhere.example.org/cqut.apk',
      }),
      mirrorFeed: mirror,
      githubFeed: official,
    );
    expect(release.preferredSource, UpdateDownloadSource.github);
    expect(
      () => AppRelease.fromJson(
        jsonEncode({
          ...valid,
          'apkUrl': 'https://github.com/another/repo/releases/download/v0.2.1/cqut.apk',
        }),
        githubFeed: official,
      ),
      throwsFormatException,
    );
  });

  test('accepts only canonical download URLs from the configured CNB repo', () {
    final feed = Uri.parse(
      'https://cnb.cool/group/team/repo/-/releases/download/latest/update.json',
    );
    final apk =
        'https://cnb.cool/group/team/repo/-/releases/download/v0.2.1/cqut.apk';
    final release = AppRelease.fromJson(
      jsonEncode({...valid, 'mirrorApkUrl': apk}),
      mirrorFeed: feed,
      githubFeed: official,
    );
    expect(release.preferredSource, UpdateDownloadSource.mirror);
    expect(release.mirrorApkUrl.toString(), apk);

    for (final redirected in [
      'https://cnb.cool/group/other/-/releases/download/v0.2.1/cqut.apk',
      'https://cnb.cool/group/team/repo/-/blob/main/cqut.apk',
      'https://cnb.cool:444/group/team/repo/-/releases/download/v0.2.1/cqut.apk',
      'https://asset.cnb.cool/temporary/cqut.apk',
    ]) {
      final mismatched = AppRelease.fromJson(
        jsonEncode({...valid, 'mirrorApkUrl': redirected}),
        mirrorFeed: feed,
        githubFeed: official,
      );
      expect(mismatched.preferredSource, UpdateDownloadSource.github);
    }
  });

  test('restricts mirror redirects to same origin or the CNB asset CDN', () {
    final cnb = Uri.parse(
      'https://cnb.cool/group/repo/-/releases/download/latest/update.json',
    );
    final asset = Uri.parse('https://asset.cnb.cool/attachment?signature=test');
    expect(allowMirrorRedirect(cnb, cnb, asset), isTrue);
    expect(allowMirrorRedirect(cnb, asset, cnb), isFalse);
    expect(
      allowMirrorRedirect(cnb, asset, asset.replace(path: '/next')),
      isTrue,
    );
    for (final lookalike in [
      Uri.parse('https://asset.cnb.cool.example.org/file'),
      Uri.parse('https://asset.cnb.cool:444/file'),
      Uri.parse('http://asset.cnb.cool/file'),
      Uri.parse('https://example.org/file'),
    ]) {
      expect(allowMirrorRedirect(cnb, cnb, lookalike), isFalse);
      expect(allowMirrorRedirect(cnb, asset, lookalike), isFalse);
    }
    expect(allowMirrorRedirect(mirror, mirror, asset), isFalse);
    expect(
      allowMirrorRedirect(mirror, mirror, mirror.replace(path: '/asset')),
      isTrue,
    );
  });
}
