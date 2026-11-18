import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


APK = "cqut-schedule.apk"
MANIFEST = "update.json"
APP_ID = "com.cqutlabs.cqut_lab_schedule"
SIGNER = "12fede291ce62c6a2466dd95fe80b0e548b1003f7b398cba73e066e76bfb1f89"
TAG = re.compile(r"v[0-9]+\.[0-9]+\.[0-9]+")
HASH = re.compile(r"[a-f0-9]{64}")
MANIFEST_KEY = "updates/update.json"


def gh(*args):
    return subprocess.check_output(
        ["gh", *args], text=True, encoding="utf-8", timeout=45,
    )


def latest_tag(repository):
    tag = gh("api", f"repos/{repository}/releases/latest", "--jq", ".tag_name").strip()
    if not TAG.fullmatch(tag):
        raise ValueError("The latest official release must have a stable version tag.")
    return tag


def download_release(repository, tag, directory):
    subprocess.run(
        [
            "gh", "release", "download", tag, "--repo", repository,
            "--pattern", APK, "--pattern", MANIFEST, "--dir", directory,
        ],
        check=True,
        timeout=360,
    )


def release_manifest(path, repository, tag):
    if path.stat().st_size > 65536:
        raise ValueError("Release metadata exceeds the app limit.")
    data = json.loads(path.read_text(encoding="utf-8"))
    expected = f"https://github.com/{repository}/releases/download/{tag}/{APK}"
    known = {"versionName", "versionCode", "notes", "apkUrl", "sha256"}
    if (
        not isinstance(data, dict)
        or not known <= data.keys()
        or data["versionName"] != tag[1:]
        or type(data["versionCode"]) is not int
        or not 0 < data["versionCode"] <= 2_100_000_000
        or not isinstance(data["notes"], str)
        or len(data["notes"].encode("utf-16-le")) // 2 > 12000
        or data["apkUrl"] != expected
        or not isinstance(data["sha256"], str)
        or not HASH.fullmatch(data["sha256"])
    ):
        raise ValueError("The official update manifest does not match the release.")
    return {key: data[key] for key in sorted(known)}


def check_apk(path, data):
    if not 0 < path.stat().st_size <= 512 * 1024 * 1024:
        raise ValueError("The APK exceeds the app limit.")
    with path.open("rb") as apk:
        if hashlib.file_digest(apk, "sha256").hexdigest() != data["sha256"]:
            raise ValueError("The official APK SHA-256 does not match update.json.")
    sdk = os.environ.get("ANDROID_HOME") or os.environ["ANDROID_SDK_ROOT"]
    aapt_name, signer_name = ("aapt.exe", "apksigner.bat") if os.name == "nt" else ("aapt", "apksigner")
    tools = Path(sdk) / "build-tools"
    tools = max(
        (p for p in tools.iterdir() if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", p.name)
         and (p / signer_name).is_file() and (p / aapt_name).is_file()),
        key=lambda p: tuple(map(int, p.name.split("."))),
    )
    badging = subprocess.check_output(
        [tools / aapt_name, "dump", "badging", path], text=True, encoding="utf-8",
    )
    expected = (
        f"package: name='{APP_ID}' versionCode='{data['versionCode']}' "
        f"versionName='{data['versionName']}'"
    )
    if not badging.startswith(expected + " ") or "application-debuggable" in badging.splitlines():
        raise ValueError("Unexpected APK application ID, release version, or build type.")
    certificates = subprocess.check_output(
        [tools / signer_name, "verify", "--print-certs", path], text=True, encoding="utf-8",
    )
    signers = re.findall(r"\bcertificate SHA-256 digest: ([a-fA-F0-9]{64})$",
                         certificates, flags=re.MULTILINE)
    if {value.lower() for value in signers} != {SIGNER}:
        raise ValueError("APK signer differs from the released Android signing certificate.")


def mirror_base(value):
    value = value.rstrip("/")
    parts = urlsplit(value)
    if (
        parts.scheme != "https" or not parts.hostname
        or parts.username or parts.password or parts.path or parts.query or parts.fragment
        or any(char.isspace() for char in value)
        or parts.hostname.endswith((".myqcloud.com", ".tencentcos.cn"))
    ):
        raise ValueError("Use a custom HTTPS distribution domain for APK downloads.")
    return value


class SameOriginRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        destination = urlsplit(newurl)
        source = urlsplit(req.full_url)
        if (destination.scheme, destination.netloc) != (source.scheme, source.netloc):
            raise ValueError("The public mirror must stay on its configured HTTPS origin.")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


PUBLIC_HTTP = build_opener(SameOriginRedirects())


def public_open(url):
    return PUBLIC_HTTP.open(Request(url, headers={
        "User-Agent": "CQUT-release-mirror",
        "Cache-Control": "no-cache",
    }), timeout=30)


def verify_public_apk(url, path, expected):
    digest = hashlib.sha256()
    size = 0
    with public_open(url) as response:
        for block in iter(lambda: response.read(1024 * 1024), b""):
            size += len(block)
            if size > path.stat().st_size:
                raise ValueError("Public mirror returned a larger file than the official APK.")
            digest.update(block)
    if size != path.stat().st_size or digest.hexdigest() != expected:
        raise ValueError("Public mirror APK does not match the official release.")


def current_mirror(base):
    try:
        with public_open(f"{base}/{MANIFEST_KEY}") as response:
            content = response.read(65537)
    except HTTPError as error:
        if error.code == 404:
            return None
        raise
    if len(content) > 65536:
        raise ValueError("The current mirror manifest is too large.")
    data = json.loads(content)
    if not isinstance(data, dict) or type(data.get("versionCode")) is not int:
        raise ValueError("The current mirror has invalid version metadata.")
    return data


def sync(client, bucket, base, repository, tag, path, data):
    existing = current_mirror(base)
    if existing and existing["versionCode"] > data["versionCode"]:
        raise ValueError("The official release has an older build number than the mirror.")
    if (existing and existing["versionCode"] == data["versionCode"]
            and existing.get("sha256") != data["sha256"]):
        raise ValueError("Do not republish different APK contents with the same build number.")

    apk_key = f"updates/releases/{tag}/{data['sha256']}/{APK}"
    url = f"{base}/{apk_key}"
    try:
        verify_public_apk(url, path, data["sha256"])
    except HTTPError as error:
        if error.code != 404:
            raise
        with path.open("rb") as apk:
            client.put_object(
                Bucket=bucket, Key=apk_key, Body=apk, EnableMD5=True,
                ContentType="application/vnd.android.package-archive",
                CacheControl="public, max-age=31536000, immutable",
            )
        verify_public_apk(url, path, data["sha256"])

    if latest_tag(repository) != tag:
        raise ValueError("A newer GitHub release was published during sync. Rerun the sync.")

    mirror = dict(data, mirrorApkUrl=url)
    payload = (json.dumps(mirror, ensure_ascii=False) + "\n").encode("utf-8")
    if len(payload) > 65536:
        raise ValueError("Mirror metadata exceeds the app limit.")
    client.put_object(
        Bucket=bucket, Key=MANIFEST_KEY, Body=payload, EnableMD5=True,
        ContentType="application/json; charset=utf-8", CacheControl="no-store",
    )
    if current_mirror(base) != mirror:
        raise ValueError("Public mirror manifest differs from the published metadata.")
    print(f"Verified and synced {tag} to the public mirror.")


def main():
    from qcloud_cos import CosConfig, CosS3Client

    repository = os.environ["GITHUB_REPOSITORY"]
    bucket = os.environ["CQUT_COS_BUCKET"]
    region = os.environ["CQUT_COS_REGION"]
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]+-[0-9]+", bucket) or not re.fullmatch(r"ap-[a-z0-9-]+", region):
        raise ValueError("Use the full COS bucket name and its region ID.")
    base = mirror_base(os.environ["CQUT_MIRROR_BASE_URL"])
    secret_id = os.environ.get("CQUT_COS_SECRET_ID")
    secret_key = os.environ.get("CQUT_COS_SECRET_KEY")
    if not secret_id or not secret_key:
        raise ValueError("The COS upload credentials are missing from GitHub Secrets.")
    client = CosS3Client(CosConfig(
        Region=region, SecretId=secret_id, SecretKey=secret_key, Scheme="https",
    ))
    tag = latest_tag(repository)
    with TemporaryDirectory() as directory:
        download_release(repository, tag, directory)
        apk = Path(directory) / APK
        data = release_manifest(Path(directory) / MANIFEST, repository, tag)
        check_apk(apk, data)
        sync(client, bucket, base, repository, tag, apk, data)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Mirror sync failed: {error}", file=sys.stderr)
        sys.exit(1)
