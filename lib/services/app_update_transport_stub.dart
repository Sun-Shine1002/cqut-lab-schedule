Future<String> readManifest(
  Uri uri, {
  required Duration timeout,
  required bool sameOrigin,
}) => throw UnsupportedError('Android only');

Future<String> downloadApk(
  Uri uri,
  String cachePath,
  int versionCode,
  String expectedHash,
  void Function(int, int?) onProgress, {
  required bool sameOrigin,
}) => throw UnsupportedError('Android only');
