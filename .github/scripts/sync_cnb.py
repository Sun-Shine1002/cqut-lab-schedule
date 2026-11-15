import hashlib
import json
import os
import re
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, urlencode, urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

from sync_mirror import APK, MANIFEST, check_apk, download_release, latest_tag, release_manifest


API = "https://api.cnb.cool"
WEB = "https://cnb.cool"
REPOSITORY = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*(?:/[a-zA-Z0-9][a-zA-Z0-9_.-]*)+")


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class AssetRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        destination = urlsplit(newurl)
        source = urlsplit(req.full_url)
        if (destination.scheme == "https" and destination.port in (None, 443)
                and not destination.username and not destination.password
                and source.hostname == "cnb.cool"
                and destination.hostname in {"cnb.cool", "asset.cnb.cool"}):
            return super().redirect_request(req, fp, code, msg, headers, newurl)
        return None


NO_REDIRECTS = build_opener(NoRedirects())
PUBLIC = build_opener(AssetRedirects())


class CnbRelease:
    def __init__(self, repository, token):
        self.root = f"{API}/{repository}/-/releases"
        self.web = f"{WEB}/{repository}/-/releases/download"
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.cnb.api+json",
        }

    def api(self, url, method="GET", data=None, *, optional=False, read_body=True):
        headers = dict(self.headers)
        payload = None
        if data is not None:
            payload = json.dumps(data, ensure_ascii=False).encode()
            headers["Content-Type"] = "application/json"
        request = Request(url, data=payload, headers=headers, method=method)
        try:
            with NO_REDIRECTS.open(request, timeout=30) as response:
                if not read_body:
                    return None
                result = response.read(2 * 1024 * 1024 + 1)
        except HTTPError as error:
            if optional and error.code == 404:
                return None
            raise ValueError(f"CNB {method} returned HTTP {error.code}.") from None
        if len(result) > 2 * 1024 * 1024:
            raise ValueError("CNB API response is too large.")
        return json.loads(result) if result else None

    def upload(self, release_url, file):
        size = file.stat().st_size
        ticket = self.api(f"{release_url}/asset-upload-url", "POST", {
            "asset_name": file.name, "size": size, "overwrite": False, "ttl": 0,
        })
        upload_url = ticket["upload_url"]
        destination = urlsplit(upload_url)
        confirmation = urljoin(API + "/", ticket["verify_url"])
        verify = urlsplit(confirmation)
        prefix = urlsplit(release_url).path + "/asset-upload-confirmation/"
        if (
            destination.scheme != "https" or not destination.hostname
            or destination.username or destination.password
            or verify.scheme != "https" or verify.netloc != "api.cnb.cool"
            or not verify.path.startswith(prefix) or verify.fragment
        ):
            raise ValueError("CNB returned invalid upload URLs.")
        try:
            with file.open("rb") as body:
                request = Request(upload_url, data=body, method="PUT", headers={
                    "Content-Length": str(size),
                    "Content-Type": "application/octet-stream",
                })
                with NO_REDIRECTS.open(request, timeout=180):
                    pass
        except (HTTPError, URLError) as error:
            status = f" HTTP {error.code}" if isinstance(error, HTTPError) else ""
            raise ValueError(f"CNB upload did not complete for {file.name}.{status}") from None
        query = [(key, value) for key, value in parse_qsl(verify.query) if key != "ttl"]
        query.append(("ttl", "0"))
        self.api(verify._replace(query=urlencode(query)).geturl(), "POST", read_body=False)

    def public_asset(self, tag, name):
        request = Request(f"{self.web}/{tag}/{name}", headers={"Cache-Control": "no-cache"})
        return PUBLIC.open(request, timeout=45)

    def read_manifest(self, tag, *, optional=False):
        try:
            with self.public_asset(tag, MANIFEST) as response:
                payload = response.read(65537)
        except HTTPError as error:
            if optional and error.code == 404:
                return None
            raise
        if len(payload) > 65536:
            raise ValueError("CNB metadata exceeds the app limit.")
        return payload

    def verify_apk(self, tag, length, checksum):
        size, digest = 0, hashlib.sha256()
        with self.public_asset(tag, APK) as response:
            for block in iter(lambda: response.read(1024 * 1024), b""):
                size += len(block)
                if size > length:
                    raise ValueError("CNB returned a larger APK than the original.")
                digest.update(block)
        if size != length or digest.hexdigest() != checksum:
            raise ValueError("CNB APK differs from the original GitHub APK.")


