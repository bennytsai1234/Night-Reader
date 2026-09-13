[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [ValidateSet('journey', 'monkey', 'continuous')]
    [string]$Scenario = 'journey',

    [ValidateSet('debug', 'profile')]
    [string]$BuildMode = 'debug',

    [string]$FixtureHostPath,

    [string]$FixtureDevicePath = '/sdcard/Android/data/com.inkpage.reader.debug/files/NightReader/西游记.txt',

    [int]$Seed = 48291723,

    [ValidateRange(0, 100000)]
    [int]$Iterations = 120,

    [ValidateRange(0, 86400)]
    [int]$DurationSeconds = 0,

    [ValidateSet('', 'slow_read_forward', 'small_correction', 'fling_forward_then_reverse', 'fling_reverse_then_continue', 'next_or_previous_chapter', 'chapter_switch_while_ballistic', 'directory_jump_then_immediate_read')]
    [string]$Action = '',

    [string]$ReportDir,

    [int]$BuildNumber = 3000,

    [ValidateRange(30, 86400)]
    [int]$TimeoutSeconds = 900,

    [ValidateRange(30, 900)]
    [int]$SampleIntervalSeconds = 900
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageName = 'com.inkpage.reader.debug'
$activityName = "$packageName/com.inkpage.reader.MainActivity"
$normalApkPath = Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-debug.apk'
$workloadApkPath = Join-Path $repoRoot "build/app/outputs/flutter-apk/app-$BuildMode.apk"
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
$testTarget = switch ($Scenario) {
    'journey' { 'integration_test/reader_journey_test.dart' }
    'monkey' { 'integration_test/reader_monkey_test.dart' }
    'continuous' { 'integration_test/reader_continuous_test.dart' }
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

function Get-WorkloadLogcat {
    # Poll only the Flutter workload markers and crash-relevant tags.  The
    # complete logcat is still saved at the end and on failure, but repeatedly
    # transferring the emulator's system log would make a multi-hour run
    # unnecessarily expensive and can hide the workload's own progress.
    $output = Invoke-Captured 'adb' @(
        '-s', $DeviceId, 'logcat', '-d', '-v', 'brief', '-s',
        'flutter:I',
        'AndroidRuntime:E',
        'ActivityManager:E',
        'ActivityTaskManager:E',
        'libc:E',
        'DEBUG:E',
        'audio_service:D',
        'AudioService:D',
        'GoogleTTSServiceImpl:D',
        'NightReader:D'
    )
    return ($output -join [Environment]::NewLine)
}

function Get-WorkloadProgress([string]$Log) {
    $completed = $null
    $actionMatches = [regex]::Matches(
        $Log,
        'READER_(MONKEY|CONTINUOUS)_ACTION seed=\d+ #(\d+) [^\r\n]+'
    )
    if ($actionMatches.Count -gt 0) {
        $lastActionNumber = [int]$actionMatches[$actionMatches.Count - 1].Groups[2].Value
        $completed = $lastActionNumber + 1
    }

    $resultMatch = [regex]::Match(
        $Log,
        'READER_(MONKEY|CONTINUOUS)_RESULT[^\r\n]*\bcompleted=(\d+)'
    )
    if ($resultMatch.Success) {
        $completed = [int]$resultMatch.Groups[2].Value
    }

    $lastActions = @($actionMatches |
        Select-Object -Last 20 |
        ForEach-Object { $_.Value.Trim() })
    $telemetryHeartbeat = $null
    $heartbeatMatches = [regex]::Matches(
        $Log,
        '(?m)ReaderV2 telemetry heartbeat:\s*(\{.*\})\s*$'
    )
    if ($heartbeatMatches.Count -gt 0) {
        $heartbeatJson = $heartbeatMatches[$heartbeatMatches.Count - 1].Groups[1].Value
        try {
            $telemetryHeartbeat = $heartbeatJson | ConvertFrom-Json
        }
        catch {
            Write-Warning "解析 telemetry heartbeat 失敗：$($_.Exception.Message)"
        }
    }

    $performance = $null
    $performanceMatch = [regex]::Match(
        $Log,
        'READER_CONTINUOUS_PERFORMANCE\s+status=(passed|failed)\s+targetP99Micros=([0-9.]+)\s+actualP99Micros=([0-9.]+)\s+frames=(\d+)\s+taskP99Micros=([0-9.]+)\s+worstTaskMicros=([0-9.]+)\s+worstTaskChars=(\d+)\s+tasksOver8ms=(\d+)\s+vsyncP99=([0-9.]+)\s+buildP99=([0-9.]+)\s+rasterP99=([0-9.]+)'
    )
    if ($performanceMatch.Success) {
        $performance = [ordered]@{
            status = $performanceMatch.Groups[1].Value
            targetP99Micros = [double]$performanceMatch.Groups[2].Value
            actualP99Micros = [double]$performanceMatch.Groups[3].Value
            frames = [int]$performanceMatch.Groups[4].Value
            taskP99Micros = [double]$performanceMatch.Groups[5].Value
            worstTaskMicros = [double]$performanceMatch.Groups[6].Value
            worstTaskChars = [int]$performanceMatch.Groups[7].Value
            tasksOver8ms = [int]$performanceMatch.Groups[8].Value
            vsyncP99Micros = [double]$performanceMatch.Groups[9].Value
            buildP99Micros = [double]$performanceMatch.Groups[10].Value
            rasterP99Micros = [double]$performanceMatch.Groups[11].Value
        }
    }

    return [ordered]@{
        completedActions = $completed
        lastActions = $lastActions
        telemetryHeartbeat = $telemetryHeartbeat
        performance = $performance
    }
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

function Capture-PerformanceSnapshot([string]$Name, [int]$ElapsedSeconds = 0, [string]$WorkloadLog = '') {
    $meminfoPath = $null
    $gfxinfoPath = $null
    $pssKb = $null
    $rssKb = $null
    $nativeHeapKb = $null
    $dalvikHeapKb = $null

    try {
        $meminfo = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'meminfo', $packageName)
        $meminfoText = $meminfo -join [Environment]::NewLine
        $meminfoPath = Write-ReportFile "meminfo-$Name.txt" $meminfoText
        $totalMatch = [regex]::Match(
            $meminfoText,
            '(?m)^\s*TOTAL PSS:\s*(\d+)\s+TOTAL RSS:\s*(\d+)'
        )
        if ($totalMatch.Success) {
            $pssKb = [long]$totalMatch.Groups[1].Value
            $rssKb = [long]$totalMatch.Groups[2].Value
        }
        $nativeMatch = [regex]::Match(
            $meminfoText,
            '(?m)^\s*Native Heap\s+(\d+)\s+'
        )
        if ($nativeMatch.Success) {
            $nativeHeapKb = [long]$nativeMatch.Groups[1].Value
        }
        $dalvikMatch = [regex]::Match(
            $meminfoText,
            '(?m)^\s*Dalvik Heap\s+(\d+)\s+'
        )
        if ($dalvikMatch.Success) {
            $dalvikHeapKb = [long]$dalvikMatch.Groups[1].Value
        }
    }
    catch {
        Write-Warning "保存 meminfo-$Name.txt 失敗：$($_.Exception.Message)"
    }

    try {
        $gfxinfo = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'gfxinfo', $packageName)
        $gfxinfoPath = Write-ReportFile "gfxinfo-$Name.txt" (
            $gfxinfo -join [Environment]::NewLine
        )
    }
    catch {
        Write-Warning "保存 gfxinfo-$Name.txt 失敗：$($_.Exception.Message)"
    }

    $progress = Get-WorkloadProgress $WorkloadLog
    $sample = [ordered]@{
        snapshot = $Name
        capturedAt = (Get-Date).ToString('o')
        elapsedSeconds = $ElapsedSeconds
        memory = [ordered]@{
            pssKb = $pssKb
            rssKb = $rssKb
            nativeHeapKb = $nativeHeapKb
            dalvikHeapKb = $dalvikHeapKb
            dartHeapKb = $null
            dartHeapNote = '未使用 VM service；adb dumpsys meminfo 未提供 Dart heap。'
        }
        meminfoPath = $meminfoPath
        gfxinfoPath = $gfxinfoPath
        actionsCompleted = $progress.completedActions
        lastActions = $progress.lastActions
        telemetryHeartbeat = $progress.telemetryHeartbeat
    }
    $sample | ConvertTo-Json -Compress -Depth 8 |
        Add-Content -LiteralPath $samplesPath -Encoding utf8
    Write-Host (
        "sample={0} elapsed={1}s pssKb={2} rssKb={3} actions={4}" -f
        $Name, $ElapsedSeconds, $pssKb, $rssKb, $progress.completedActions
    )
    return $sample
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
        $restoreSucceeded = Test-Path -LiteralPath $normalApkPath
    }
    catch {
        Write-Warning "一般 debug APK 重建失敗，改用 workload 前 backup：$($_.Exception.Message)"
    }

    if (-not $restoreSucceeded) {
        if (-not (Test-Path -LiteralPath $backupApkPath)) {
            throw '一般 debug APK 重建失敗，且沒有 workload 前 backup 可恢復。'
        }
        Copy-Item -LiteralPath $backupApkPath -Destination $normalApkPath -Force
    }

    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'install', '-r', '-d', $normalApkPath) | ForEach-Object { Write-Host $_ }
    Invoke-Adb @('-s', $DeviceId, 'logcat', '-c') | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'start', '-W', '-n', $activityName) | ForEach-Object { Write-Host $_ }
    Wait-ForNormalReady
    Write-Host '一般 debug APK 已恢復，Ready log 已確認。'
}

