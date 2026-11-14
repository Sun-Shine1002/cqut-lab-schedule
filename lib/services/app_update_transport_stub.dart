bool validUrl(Uri uri) =>
    uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;

Future<String> readManifest(Uri uri) => throw UnsupportedError('Android only');

Future<String> downloadApk(
  Uri uri,
  String cachePath,
  int versionCode,
  String expectedHash,
  void Function(int, int?) onProgress,
) => throw UnsupportedError('Android only');