def sync(cnb, github, tag, apk, official):
    mirror = dict(official, mirrorApkUrl=f"{cnb.web}/{tag}/{APK}")
    payload = (json.dumps(mirror, ensure_ascii=False) + "\n").encode()
    if len(payload) > 65536:
        raise ValueError("CNB metadata exceeds the app limit.")

    existing = cnb.read_manifest("latest", optional=True)
    if existing is not None:
        data = json.loads(existing)
        version = data["versionCode"]
        if type(version) is not int or version > official["versionCode"]:
            raise ValueError("CNB latest version must not go backwards.")
        if version == official["versionCode"] and data["sha256"] != official["sha256"]:
            raise ValueError("Do not reuse a build number for different APKs.")

    release = cnb.api(f"{cnb.root}/tags/{tag}", optional=True)
    if release is None:
        release = cnb.api(cnb.root, "POST", {
            "tag_name": tag, "target_commitish": "main", "name": tag,
            "body": f"Official APK: {official['apkUrl']}",
            "draft": True, "prerelease": False, "make_latest": "false",
        })
    release_id = str(release["id"])
    if not re.fullmatch(r"[A-Za-z0-9_-]+", release_id):
        raise ValueError("CNB returned an invalid release ID.")
    release_url = f"{cnb.root}/{release_id}"
    release = cnb.api(release_url)
    assets = {entry["name"]: entry for entry in (release.get("assets") or [])}

    manifest = apk.with_name(MANIFEST)
    manifest.write_bytes(payload)
    for file in (apk, manifest):
        asset = assets.get(file.name)
        if asset is not None:
            if asset["size"] != file.stat().st_size:
                raise ValueError(f"Existing CNB attachment has a different size: {file.name}")
            if asset.get("hash_algo", "").lower() == "sha256":
                with file.open("rb") as stream:
                    if hashlib.file_digest(stream, "sha256").hexdigest() != asset["hash_value"].lower():
                        raise ValueError(f"Existing CNB attachment hash differs: {file.name}")
        elif release["draft"]:
            cnb.upload(release_url, file)
        else:
            raise ValueError(f"Published CNB release is missing {file.name}.")

    if latest_tag(github) != tag:
        raise ValueError("GitHub latest changed while syncing. Rerun the workflow.")
    if release["draft"]:
        cnb.api(release_url, "PATCH", {"draft": False, "make_latest": "false"}, read_body=False)
    cnb.verify_apk(tag, apk.stat().st_size, mirror["sha256"])
    if cnb.read_manifest(tag) != payload:
        raise ValueError("CNB public metadata differs from the uploaded file.")
    if latest_tag(github) != tag:
        raise ValueError("GitHub latest changed while syncing. Rerun the workflow.")
    cnb.api(release_url, "PATCH", {"make_latest": "true"}, read_body=False)
    if cnb.read_manifest("latest") != payload:
        raise ValueError("CNB latest does not serve the verified update metadata.")
    print(f"Verified and synced {tag} to the public CNB mirror.")


def main():
    github = os.environ["GITHUB_REPOSITORY"]
    repository = os.environ["CQUT_CNB_REPOSITORY"]
    token = os.environ.get("CQUT_CNB_RELEASE_TOKEN")
    if not REPOSITORY.fullmatch(repository) or repository.endswith(".git") or not token:
        raise ValueError("Configure a public CNB repository path and its release token.")
    cnb = CnbRelease(repository, token)
    tag = latest_tag(github)
    with TemporaryDirectory() as directory:
        download_release(github, tag, directory)
        root = Path(directory)
        apk = root / APK
        official = release_manifest(root / MANIFEST, github, tag)
        check_apk(apk, official)
        sync(cnb, github, tag, apk, official)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"CNB sync failed: {error}", file=sys.stderr)
        sys.exit(1)