Assert-Command 'adb'
Assert-Command 'flutter'

New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$samplesPath = Join-Path $reportDir 'samples.jsonl'
New-Item -ItemType File -Path $samplesPath -Force | Out-Null
$continuousSamplesPath = if ($Scenario -eq 'continuous') {
    Join-Path $reportDir 'continuous-samples.jsonl'
}
else {
    $null
}
if ($null -ne $continuousSamplesPath) {
    New-Item -ItemType File -Path $continuousSamplesPath -Force | Out-Null
}
$effectiveTimeoutSeconds = $TimeoutSeconds
if ($DurationSeconds -gt 0) {
    $effectiveTimeoutSeconds = [Math]::Max(
        $TimeoutSeconds,
        $DurationSeconds + 300
    )
}
if ($effectiveTimeoutSeconds -gt 86400) {
    throw "workload timeout $effectiveTimeoutSeconds 秒超過 runner 上限 86400 秒。"
}
$fixture = Resolve-Path -LiteralPath $fixtureHostPath -ErrorAction Stop
if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) {
    throw "找不到 fixture：$fixtureHostPath"
}

$startedAt = Get-Date
$effectiveBuildNumber = $null
$testApkInstalled = $false
$testError = $null
$restoreError = $null
$workloadStartedAt = $null
$workloadFinishedAt = $null
$sampleCount = 0
$lastWorkloadLog = ''

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

    # The NightReader_120Hz emulator is a userdebug image; root adb lets
    # the deterministic fixture be owned by the debug package UID, matching
    # Android's app-specific external-files view instead of shell's view.
    Invoke-Captured 'adb' @('-s', $DeviceId, 'root') | ForEach-Object { Write-Host $_ }
    Start-Sleep -Milliseconds 1000

    # Clear before pushing: pm clear also removes the app-specific external
    # directory used as the deterministic fixture destination.
    Write-Host '清除 app data（在 fixture push 前）。'
    $installedPackagePath = & adb -s $DeviceId shell pm path $packageName 2>$null
    $packageInstalled = $LASTEXITCODE -eq 0 -and ($installedPackagePath -match '^package:')
    if ($packageInstalled) {
        Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
        Invoke-Adb @('-s', $DeviceId, 'shell', 'pm', 'clear', $packageName) |
            ForEach-Object { Write-Host $_ }
    }
    else {
        Write-Host "尚未安裝 $packageName，略過 pm clear；稍後先安裝一般 debug APK。"
    }

    # Let the installed app create its package-owned external directory before
    # adb pushes the fixture.  On some API 37 emulator images a shell-created
    # Android/data subtree is visible to `adb shell ls` but filtered from the
    # app's dart:io File.exists until the app has initialized its own path.
    if (Test-Path -LiteralPath $normalApkPath) {
        Write-Host '啟動一般 debug APK 建立 app-specific external directory。'
        Invoke-Adb @('-s', $DeviceId, 'install', '-r', '-d', $normalApkPath) |
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

    if (Test-Path -LiteralPath $normalApkPath) {
        Copy-Item -LiteralPath $normalApkPath -Destination $backupApkPath -Force
    }

    Write-Host "建置 Android integration workload：$testTarget"
    Push-Location $repoRoot
    try {
        $buildArguments = @(
            'build', 'apk', "--$BuildMode", "--target=$testTarget",
            "--build-number=$effectiveBuildNumber",
            "--dart-define=NIGHT_READER_FIXTURE_PATH=$FixtureDevicePath",
            "--dart-define=NIGHT_READER_FIXTURE_HOST_PATH=$fixtureHostPath"
        )
        if ($Scenario -eq 'monkey') {
            $buildArguments += "--dart-define=NIGHT_READER_MONKEY_SEED=$Seed"
            $buildArguments += "--dart-define=NIGHT_READER_MONKEY_ITERATIONS=$Iterations"
            $buildArguments += "--dart-define=NIGHT_READER_MONKEY_DURATION_SECONDS=$DurationSeconds"
        }
        if ($Scenario -eq 'continuous') {
            $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_SEED=$Seed"
            $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_ITERATIONS=$Iterations"
            $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_DURATION_SECONDS=$DurationSeconds"
            if (-not [string]::IsNullOrWhiteSpace($Action)) {
                $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_ACTION=$Action"
            }
        }
        Invoke-Captured 'flutter' $buildArguments | ForEach-Object { Write-Host $_ }
    }
    finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $workloadApkPath)) {
        throw "找不到 integration workload APK：$workloadApkPath"
    }

    Write-Host '清除 app data 並安裝 workload APK。'
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
    Invoke-Adb @('-s', $DeviceId, 'install', '-r', '-d', $workloadApkPath) | ForEach-Object { Write-Host $_ }
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
    $workloadStartedAt = Get-Date
    $startLog = Get-WorkloadLogcat
    $lastWorkloadLog = $startLog
    $startSample = Capture-PerformanceSnapshot `
        -Name 'sample-000-start' `
        -ElapsedSeconds 0 `
        -WorkloadLog $startLog
    if ($null -ne $startSample) { $sampleCount += 1 }

    $deadline = $workloadStartedAt.AddSeconds($effectiveTimeoutSeconds)
    $nextSampleAt = $workloadStartedAt.AddSeconds($SampleIntervalSeconds)
    $passed = $false
    $failure = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 1000
        $now = Get-Date
        $log = Get-WorkloadLogcat
        $lastWorkloadLog = $log
        if ($now -ge $nextSampleAt) {
            $elapsedSeconds = [int]([Math]::Floor(($now - $workloadStartedAt).TotalSeconds))
            $sampleName = 'sample-{0:D3}-{1}s' -f $sampleCount, $elapsedSeconds
            $sample = Capture-PerformanceSnapshot `
                -Name $sampleName `
                -ElapsedSeconds $elapsedSeconds `
                -WorkloadLog $log
            if ($null -ne $sample) { $sampleCount += 1 }
            $nextSampleAt = $now.AddSeconds($SampleIntervalSeconds)
        }
        if ($log -match 'READER_(E2E|MONKEY|CONTINUOUS)_RESULT status=passed') {
            $passed = $true
            break
        }
        if ($log -match 'READER_(E2E|MONKEY|CONTINUOUS)_(FAILURE|ANOMALY)|Some tests failed|FATAL EXCEPTION|ANR in|SIGSEGV|SIGABRT|Null check operator used on a null value|Unhandled exception') {
            $failure = ($log -split "`r?`n" | Where-Object {
                $_ -match 'READER_(E2E|MONKEY|CONTINUOUS)_(FAILURE|ANOMALY)|Some tests failed|FATAL EXCEPTION|ANR in|SIGSEGV|SIGABRT|Null check operator used on a null value|Unhandled exception'
            } | Select-Object -Last 1)
            break
        }
        if ($null -eq (Get-AndroidPid)) {
            $failure = 'workload process 在回報結果前消失。'
            break
        }
    }

    $workloadFinishedAt = Get-Date
    $finalLog = Get-Logcat
    Write-ReportFile 'workload-logcat.txt' $finalLog | Out-Null
    $finalFilteredLog = Get-WorkloadLogcat
    $lastWorkloadLog = $finalFilteredLog
    if ($null -ne $continuousSamplesPath) {
        $sampleLines = @(
            $finalFilteredLog -split "`r?`n" | ForEach-Object {
                $sampleMatch = [regex]::Match(
                    [string]$_,
                    'READER_CONTINUOUS_SAMPLE\s+(\{.*\})'
                )
                if ($sampleMatch.Success) {
                    $sampleMatch.Groups[1].Value
                }
            }
        )
        if ($sampleLines.Count -gt 0) {
            Set-Content -LiteralPath $continuousSamplesPath `
                -Value $sampleLines -Encoding utf8
        }
    }
    $endElapsedSeconds = [int]([Math]::Floor(($workloadFinishedAt - $workloadStartedAt).TotalSeconds))
    $endSample = Capture-PerformanceSnapshot `
        -Name 'end' `
        -ElapsedSeconds $endElapsedSeconds `
        -WorkloadLog $finalFilteredLog
    if ($null -ne $endSample) { $sampleCount += 1 }
    if (-not $passed) {
        if ($null -eq $failure) {
            $failure = "在 $effectiveTimeoutSeconds 秒內沒有看到 workload passed marker。"
        }
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
    $workloadProgress = Get-WorkloadProgress $lastWorkloadLog
    $workloadEndAt = if ($null -ne $workloadFinishedAt) {
        $workloadFinishedAt
    }
    elseif ($null -ne $workloadStartedAt) {
        $finishedAt
    }
    else {
        $null
    }
    $metadata = [ordered]@{
        scenario = $Scenario
        seed = $Seed
        requestedIterations = $Iterations
        requestedDurationSeconds = $DurationSeconds
        sampleIntervalSeconds = $SampleIntervalSeconds
        effectiveTimeoutSeconds = $effectiveTimeoutSeconds
        fixtureHostPath = $fixtureHostPath
        fixtureDevicePath = $FixtureDevicePath
        fixtureBytes = if ($null -ne $fixtureSize) { $fixtureSize } else { $null }
        avdDeviceId = $DeviceId
        buildMode = $BuildMode
        package = $packageName
        activity = $activityName
        apkPath = $workloadApkPath
        normalApkPath = $normalApkPath
        startedAt = $startedAt.ToString('o')
        finishedAt = $finishedAt.ToString('o')
        actualDurationSeconds = ($finishedAt - $startedAt).TotalSeconds
        workloadStartedAt = if ($null -ne $workloadStartedAt) {
            $workloadStartedAt.ToString('o')
        }
        else {
            $null
        }
        workloadFinishedAt = if ($null -ne $workloadEndAt) {
            $workloadEndAt.ToString('o')
        }
        else {
            $null
        }
        workloadDurationSeconds = if ($null -ne $workloadStartedAt -and $null -ne $workloadEndAt) {
            ($workloadEndAt - $workloadStartedAt).TotalSeconds
        }
        else {
            $null
        }
        sampleCount = $sampleCount
        samplesPath = $samplesPath
        continuousSamplesPath = $continuousSamplesPath
        completedActions = $workloadProgress.completedActions
        lastActions = $workloadProgress.lastActions
        performance = $workloadProgress.performance
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
