import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_update_transport_stub.dart'
    if (dart.library.io) 'app_update_transport_io.dart'
    as transport;

const _updateUrl = String.fromEnvironment('CQUT_UPDATE_URL');

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
  });

  factory AppRelease.fromJson(String json) {
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
      final uri = Uri.tryParse(url);
      if (uri != null &&
          transport.validUrl(uri) &&
          uri.path.toLowerCase().endsWith('.apk')) {
        return AppRelease(
          versionName: name,
          versionCode: code,
          notes: notes.trim(),
          apkUrl: uri,
          sha256: checksum.toLowerCase(),
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
}

class AppUpdate {
  static const _channel = MethodChannel(
    'com.cqutlabs.cqut_lab_schedule/app_update',
  );

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get configured => _updateUrl.isNotEmpty;

  static Future<AppUpdateInfo> info() async {
    final data = await _channel.invokeMapMethod<String, Object?>('getInfo');
    return AppUpdateInfo(
      versionName: data!['versionName'] as String,
      versionCode: data['versionCode'] as int,
      cachePath: data['cachePath'] as String,
    );
  }

  static Future<AppRelease?> check(AppUpdateInfo installed) async {
    final uri = Uri.parse(_updateUrl);
    final release = AppRelease.fromJson(await transport.readManifest(uri));
    return release.versionCode > installed.versionCode ? release : null;
  }

  static Future<String> download(
    AppUpdateInfo installed,
    AppRelease release,
    void Function(int received, int? total) onProgress,
  ) => transport.downloadApk(
    release.apkUrl,
    installed.cachePath,
    release.versionCode,
    release.sha256,
    onProgress,
  );

  static Future<void> install(String path, AppRelease release) =>
      _channel.invokeMethod<void>('install', {
        'path': path,
        'versionCode': release.versionCode,
      });

  static Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');
}
