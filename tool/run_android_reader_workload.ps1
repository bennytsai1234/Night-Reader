[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [ValidateSet('journey', 'monkey')]
    [string]$Scenario = 'journey',

    [string]$FixtureHostPath,

    [string]$FixtureDevicePath = '/sdcard/Android/data/com.inkpage.reader.debug/files/NightReader/西游记.txt',

    [int]$Seed = 48291723,

    [ValidateRange(0, 100000)]
    [int]$Iterations = 120,

    [ValidateRange(0, 86400)]
    [int]$DurationSeconds = 0,

    [string]$ReportDir,

    [int]$BuildNumber = 3000,

    [ValidateRange(30, 3600)]
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageName = 'com.inkpage.reader.debug'
$activityName = "$packageName/com.inkpage.reader.MainActivity"
$apkPath = Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-debug.apk'
$fixtureHostPath = if ([string]::IsNullOrWhiteSpace($FixtureHostPath)) {
    Join-Path $repoRoot 'samples/西游记.txt'
}
else {
    $FixtureHostPath
}
$reportDir = if ([string]::IsNullOrWhiteSpace($ReportDir)) {
    Join-Path $repoRoot (Join-Path 'artifacts/android-reader' (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
else {
    $ReportDir
}
$testTarget = if ($Scenario -eq 'journey') {
    'integration_test/reader_journey_test.dart'
}
else {
    'integration_test/reader_monkey_test.dart'
}
$backupApkPath = Join-Path ([System.IO.Path]::GetTempPath()) (
    "night-reader-debug-before-reader-workload-{0}.apk" -f [Guid]::NewGuid()
)

function Assert-Command([string]$Name) {
    if ($null -eq (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "找不到命令 $Name，請先把 Flutter 與 Android Platform Tools 加入 PATH。"
    }
}

function Invoke-Captured([string]$FilePath, [string[]]$Arguments) {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # adb push and Flutter frequently write progress/warnings to stderr
        # even when the process exits successfully.  Do not let PowerShell's
        # Stop policy turn those native stderr records into false failures.
        $ErrorActionPreference = 'Continue'
        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "$FilePath $($Arguments -join ' ') 失敗，exit code=$exitCode：$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Invoke-Adb([string[]]$Arguments) {
    return Invoke-Captured 'adb' $Arguments
}

function Get-AndroidPid {
    $output = & adb -s $DeviceId shell pidof -s $packageName 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    foreach ($line in @($output)) {
        if ([string]$line -match '^(\d+)$') {
            return [int]$Matches[1]
        }
    }
    return $null
}

function Get-Logcat {
    $output = Invoke-Captured 'adb' @('-s', $DeviceId, 'logcat', '-d', '-v', 'brief')
    return ($output -join [Environment]::NewLine)
}

function Get-InstalledVersionCode {
    $dump = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'package', $packageName)
    foreach ($line in $dump) {
        if ([string]$line -match '\bversionCode=(\d+)') {
            return [int]$Matches[1]
        }
    }
    return 0
}

function Set-AppExternalFixtureOwnership([string]$DirectoryPath) {
    $dump = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'package', $packageName)
    $appUid = $null
    foreach ($line in $dump) {
        if ([string]$line -match '\bappId=(\d+)') {
            $appUid = $Matches[1]
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($appUid)) {
        throw "找不到 $packageName 的 appId，無法準備 app-specific fixture。"
    }
    $owner = '{0}:{0}' -f $appUid
    Invoke-Adb @('-s', $DeviceId, 'shell', 'chown', '-R', $owner, $DirectoryPath) |
        ForEach-Object { Write-Host $_ }
    Write-Host "fixture ownership=$owner path=$DirectoryPath"
}

function Write-ReportFile([string]$Name, [string]$Content) {
    $path = Join-Path $reportDir $Name
    Set-Content -LiteralPath $path -Value $Content -Encoding utf8
    return $path
}

function Capture-PerformanceSnapshot([string]$Name) {
    try {
        $meminfo = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'meminfo', $packageName)
        Write-ReportFile "meminfo-$Name.txt" ($meminfo -join [Environment]::NewLine) | Out-Null
    }
    catch {
        Write-Warning "保存 meminfo-$Name.txt 失敗：$($_.Exception.Message)"
    }

    try {
        $gfxinfo = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'gfxinfo', $packageName)
        Write-ReportFile "gfxinfo-$Name.txt" ($gfxinfo -join [Environment]::NewLine) | Out-Null
    }
    catch {
        Write-Warning "保存 gfxinfo-$Name.txt 失敗：$($_.Exception.Message)"
    }
}

function Capture-FailureArtifacts {
    try {
        $log = Get-Logcat
        Write-ReportFile 'failure-logcat.txt' $log | Out-Null
    }
    catch {
        Write-Warning "保存 failure logcat 失敗：$($_.Exception.Message)"
    }

    $remoteScreenshot = '/sdcard/NightReader-reader-workload-failure.png'
    try {
        Invoke-Adb @('-s', $DeviceId, 'shell', 'screencap', '-p', $remoteScreenshot) | Out-Null
        Invoke-Adb @('-s', $DeviceId, 'pull', $remoteScreenshot, $reportDir) | Out-Null
        Invoke-Adb @('-s', $DeviceId, 'shell', 'rm', '-f', $remoteScreenshot) | Out-Null
    }
    catch {
        Write-Warning "保存 failure screenshot 失敗：$($_.Exception.Message)"
    }
}

function Wait-ForNormalReady([int]$WaitSeconds = 45) {
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $log = Get-Logcat
        if ($log -match '夜讀 Ready to Run') { return }
        Start-Sleep -Milliseconds 500
    }
    throw "一般 debug APK 在 $WaitSeconds 秒內沒有出現『夜讀 Ready to Run』。"
}

function Restore-NormalApk([int]$EffectiveBuildNumber) {
    Write-Host '恢復一般 debug APK...'
    $restoreSucceeded = $false
    try {
        Push-Location $repoRoot
        try {
            Invoke-Captured 'flutter' @('build', 'apk', '--debug', "--build-number=$EffectiveBuildNumber") | ForEach-Object { Write-Host $_ }
        }
        finally {
            Pop-Location
        }
        $restoreSucceeded = Test-Path -LiteralPath $apkPath
    }
    catch {
        Write-Warning "一般 debug APK 重建失敗，改用 workload 前 backup：$($_.Exception.Message)"
    }

    if (-not $restoreSucceeded) {
        if (-not (Test-Path -LiteralPath $backupApkPath)) {
            throw '一般 debug APK 重建失敗，且沒有 workload 前 backup 可恢復。'
        }
        Copy-Item -LiteralPath $backupApkPath -Destination $apkPath -Force
    }

    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'install', '-r', $apkPath) | ForEach-Object { Write-Host $_ }
    Invoke-Adb @('-s', $DeviceId, 'logcat', '-c') | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'start', '-W', '-n', $activityName) | ForEach-Object { Write-Host $_ }
    Wait-ForNormalReady
    Write-Host '一般 debug APK 已恢復，Ready log 已確認。'
}

