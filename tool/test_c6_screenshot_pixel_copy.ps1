[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$subsetPath = Join-Path $repoRoot 'integration_test/reader_correctness_android_subset_test.dart'
$runnerPath = Join-Path $repoRoot 'tool/run_android_reader_workload.ps1'

if (-not (Test-Path -LiteralPath $subsetPath -PathType Leaf)) {
    throw "找不到 C6 Android subset test：$subsetPath"
}
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "找不到 Android workload runner：$runnerPath"
}

$subset = Get-Content -Raw -LiteralPath $subsetPath
$runner = Get-Content -Raw -LiteralPath $runnerPath

# The golden checkpoint is required evidence.  It must convert the Flutter
# surface, pump before capture, and write the returned bytes only after the
# capture succeeds.  This deliberately does not permit an adb screencap or a
# post-detection image to stand in for the app-owned golden.
$goldenContract = [regex]::Match(
    $subset,
    '(?s)if \(_captureGolden.*?await binding\.convertFlutterSurfaceToImage\(\);.*?await tester\.pump\(\);.*?final screenshotBytes = await binding\.takeScreenshot\(name\);.*?await evidenceWriter\.writeGoldenPng\(item, name, screenshotBytes\);'
)
if (-not $goldenContract.Success) {
    throw 'C6 golden contract changed: surface conversion, pump, takeScreenshot, and writeGoldenPng must remain ordered.'
}

# A capture exception must remain in the case failure path.  The normal case
# result marker is later in the same try body, while the catch branch rethrows
# after writing fail-closed evidence; this prevents an ordinary PixelCopy
# failure from being converted to a passed case.
$goldenStart = $subset.IndexOf('if (_captureGolden && _shouldCaptureGolden(item))', [StringComparison]::Ordinal)
$caseResult = $subset.IndexOf("debugPrint('READER_C6_CASE_RESULT", [StringComparison]::Ordinal)
$caseCatch = $subset.IndexOf(
    '        } catch (error, stackTrace) {',
    [StringComparison]::Ordinal
)
$rethrow = $subset.IndexOf('          rethrow;', [StringComparison]::Ordinal)
if ($goldenStart -lt 0 -or $caseResult -lt 0 -or $rethrow -lt 0 -or
    $caseCatch -lt 0 -or $goldenStart -ge $caseCatch -or
    $caseResult -ge $caseCatch -or $rethrow -le $caseCatch) {
    throw 'C6 failure contract changed: golden capture must be inside the case try and the enclosing catch must rethrow.'
}

# The runner may enable or disable golden capture only through the explicit
# switch/define.  It must not add a correctness-path screencap fallback.
if ($runner -notmatch '\[switch\]\$CaptureGolden' -or
    $runner -notmatch 'NIGHT_READER_C6_CAPTURE_GOLDEN=') {
    throw 'C6 runner no longer exposes the explicit CaptureGolden contract.'
}
$exportStart = $runner.IndexOf('function Export-C6EvidenceBundles', [StringComparison]::Ordinal)
$failureStart = $runner.IndexOf('function Capture-FailureArtifacts', [StringComparison]::Ordinal)
$readyStart = $runner.IndexOf('function Wait-ForNormalReady', [StringComparison]::Ordinal)
if ($exportStart -lt 0 -or $failureStart -le $exportStart -or
    $readyStart -le $failureStart) {
    throw 'C6 runner function boundaries changed; cannot prove screenshot evidence ownership.'
}
$exportSource = $runner.Substring($exportStart, $failureStart - $exportStart)
$failureSource = $runner.Substring($failureStart, $readyStart - $failureStart)
if ($exportSource -match '(?im)adb[^\r\n]*screencap') {
    throw 'C6 evidence exporter contains an adb screencap fallback; required PixelCopy evidence must not be substituted.'
}
if ($failureSource -notmatch '(?im)adb[^\r\n]*screencap' -or
    $failureSource -notmatch 'supplementalScreenshot') {
    throw 'C6 post-detection supplemental screenshot ownership changed unexpectedly.'
}

# Pin the Flutter implementation used by this workspace.  Flutter 3.47's
# integration_test Android implementation maps captureView to PixelCopy and
# reports PixelCopy result 2 as ERROR_TIMEOUT.  This test is source-contract
# only; it does not modify the SDK or treat result 2 as pass.
$flutterCommand = Get-Command flutter -ErrorAction Stop
$flutterSdk = Split-Path (Split-Path $flutterCommand.Source)
$flutterScreenshotPath = Join-Path $flutterSdk 'packages/integration_test/android/src/main/java/dev/flutter/plugins/integration_test/FlutterDeviceScreenshot.java'
if (-not (Test-Path -LiteralPath $flutterScreenshotPath -PathType Leaf)) {
    throw "找不到 Flutter integration_test screenshot implementation：$flutterScreenshotPath"
}
$flutterScreenshot = Get-Content -Raw -LiteralPath $flutterScreenshotPath
foreach ($required in @(
        'PixelCopy.request(',
        'flutterActivity.getWindow()',
        'copyResult == PixelCopy.SUCCESS',
        'result.error("Could not copy the pixels", "result was " + copyResult, null)')) {
    if ($flutterScreenshot.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "Flutter PixelCopy contract changed; missing: $required"
    }
}

Write-Output 'C6 screenshot PixelCopy source-contract tests passed:'
Write-Output '  golden surface conversion -> pump -> takeScreenshot -> app-owned write ordering is preserved.'
Write-Output '  capture failure remains fail-closed and cannot emit a passed case marker.'
Write-Output '  adb screencap remains confined to post-detection supplemental context, never the C6 evidence exporter.'
Write-Output '  Flutter integration_test captureView still uses Window PixelCopy and reports copy errors.'
