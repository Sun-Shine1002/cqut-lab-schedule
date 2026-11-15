bool validUpdateUrl(Uri uri) =>
    uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;

String? _cnbReleaseRepository(Uri uri) {
  if (!_isHttpsHost(uri, 'cnb.cool')) return null;
  final segments = uri.pathSegments;
  final separator = segments.indexOf('-');
  if (separator < 2 ||
      segments.length != separator + 5 ||
      segments[separator + 1] != 'releases' ||
      segments[separator + 4].isEmpty) {
    return null;
  }
  final section = segments[separator + 2];
  final tagOrAction = segments[separator + 3];
  final versionDownload = section == 'download' && tagOrAction.isNotEmpty;
  final latestDownload = section == 'latest' && tagOrAction == 'download';
  if (!versionDownload && !latestDownload) return null;
  return segments.take(separator).join('/');
}

bool belongsToMirrorRepository(Uri apk, Uri feed) {
  if (apk.origin != feed.origin) return false;
  if (feed.host != 'cnb.cool') return true;
  final repo = _cnbReleaseRepository(feed);
  return repo != null && _cnbReleaseRepository(apk) == repo;
}

bool allowMirrorRedirect(Uri initial, Uri from, Uri to) {
  if (!validUpdateUrl(from) || !validUpdateUrl(to)) return false;
  if (to.origin == from.origin) return true;

  // CNB signs each public attachment URL and serves it on its asset domain.
  final repo = _cnbReleaseRepository(initial);
  return repo != null &&
      _cnbReleaseRepository(from) == repo &&
      _isHttpsHost(to, 'asset.cnb.cool');
}

bool _isHttpsHost(Uri uri, String host) =>
    validUpdateUrl(uri) && uri.host == host && uri.port == 443;
