import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _connectTimeout = Duration(seconds: 25);
const _stallTimeout = Duration(seconds: 90);
const _maxManifestBytes = 64 * 1024;
const _maxApkBytes = 512 * 1024 * 1024;

bool validUrl(Uri uri) =>
    uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;

Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
  for (var redirects = 0; redirects <= 5; redirects++) {
    if (!validUrl(uri)) {
      throw const FormatException('更新地址必须使用 HTTPS。');
    }
    final request = await client.getUrl(uri).timeout(_connectTimeout);
    request.followRedirects = false;
    final response = await request.close().timeout(_connectTimeout);
    if (response.statusCode == HttpStatus.ok) return response;
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (!response.isRedirect || location == null) {
      throw HttpException('服务器返回 HTTP ${response.statusCode}。');
    }
    await response.drain<void>().timeout(_connectTimeout);
    uri = uri.resolve(location);
  }
  throw const HttpException('更新地址跳转次数过多。');
}

Future<String> readManifest(Uri uri) async {
  final client = HttpClient()..connectionTimeout = _connectTimeout;
  try {
    final response = await _get(client, uri);
    final bytes = <int>[];
    await for (final chunk in response.timeout(_connectTimeout)) {
      if (bytes.length + chunk.length > _maxManifestBytes) {
        throw const FormatException('更新信息超出大小限制。');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  } finally {
    client.close(force: true);
  }
}

Future<String> downloadApk(
  Uri uri,
  String cachePath,
  int versionCode,
  String expectedHash,
  void Function(int, int?) onProgress,
) async {
  try {
    return await _downloadApk(
      uri,
      cachePath,
      versionCode,
      expectedHash,
      onProgress,
    );
  } on FileSystemException {
    throw const FormatException('无法保存安装包，请检查手机存储空间。');
  }
}

Future<String> _downloadApk(
  Uri uri,
  String cachePath,
  int versionCode,
  String expectedHash,
  void Function(int, int?) onProgress,
) async {
  final directory = await Directory(cachePath).create(recursive: true);
  final separator = Platform.pathSeparator;
  final apk = File('${directory.path}${separator}cqut-$versionCode.apk');
  if (await apk.exists()) {
    if (await _matches(apk, expectedHash)) return apk.path;
    await apk.delete();
  }
  final partial = File('${apk.path}.part');
  final client = HttpClient()..connectionTimeout = _connectTimeout;
  try {
    final response = await _get(client, uri);
    final total = response.contentLength;
    if (total > _maxApkBytes) {
      throw const FormatException('安装包超出大小限制。');
    }
    final output = await partial.open(mode: FileMode.write);
    var received = 0;
    try {
      await for (final chunk in response.timeout(_stallTimeout)) {
        received += chunk.length;
        if (received > _maxApkBytes) {
          throw const FormatException('安装包超出大小限制。');
        }
        await output.writeFrom(chunk);
        onProgress(received, total > 0 ? total : null);
      }
    } finally {
      await output.close();
    }
    if (received == 0 ||
        (total > 0 && received != total) ||
        !await _matches(partial, expectedHash)) {
      throw const FormatException('安装包校验失败，请重新下载。');
    }
    await partial.rename(apk.path);
    return apk.path;
  } finally {
    client.close(force: true);
    if (await partial.exists()) await partial.delete();
  }
}

Future<bool> _matches(File file, String expectedHash) async =>
    (await sha256.bind(file.openRead()).first).toString() == expectedHash;