Assert-Command 'adb'
Assert-Command 'flutter'

New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$fixture = Resolve-Path -LiteralPath $fixtureHostPath -ErrorAction Stop
if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) {
    throw "找不到 fixture：$fixtureHostPath"
}

$startedAt = Get-Date
$effectiveBuildNumber = $null
$testApkInstalled = $false
$testError = $null
$restoreError = $null

try {
    $emulators = Invoke-Captured 'flutter' @('emulators')
    $devices = Invoke-Captured 'adb' @('devices', '-l')
    $flutterDevices = Invoke-Captured 'flutter' @('devices')
    Write-ReportFile 'environment.txt' (
        "flutter emulators`n$($emulators -join [Environment]::NewLine)`n`n" +
        "adb devices -l`n$($devices -join [Environment]::NewLine)`n`n" +
        "flutter devices`n$($flutterDevices -join [Environment]::NewLine)"
    ) | Out-Null

    $state = Invoke-Adb @('-s', $DeviceId, 'get-state')
    if (($state -join "`n") -notmatch '(?m)^\s*device\s*$') {
        throw "裝置 $DeviceId 沒有以 device 狀態連線。"
    }

    # The fixed NightReader_API37 emulator is a userdebug image; root adb lets
    # the deterministic fixture be owned by the debug package UID, matching
    # Android's app-specific external-files view instead of shell's view.
    Invoke-Captured 'adb' @('-s', $DeviceId, 'root') | ForEach-Object { Write-Host $_ }
    Start-Sleep -Milliseconds 1000

    # Clear before pushing: pm clear also removes the app-specific external
    # directory used as the deterministic fixture destination.
    Write-Host '清除 app data（在 fixture push 前）。'
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'shell', 'pm', 'clear', $packageName) | ForEach-Object { Write-Host $_ }

    # Let the installed app create its package-owned external directory before
    # adb pushes the fixture.  On some API 37 emulator images a shell-created
    # Android/data subtree is visible to `adb shell ls` but filtered from the
    # app's dart:io File.exists until the app has initialized its own path.
    if (Test-Path -LiteralPath $apkPath) {
        Write-Host '啟動一般 debug APK 建立 app-specific external directory。'
        Invoke-Adb @('-s', $DeviceId, 'install', '-r', $apkPath) |
            ForEach-Object { Write-Host $_ }
        Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'start', '-W', '-n', $activityName) |
            ForEach-Object { Write-Host $_ }
        Start-Sleep -Milliseconds 1500
        Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
    }

    Write-Host "推送 fixture：$fixtureHostPath -> $FixtureDevicePath"
    $fixtureDirectory = $FixtureDevicePath.Substring(0, $FixtureDevicePath.LastIndexOf('/'))
    Invoke-Adb @('-s', $DeviceId, 'shell', 'mkdir', '-p', $fixtureDirectory) | Out-Null
    Invoke-Captured 'adb' @('-s', $DeviceId, 'push', $fixture.Path, $FixtureDevicePath) | ForEach-Object { Write-Host $_ }
    $fixtureSize = (Get-Item -LiteralPath $fixture.Path).Length
    Set-AppExternalFixtureOwnership $fixtureDirectory

    $installedBuildNumber = Get-InstalledVersionCode
    $effectiveBuildNumber = [Math]::Max($BuildNumber, $installedBuildNumber + 1)
    Write-Host "使用 Android versionCode=$effectiveBuildNumber。"

    if (Test-Path -LiteralPath $apkPath) {
        Copy-Item -LiteralPath $apkPath -Destination $backupApkPath -Force
    }

    Write-Host "建置 Android integration workload：$testTarget"
    Push-Location $repoRoot
    try {
        $buildArguments = @(
            'build', 'apk', '--debug', "--target=$testTarget",
            "--build-number=$effectiveBuildNumber",
            "--dart-define=NIGHT_READER_FIXTURE_PATH=$FixtureDevicePath",
            "--dart-define=NIGHT_READER_FIXTURE_HOST_PATH=$fixtureHostPath"
        )
        if ($Scenario -eq 'monkey') {
            $buildArguments += "--dart-define=NIGHT_READER_MONKEY_SEED=$Seed"
            $buildArguments += "--dart-define=NIGHT_READER_MONKEY_ITERATIONS=$Iterations"
            $buildArguments += "--dart-define=NIGHT_READER_MONKEY_DURATION_SECONDS=$DurationSeconds"
        }
        Invoke-Captured 'flutter' $buildArguments | ForEach-Object { Write-Host $_ }
    }
    finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "找不到 integration workload APK：$apkPath"
    }

    Write-Host '清除 app data 並安裝 workload APK。'
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'install', '-r', $apkPath) | ForEach-Object { Write-Host $_ }
    $testApkInstalled = $true
    # TTS uses audio_service's Android notification channel on API 33+.
    # Grant the declared runtime notification permission before the workload
    # starts so a system permission dialog cannot steal the test surface during
    # the seeded monkey actions.  Older images simply reject this grant.
    try {
        Invoke-Adb @(
            '-s', $DeviceId, 'shell', 'pm', 'grant', $packageName,
            'android.permission.POST_NOTIFICATIONS'
        ) | ForEach-Object { Write-Host $_ }
    }
    catch {
        Write-Warning "POST_NOTIFICATIONS grant skipped：$($_.Exception.Message)"
    }
    # Some emulator/package-manager combinations remove the app-specific
    # external directory during an APK update.  Push again after install so
    # the workload always starts with the declared deterministic fixture.
    Write-Host "再次推送 fixture（workload APK 安裝後）：$FixtureDevicePath"
    Invoke-Adb @('-s', $DeviceId, 'shell', 'mkdir', '-p', $fixtureDirectory) | Out-Null
    Invoke-Captured 'adb' @('-s', $DeviceId, 'push', $fixture.Path, $FixtureDevicePath) |
        ForEach-Object { Write-Host $_ }
    Set-AppExternalFixtureOwnership $fixtureDirectory
    Invoke-Adb @('-s', $DeviceId, 'logcat', '-c') | Out-Null
    Invoke-Adb @(
        '-s', $DeviceId, 'shell', 'am', 'start', '-W', '-n', $activityName,
        '--ez', 'test-flag', 'true',
        '--ez', 'disable-service-auth-codes', 'true',
        '--ez', 'disable-service-origin-check', 'true'
    ) | ForEach-Object { Write-Host $_ }

    $processId = $null
    $processDeadline = (Get-Date).AddSeconds(30)
    while ($null -eq $processId -and (Get-Date) -lt $processDeadline) {
        $processId = Get-AndroidPid
        if ($null -eq $processId) { Start-Sleep -Milliseconds 250 }
    }
    if ($null -eq $processId) { throw 'workload APK 啟動後沒有取得 process PID。' }
    Write-Host "workload process PID=$processId。"
    Capture-PerformanceSnapshot 'start'

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $middleCaptured = $false
    $middleDeadline = if ($DurationSeconds -gt 0) {
        (Get-Date).AddSeconds([Math]::Max(1, [Math]::Floor($DurationSeconds / 2)))
    }
    else {
        $null
    }
    $passed = $false
    $failure = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 1000
        if (-not $middleCaptured -and $null -ne $middleDeadline -and (Get-Date) -ge $middleDeadline) {
            Capture-PerformanceSnapshot 'middle'
            $middleCaptured = $true
        }
        $log = Get-Logcat
        if ($log -match 'READER_(E2E|MONKEY)_RESULT status=passed') {
            $passed = $true
            break
        }
        if ($log -match 'READER_(E2E|MONKEY)_FAILURE|Some tests failed|FATAL EXCEPTION|ANR in|SIGSEGV|SIGABRT|Null check operator used on a null value|Unhandled exception') {
            $failure = ($log -split "`r?`n" | Where-Object {
                $_ -match 'READER_(E2E|MONKEY)_FAILURE|Some tests failed|FATAL EXCEPTION|ANR in|SIGSEGV|SIGABRT|Null check operator used on a null value|Unhandled exception'
            } | Select-Object -Last 1)
            break
        }
        if ($null -eq (Get-AndroidPid)) {
            $failure = 'workload process 在回報結果前消失。'
            break
        }
    }

    $finalLog = Get-Logcat
    Write-ReportFile 'workload-logcat.txt' $finalLog | Out-Null
    Capture-PerformanceSnapshot 'end'
    if (-not $passed) {
        if ($null -eq $failure) { $failure = "在 $TimeoutSeconds 秒內沒有看到 workload passed marker。" }
        throw "Android $Scenario workload 失敗：$failure"
    }
    Write-Host "Android $Scenario workload 通過。"
}
catch {
    $testError = $_
    Capture-FailureArtifacts
}
finally {
    $finishedAt = Get-Date
    $metadata = [ordered]@{
        scenario = $Scenario
        seed = $Seed
        requestedIterations = $Iterations
        requestedDurationSeconds = $DurationSeconds
        fixtureHostPath = $fixtureHostPath
        fixtureDevicePath = $FixtureDevicePath
        fixtureBytes = if ($null -ne $fixtureSize) { $fixtureSize } else { $null }
        avdDeviceId = $DeviceId
        package = $packageName
        activity = $activityName
        apkPath = $apkPath
        startedAt = $startedAt.ToString('o')
        finishedAt = $finishedAt.ToString('o')
        actualDurationSeconds = ($finishedAt - $startedAt).TotalSeconds
        effectiveBuildNumber = $effectiveBuildNumber
        testError = if ($null -ne $testError) { $testError.ToString() } else { $null }
        restoreError = $null
    }

    if ($testApkInstalled) {
        try {
            Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
            Restore-NormalApk -EffectiveBuildNumber $effectiveBuildNumber
        }
        catch {
            $restoreError = $_
            Write-Warning "恢復一般 debug APK 失敗：$($_.Exception.Message)"
        }
    }

    $metadata.restoreError = if ($null -ne $restoreError) { $restoreError.ToString() } else { $null }
    $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportDir 'metadata.json') -Encoding utf8
    Remove-Item -LiteralPath $backupApkPath -Force -ErrorAction SilentlyContinue
}

if ($null -ne $testError) { Write-Error $testError }
if ($null -ne $restoreError) { Write-Error "恢復一般 debug APK 失敗：$restoreError" }
if ($null -ne $testError -and $null -ne $restoreError) { exit 3 }
if ($null -ne $restoreError) { exit 2 }
if ($null -ne $testError) { exit 1 }
exit 0
