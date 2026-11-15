import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_update_transport_stub.dart'
    if (dart.library.io) 'app_update_transport_io.dart'
    as transport;
import 'app_update_url_policy.dart';

const _updateUrl = String.fromEnvironment('CQUT_UPDATE_URL');
const _mirrorUpdateUrl = String.fromEnvironment('CQUT_UPDATE_MIRROR_URL');
const _mirrorManifestTimeout = Duration(seconds: 5);
const _githubManifestTimeout = Duration(seconds: 8);

enum UpdateDownloadSource { mirror, github }

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.cachePath,
  });

  final String versionName;
  final int versionCode;
  final String cachePath;
}

class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.notes,
    required this.apkUrl,
    required this.sha256,
    this.mirrorApkUrl,
  });

  factory AppRelease.fromJson(String json, {Uri? mirrorFeed, Uri? githubFeed}) {
    final source = jsonDecode(json);
    if (source
        case {
          'versionName': final String name,
          'versionCode': final int code,
          'notes': final String notes,
          'apkUrl': final String url,
          'sha256': final String checksum,
        }
        when name.isNotEmpty &&
            name.length <= 80 &&
            code > 0 &&
            code <= 2100000000 &&
            notes.length <= 12000 &&
            RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(checksum)) {
      final uri = _apkUrl(url);
      if (uri != null && _belongsToReleaseRepository(uri, githubFeed)) {
        final mirror = _apkUrl(source['mirrorApkUrl']);
        return AppRelease(
          versionName: name,
          versionCode: code,
          notes: notes.trim(),
          apkUrl: uri,
          sha256: checksum.toLowerCase(),
          mirrorApkUrl:
              mirror != null &&
                  mirror != uri &&
                  (mirrorFeed == null ||
                      belongsToMirrorRepository(mirror, mirrorFeed))
              ? mirror
              : null,
        );
      }
    }
    throw const FormatException('更新信息格式无效。');
  }

  final String versionName;
  final int versionCode;
  final String notes;
  final Uri apkUrl;
  final String sha256;
  final Uri? mirrorApkUrl;

  UpdateDownloadSource get preferredSource => mirrorApkUrl == null
      ? UpdateDownloadSource.github
      : UpdateDownloadSource.mirror;

  Uri downloadUrl(UpdateDownloadSource source) => switch (source) {
    UpdateDownloadSource.mirror =>
      mirrorApkUrl ?? (throw StateError('当前版本没有国内下载地址。')),
    UpdateDownloadSource.github => apkUrl,
  };

  static Uri? _apkUrl(Object? value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        !validUpdateUrl(uri) ||
        !uri.path.toLowerCase().endsWith('.apk')) {
      return null;
    }
    return uri;
  }

  static bool _belongsToReleaseRepository(Uri apk, Uri? feed) {
    if (feed == null || feed.host != 'github.com') return true;
    final manifestPath = feed.pathSegments;
    final apkPath = apk.pathSegments;
    if (manifestPath.length < 3 || manifestPath[2] != 'releases') return true;
    return apk.origin == feed.origin &&
        apkPath.length >= 6 &&
        apkPath[0].toLowerCase() == manifestPath[0].toLowerCase() &&
        apkPath[1].toLowerCase() == manifestPath[1].toLowerCase() &&
        apkPath[2] == 'releases' &&
        apkPath[3] == 'download';
  }
}

class AppUpdate {
  static const _channel = MethodChannel(
    'com.cqutlabs.cqut_lab_schedule/app_update',
  );

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get configured =>
      _updateUrl.isNotEmpty || _mirrorUpdateUrl.isNotEmpty;

  static Future<AppUpdateInfo> info() async {
    final data = await _channel.invokeMapMethod<String, Object?>('getInfo');
    return AppUpdateInfo(
      versionName: data!['versionName'] as String,
      versionCode: data['versionCode'] as int,
      cachePath: data['cachePath'] as String,
    );
  }

  static Future<AppRelease?> check(AppUpdateInfo installed) => checkSources(
    installed,
    mirrorFeed: _manifestUrl(_mirrorUpdateUrl),
    githubFeed: _manifestUrl(_updateUrl),
    read: (uri, timeout) => transport.readManifest(
      uri,
      timeout: timeout,
      sameOrigin: uri == _manifestUrl(_mirrorUpdateUrl),
    ),
  );

  static Uri? _manifestUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && validUpdateUrl(uri) ? uri : null;
  }

  @visibleForTesting
  static Future<AppRelease?> checkSources(
    AppUpdateInfo installed, {
    required Uri? mirrorFeed,
    required Uri? githubFeed,
    required Future<String> Function(Uri, Duration) read,
  }) async {
    AppRelease? mirrorRelease;
    Exception? mirrorError;
    if (mirrorFeed != null) {
      try {
        mirrorRelease = AppRelease.fromJson(
          await read(mirrorFeed, _mirrorManifestTimeout),
          mirrorFeed: mirrorFeed,
          githubFeed: githubFeed,
        );
        if (mirrorRelease.mirrorApkUrl == null) {
          mirrorRelease = null;
          throw const FormatException('国内更新信息缺少有效的下载地址。');
        }
        if (mirrorRelease.versionCode > installed.versionCode) {
          return mirrorRelease;
        }
      } on Exception catch (error) {
        mirrorError = error;
      }
    }

    if (githubFeed != null && githubFeed != mirrorFeed) {
      try {
        final release = AppRelease.fromJson(
          await read(githubFeed, _githubManifestTimeout),
          mirrorFeed: mirrorFeed,
          githubFeed: githubFeed,
        );
        return release.versionCode > installed.versionCode ? release : null;
      } on Exception {
        if (mirrorRelease == null) rethrow;
      }
    }

    if (mirrorRelease != null) return null;
    throw mirrorError ?? const FormatException('没有可用的更新地址。');
  }

  static Future<String> download(
    AppUpdateInfo installed,
    AppRelease release,
    void Function(int received, int? total) onProgress, {
    UpdateDownloadSource? source,
  }) {
    final selected = source ?? release.preferredSource;
    return transport.downloadApk(
      release.downloadUrl(selected),
      installed.cachePath,
      release.versionCode,
      release.sha256,
      onProgress,
      sameOrigin: selected == UpdateDownloadSource.mirror,
    );
  }

  static Future<void> install(String path, AppRelease release) =>
      _channel.invokeMethod<void>('install', {
        'path': path,
        'versionCode': release.versionCode,
      });

  static Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');
}
