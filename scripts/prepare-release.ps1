[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9-]+/[a-zA-Z0-9_.-]+$')]
    [string] $Repository,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1, 12000)]
    [string] $Notes,

    [string] $AndroidSdk = $env:ANDROID_HOME,
    [string] $FlutterCommand = 'flutter',
    [string] $ApkPath,
    [string] $MirrorBaseUrl = $env:CQUT_MIRROR_BASE_URL,
    [string] $CnbRepository = $env:CQUT_CNB_REPOSITORY
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionLine = Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') `
    -Pattern '^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$' | Select-Object -First 1
if ($null -eq $versionLine) {
    throw 'Set a stable build version in pubspec.yaml, for example version: 0.2.0+2.'
}

$versionName = $versionLine.Matches[0].Groups[1].Value
$versionCode = 0
if (-not [int]::TryParse($versionLine.Matches[0].Groups[2].Value, [ref] $versionCode) -or $versionCode -gt 2100000000) {
    throw 'The build number in pubspec.yaml must be at most 2100000000.'
}
$tag = "v$versionName"
$apkName = 'cqut-schedule.apk'
$outputDirectory = Join-Path $projectRoot "build/releases/$tag"
$updateUrl = "https://github.com/$Repository/releases/latest/download/update.json"
$mirrorUpdateUrl = $null
if ($CnbRepository) {
    if ($MirrorBaseUrl -or $CnbRepository -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]*(/[a-zA-Z0-9][a-zA-Z0-9_.-]*)+$' -or
        $CnbRepository.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Provide a CNB repository path (group/project) and omit -MirrorBaseUrl.'
    }
    $mirrorUpdateUrl = "https://cnb.cool/$CnbRepository/-/releases/download/latest/update.json"
} elseif ($MirrorBaseUrl) {
    $base = $MirrorBaseUrl.TrimEnd('/')
    $uri = [uri] $base
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or -not $uri.Host -or
        $uri.UserInfo -or $uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment -or
        $base -match '\s' -or $uri.Host -match '\.(myqcloud\.com|tencentcos\.cn)$') {
        throw 'Use a custom HTTPS domain for APK downloads in -MirrorBaseUrl.'
    }
    $mirrorUpdateUrl = "$base/updates/update.json"
}
if (Test-Path -LiteralPath $outputDirectory) {
    throw "Release directory already exists: $outputDirectory"
}

if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
if (-not $AndroidSdk) {
    throw 'Set ANDROID_HOME or pass -AndroidSdk pointing to the Android SDK.'
}
$buildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
    Where-Object {
        ($_.Name -as [version]) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe')) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat'))
    } | Sort-Object { $_.Name -as [version] } -Descending | Select-Object -First 1
if ($null -eq $buildTools) {
    throw 'Install Android SDK Build-Tools with aapt and apksigner.'
}

if (-not $ApkPath) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'android/key.properties') -PathType Leaf)) {
        throw 'Set up release signing in android/key.properties before building the release APK.'
    }
    Push-Location -LiteralPath $projectRoot
    try {
        $buildArguments = @('build', 'apk', '--release', "--dart-define=CQUT_UPDATE_URL=$updateUrl")
        if ($mirrorUpdateUrl) {
            $buildArguments += "--dart-define=CQUT_UPDATE_MIRROR_URL=$mirrorUpdateUrl"
        }
        & $FlutterCommand @buildArguments
        if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed.' }
    } finally {
        Pop-Location
    }
    $ApkPath = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-release.apk'
}

$apk = Get-Item -LiteralPath $ApkPath
$aapt = Join-Path $buildTools.FullName 'aapt.exe'
$badging = & $aapt dump badging $apk.FullName
if ($LASTEXITCODE -ne 0) { throw 'Could not read the APK manifest.' }
$expectedPackage = "package: name='com.cqutlabs.cqut_lab_schedule' versionCode='$versionCode' versionName='$versionName' "
if (-not ($badging | Where-Object { $_.StartsWith($expectedPackage) })) {
    throw 'APK package name or version does not match this project and pubspec.yaml.'
}
if ($badging -contains 'application-debuggable') {
    throw 'Use a non-debuggable release APK.'
}

$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
$signers = & $apksigner verify --print-certs $apk.FullName
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
if ($signers -match 'certificate DN:.*\bCN=Android Debug\b') {
    throw 'Use the release key to sign the APK. This APK uses an Android debug certificate.'
}
$certificate = '12fede291ce62c6a2466dd95fe80b0e548b1003f7b398cba73e066e76bfb1f89'
$publisherCertificates = @($signers | ForEach-Object {
    if ($_ -match 'certificate SHA-256 digest: ([a-fA-F0-9]{64})$') { $Matches[1] }
} | Select-Object -Unique)
if ($publisherCertificates.Count -ne 1 -or $publisherCertificates[0] -ne $certificate) {
    throw 'APK certificate must match the signing certificate used in published CQUT releases.'
}

$null = New-Item -ItemType Directory -Path $outputDirectory
$asset = Join-Path $outputDirectory $apkName
Copy-Item -LiteralPath $apk.FullName -Destination $asset
$manifest = [ordered] @{
    versionName = $versionName
    versionCode = $versionCode
    notes = $Notes
    apkUrl = "https://github.com/$Repository/releases/download/$tag/$apkName"
    sha256 = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifestPath = Join-Path $outputDirectory 'update.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json) + "`n", [Text.UTF8Encoding]::new($false))

Write-Output "Release tag: $tag"
Write-Output "Attach both files: $asset and $manifestPath"
Write-Output "App update URL: $updateUrl"
if ($mirrorUpdateUrl) { Write-Output "App mirror update URL: $mirrorUpdateUrl" }
