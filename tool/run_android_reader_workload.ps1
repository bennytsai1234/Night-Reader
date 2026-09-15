[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [ValidateSet('journey', 'monkey', 'continuous', 'fixture-decode', 'visual-oracle', 'correctness-subset')]
    [string]$Scenario = 'journey',

    [ValidateSet('debug', 'profile')]
    [string]$BuildMode = 'debug',

    [string]$FixtureHostPath,

    [string]$FixtureDevicePath = '/sdcard/Android/data/com.inkpage.reader.debug/files/NightReader/reader_correctness_book.txt',

    [int]$Seed = 48291723,

    [ValidateRange(0, 100000)]
    [int]$Iterations = 120,

    [ValidateRange(0, 86400)]
    [int]$DurationSeconds = 0,

    # Action remains a pass-through for the legacy continuous route.  The
    # correctness-subset route never parses it; it accepts a case id or a
    # manifest and lets the shared Dart model restore the operation sequence.
    [string]$Action = '',

    [string]$CaseId = '',

    [string]$CaseList = '',

    [string]$ManifestHostPath = '',

    [string]$HostFailureCaseList = '',

    [switch]$CaptureGolden,

    [switch]$CaptureFailureScreenshots,

    [switch]$EnableInvariantHook,

    [switch]$SimpleScrollControl,

    [switch]$CaptureSettledScreenshots,

    [string]$ReportDir,

    [int]$BuildNumber = 3000,

    [ValidateRange(30, 3600)]
    [int]$TimeoutSeconds = 900,

    [string]$DriverResponsePathOverride,

    [ValidateRange(5, 900)]
    [int]$SampleIntervalSeconds = 30
)

$ErrorActionPreference = 'Stop'

$c6EvidenceModulePath = Join-Path $PSScriptRoot 'c6_evidence_bundle.psm1'
if (-not (Test-Path -LiteralPath $c6EvidenceModulePath -PathType Leaf)) {
    throw "找不到 C6 evidence bundle module：$c6EvidenceModulePath"
}
Import-Module -Name $c6EvidenceModulePath -Force

if ($Scenario -eq 'continuous') {
    if ($Iterations -gt 60) {
        throw 'continuous runner 每批最多 60 iterations；請拆成有限短批次。'
    }
    if ($DurationSeconds -gt 300) {
        throw 'continuous runner 每批最多 300 秒；禁止 7200 秒或兩小時級單次長跑。'
    }
}
if ($Scenario -eq 'visual-oracle') {
    if ($BuildMode -ne 'debug') {
        throw 'visual-oracle 必須使用 debug build；RepaintBoundary visual oracle 是 debug-only，且不作 profile 效能判定。'
    }
    if ($DurationSeconds -gt 0) {
        throw 'visual-oracle 使用固定有限 case，不接受 duration soak；不要啟動長時間或無限長跑。'
    }
    if ($TimeoutSeconds -gt 300) {
        throw 'visual-oracle 每批最多 300 秒；禁止 7200 秒或兩小時級單次長跑。'
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageName = 'com.inkpage.reader.debug'
$activityName = "$packageName/com.inkpage.reader.MainActivity"
$normalApkPath = Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-debug.apk'
$workloadApkPath = Join-Path $repoRoot "build/app/outputs/flutter-apk/app-$BuildMode.apk"
$fixtureHostPath = if ([string]::IsNullOrWhiteSpace($FixtureHostPath)) {
    Join-Path $repoRoot 'test/fixtures/reader_correctness_book.txt'
}
else {
    $FixtureHostPath
}
$fixtureDirectory = $FixtureDevicePath.Substring(0, $FixtureDevicePath.LastIndexOf('/'))
$c6ManifestDevicePath = "$fixtureDirectory/c6-manifest.json"
$c6HostFailureDevicePath = "$fixtureDirectory/c6-host-failures.json"
$c6EvidenceDevicePath = "$fixtureDirectory/c6-evidence"
$c6ManifestHostPath = if ([string]::IsNullOrWhiteSpace($ManifestHostPath)) {
    Join-Path $repoRoot ("docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-{0}.json" -f $Seed)
}
else {
    $ManifestHostPath
}
if ($Scenario -eq 'correctness-subset') {
    if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds')) {
        $TimeoutSeconds = 300
    }
    if ($BuildMode -ne 'debug') {
        throw 'correctness-subset 必須使用 debug build；C2/C3/C4 hook 與 bounded golden 只作真實性觀察，不作 profile 效能判定。'
    }
    if ($DurationSeconds -gt 0) {
        throw 'correctness-subset 不接受 duration soak；請用有限 CaseList 並由批次腳本拆分。'
    }
    if ($TimeoutSeconds -gt 300) {
        throw 'correctness-subset 每批最多 300 秒；禁止 7200 秒或兩小時級單次長跑。'
    }
    if (-not [string]::IsNullOrWhiteSpace($CaseId) -and
        -not [string]::IsNullOrWhiteSpace($CaseList)) {
        throw 'correctness-subset 的 -CaseId 與 -CaseList 只能擇一。'
    }
    if ([string]::IsNullOrWhiteSpace($CaseId) -and
        [string]::IsNullOrWhiteSpace($CaseList)) {
        throw 'correctness-subset 必須提供 -CaseId 或 -CaseList。'
    }
    if (-not [string]::IsNullOrWhiteSpace($CaseId) -and
        -not (Test-Path -LiteralPath $c6ManifestHostPath -PathType Leaf)) {
        throw "找不到 C6 manifest：$c6ManifestHostPath"
    }
    if (-not [string]::IsNullOrWhiteSpace($CaseList) -and
        -not (Test-Path -LiteralPath $CaseList -PathType Leaf)) {
        throw "找不到 C6 CaseList：$CaseList"
    }
    if (-not [string]::IsNullOrWhiteSpace($HostFailureCaseList) -and
        -not (Test-Path -LiteralPath $HostFailureCaseList -PathType Leaf)) {
        throw "找不到 host failure case list：$HostFailureCaseList"
    }
}
$reportDir = if ([string]::IsNullOrWhiteSpace($ReportDir)) {
    Join-Path $repoRoot (Join-Path 'artifacts/android-reader' (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
else {
    $ReportDir
}
$screenshotDir = Join-Path $reportDir 'checkpoints'
$systemHealthPath = Join-Path $reportDir 'system-health.json'
$script:systemHealthPath = $systemHealthPath
$script:systemHealthBaseline = $null
$script:systemHealthInitial = $null
$script:systemHealthRecent = [System.Collections.Generic.List[object]]::new()
$script:systemHealthFirstFailureObservation = $null
$script:systemHealthObservationCount = 0
$script:systemHealthForegroundState = [ordered]@{
    lastReaderForeground = $null
    lastObservationAt = $null
    notReaderSince = $null
    transitionCount = 0
}
$script:failureClassification = $null
$previousScreenshotDirectory = $env:NIGHT_READER_SCREENSHOT_DIR
$testTarget = switch ($Scenario) {
    'journey' { 'integration_test/reader_journey_test.dart' }
    'monkey' { 'integration_test/reader_monkey_test.dart' }
    'continuous' { 'integration_test/reader_continuous_test.dart' }
    'fixture-decode' { 'integration_test/reader_correctness_fixture_test.dart' }
    'visual-oracle' { 'integration_test/reader_correctness_visual_oracle_test.dart' }
    'correctness-subset' { 'integration_test/reader_correctness_android_subset_test.dart' }
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

function Get-EffectiveAdbTimeoutSeconds([double]$RequestedTimeoutSeconds) {
    $timeoutSeconds = [Math]::Max(0.05, $RequestedTimeoutSeconds)
    $supervisorDeadline = $script:DriverSupervisorDeadline
    if ($null -ne $supervisorDeadline) {
        $remainingSeconds = ($supervisorDeadline - (Get-Date)).TotalSeconds
        if ($remainingSeconds -le 0) {
            throw 'driver supervisor deadline reached before bounded ADB probe.'
        }
        $timeoutSeconds = [Math]::Min($timeoutSeconds, [Math]::Max(0.05, $remainingSeconds))
    }
    return $timeoutSeconds
}

function Invoke-Adb([string[]]$Arguments, [double]$TimeoutSeconds = 30) {
    return Invoke-AdbBounded $Arguments (Get-EffectiveAdbTimeoutSeconds $TimeoutSeconds)
}

function Invoke-AdbBoundedResult([string[]]$Arguments, [double]$TimeoutSeconds = 180) {
    # Package-manager stalls happen before the workload process exists, so the
    # workload watchdog cannot observe them. Keep install/start preparation
    # finite as well; this is separate from the workload timeout.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'adb'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($argument in $Arguments) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        try {
            [void]$process.Start()
        }
        catch {
            return [pscustomobject]@{
                timedOut = $false
                cleanupTimedOut = $false
                exitCode = $null
                stdout = ''
                stderr = ''
                startError = $_.Exception.ToString()
            }
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit([int][Math]::Ceiling($TimeoutSeconds * 1000))) {
            try { $process.Kill($true) } catch {
                try { $process.Kill() } catch { }
            }
            $cleanupCompleted = $process.WaitForExit(3000)
            return [pscustomobject]@{
                timedOut = $true
                cleanupTimedOut = -not $cleanupCompleted
                exitCode = $null
                stdout = ''
                stderr = 'bounded timeout; process terminated'
                startError = $null
            }
        }
        if (-not $stdoutTask.Wait(3000) -or -not $stderrTask.Wait(3000)) {
            return [pscustomobject]@{
                timedOut = $true
                cleanupTimedOut = $true
                exitCode = $null
                stdout = ''
                stderr = 'bounded ADB output cleanup timeout'
                startError = $null
            }
        }
        return [pscustomobject]@{
            timedOut = $false
            cleanupTimedOut = $false
            exitCode = $process.ExitCode
            stdout = $stdoutTask.GetAwaiter().GetResult()
            stderr = $stderrTask.GetAwaiter().GetResult()
            startError = $null
        }
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-AdbBounded([string[]]$Arguments, [double]$TimeoutSeconds = 180) {
    $effectiveTimeoutSeconds = Get-EffectiveAdbTimeoutSeconds $TimeoutSeconds
    $result = Invoke-AdbBoundedResult $Arguments $effectiveTimeoutSeconds
    if ($null -ne $result.startError) {
        throw "adb $($Arguments -join ' ') 啟動失敗：$($result.startError)"
    }
    if ($result.timedOut) {
        $cleanupSuffix = if ($result.cleanupTimedOut) {
            '；bounded cleanup also timed out'
        }
        else { '' }
        throw "adb $($Arguments -join ' ') 超過 bounded timeout ${effectiveTimeoutSeconds}s$cleanupSuffix。"
    }
    $stdout = [string]$result.stdout
    $stderr = [string]$result.stderr
    $output = @($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($result.exitCode -ne 0) {
        throw "adb $($Arguments -join ' ') 失敗，exit code=$($result.exitCode)：$($output -join [Environment]::NewLine)"
    }
    return @($output -split "`r?`n" | Where-Object { $_ -ne '' })
}

function Copy-C6RemoteFileViaStaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteFile,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [int]$TimeoutSeconds = 5
    )

    if ([string]::IsNullOrWhiteSpace($RemoteFile)) {
        throw 'C6 remote file path is empty'
    }
    if (Test-Path -LiteralPath $DestinationPath -PathType Container) {
        throw "C6 local destination is a directory, not a file: $DestinationPath"
    }
    # adb appends the remote leaf to a directory destination.  Keep that
    # destination independent from the report root: a descriptive C6 report
    # path can reach the Windows MAX_PATH boundary before adb creates the
    # staged PNG and reports the misleading "Not a directory" error.
    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'night-reader-c6-pull-{0}' -f [Guid]::NewGuid().ToString('N')
    )
    $stagingDirectory = Join-Path $stagingRoot 'payload'
    try {
        New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
        Invoke-AdbBounded @(
            '-s', $DeviceId, 'pull', $RemoteFile, $stagingDirectory
        ) $TimeoutSeconds | ForEach-Object { Write-Host $_ }
        $remoteLeaf = (($RemoteFile.TrimEnd('/', '\')) -split '[/\\]')[-1]
        if ([string]::IsNullOrWhiteSpace($remoteLeaf)) {
            throw "C6 remote file has no leaf name: $RemoteFile"
        }
        $stagedFiles = @(
            Get-ChildItem -LiteralPath $stagingDirectory -Recurse -File `
                -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ceq $remoteLeaf }
        )
        if ($stagedFiles.Count -ne 1) {
            throw "adb pull must produce exactly one staged leaf ($remoteLeaf); observed $($stagedFiles.Count)"
        }
        $destinationParent = Split-Path -Parent $DestinationPath
        if ([string]::IsNullOrWhiteSpace($destinationParent)) {
            throw "C6 local destination has no parent directory: $DestinationPath"
        }
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        Copy-Item -LiteralPath $stagedFiles[0].FullName -Destination $DestinationPath -Force
        if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
            throw "transport copy completed but destination file is missing: $DestinationPath"
        }
        return $DestinationPath
    }
    finally {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-AndroidPid {
    $effectiveTimeoutSeconds = Get-EffectiveAdbTimeoutSeconds 10
    $result = Invoke-AdbBoundedResult @(
        '-s', $DeviceId, 'shell', 'pidof', '-s', $packageName
    ) $effectiveTimeoutSeconds
    if ($null -ne $result.startError) {
        throw "adb pidof 啟動失敗：$($result.startError)"
    }
    if ($result.timedOut) {
        throw "adb pidof 超過 bounded timeout ${effectiveTimeoutSeconds}s；process presence unknown。"
    }
    $stdout = [string]$result.stdout
    $stderr = [string]$result.stderr
    if ($result.exitCode -ne 0) {
        # pidof uses exit 1 with no output for a cleanly absent process. Any
        # stderr or other output is a transport/ADB failure and must not be
        # collapsed into the same absent state.
        if ($result.exitCode -eq 1 -and
            [string]::IsNullOrWhiteSpace($stdout) -and
            [string]::IsNullOrWhiteSpace($stderr)) {
            return $null
        }
        throw "adb pidof 失敗，exit code=$($result.exitCode)：$($stdout)`n$stderr；process presence unknown。"
    }
    foreach ($line in @($stdout -split "`r?`n")) {
        if ([string]$line -match '^(\d+)$') {
            return [int]$Matches[1]
        }
    }
    throw "adb pidof 回傳成功但沒有有效 numeric PID；process presence unknown。"
}

function Get-Logcat {
    $output = Invoke-AdbBounded @(
        '-s', $DeviceId, 'logcat', '-d', '-v', 'brief'
    ) (Get-EffectiveAdbTimeoutSeconds 30)
    return ($output -join [Environment]::NewLine)
}

function Get-WorkloadLogcat {
    # Poll only the Flutter workload markers and crash-relevant tags.  The
    # complete logcat is still saved at the end and on failure, but repeatedly
    # transferring the emulator's system log would make a multi-hour run
    # unnecessarily expensive and can hide the workload's own progress.
    $output = Invoke-AdbBounded @(
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
    ) (Get-EffectiveAdbTimeoutSeconds 10)
    return ($output -join [Environment]::NewLine)
}

function Get-SystemHealthField([string]$Text, [string[]]$Patterns) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    foreach ($pattern in $Patterns) {
        $match = [regex]::Match(
            $Text,
            $pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($match.Success) {
            if ($match.Groups['value'].Success) {
                return $match.Groups['value'].Value.Trim()
            }
            return $match.Value.Trim()
        }
    }
    return $null
}

function Get-SystemHealthPid([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    $match = [regex]::Match($Text, '(?<!\d)(\d+)(?!\d)')
    if ($match.Success) {
        return [int]$match.Groups[1].Value
    }
    return $null
}

function Get-SystemHealthLineTimestamp([string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }
    $match = [regex]::Match($Line, '^\s*(?<value>\d+(?:\.\d+)?)\s+')
    if ($match.Success) {
        return [double]$match.Groups['value'].Value
    }
    return $null
}

function Get-SystemHealthLineIdentity([string]$Line) {
    $normalized = ([string]$Line).Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return ''
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Invoke-SystemHealthAdbCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [double]$TimeoutSeconds,
        [switch]$AllowCleanAbsent
    )

    $result = $null
    try {
        $effectiveTimeoutSeconds = Get-EffectiveAdbTimeoutSeconds $TimeoutSeconds
        $result = Invoke-AdbBoundedResult $Arguments $effectiveTimeoutSeconds
    }
    catch {
        return [ordered]@{
            success = $false
            optionalAbsent = $false
            text = ''
            stdout = ''
            stderr = ''
            exitCode = $null
            timedOut = $false
            startError = $_.Exception.ToString()
            error = $_.Exception.ToString()
        }
    }

    $stdout = [string]$result.stdout
    $stderr = [string]$result.stderr
    $output = @($stdout, $stderr) | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }
    $text = $output -join [Environment]::NewLine
    if ($null -ne $result.startError) {
        return [ordered]@{
            success = $false
            optionalAbsent = $false
            text = $text
            stdout = $stdout
            stderr = $stderr
            exitCode = $result.exitCode
            timedOut = [bool]$result.timedOut
            startError = [string]$result.startError
            error = "ADB start failed: $($result.startError)"
        }
    }
    if ([bool]$result.timedOut) {
        return [ordered]@{
            success = $false
            optionalAbsent = $false
            text = $text
            stdout = $stdout
            stderr = $stderr
            exitCode = $result.exitCode
            timedOut = $true
            startError = $null
            error = 'ADB bounded timeout'
        }
    }
    if ($null -ne $result.exitCode -and [int]$result.exitCode -ne 0) {
        if ($AllowCleanAbsent -and
            [int]$result.exitCode -eq 1 -and
            [string]::IsNullOrWhiteSpace($stdout) -and
            [string]::IsNullOrWhiteSpace($stderr)) {
            return [ordered]@{
                success = $true
                optionalAbsent = $true
                text = ''
                stdout = ''
                stderr = ''
                exitCode = $result.exitCode
                timedOut = $false
                startError = $null
                error = $null
            }
        }
        return [ordered]@{
            success = $false
            optionalAbsent = $false
            text = $text
            stdout = $stdout
            stderr = $stderr
            exitCode = $result.exitCode
            timedOut = $false
            startError = $null
            error = "ADB exit code $($result.exitCode): $text"
        }
    }
    return [ordered]@{
        success = $true
        optionalAbsent = $false
        text = $text
        stdout = $stdout
        stderr = $stderr
        exitCode = $result.exitCode
        timedOut = $false
        startError = $null
        error = $null
    }
}

function Get-SystemHealthLogSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [double]$TimeoutSeconds
    )

    $command = Invoke-SystemHealthAdbCommand -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
    $records = [System.Collections.Generic.List[object]]::new()
    if ($command.success) {
        foreach ($line in @($command.text -split '\r?\n')) {
            if ([string]::IsNullOrWhiteSpace([string]$line)) {
                continue
            }
            $lineText = ([string]$line).Trim()
            $records.Add([ordered]@{
                    timestamp = Get-SystemHealthLineTimestamp $lineText
                    identity = Get-SystemHealthLineIdentity $lineText
                    text = $lineText
                })
        }
    }
    $maxTimestamp = $null
    foreach ($record in $records) {
        if ($null -ne $record.timestamp -and
            ($null -eq $maxTimestamp -or $record.timestamp -gt $maxTimestamp)) {
            $maxTimestamp = [double]$record.timestamp
        }
    }
    return [ordered]@{
        name = $Name
        success = [bool]$command.success
        error = $command.error
        timedOut = [bool]$command.timedOut
        lineCount = $records.Count
        timestampedLineCount = @($records | Where-Object { $null -ne $_.timestamp }).Count
        maxTimestamp = $maxTimestamp
        records = @($records.ToArray())
    }
}

function Get-SystemHealthNewLines {
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot,
        [Parameter(Mandatory = $true)]
        $BaselineBuffer
    )

    $baselineIdentities = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($identity in @($BaselineBuffer.lineIdentities)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$identity)) {
            [void]$baselineIdentities.Add([string]$identity)
        }
    }
    $baselineMaxTimestamp = $BaselineBuffer.maxTimestamp
    $newRecords = [System.Collections.Generic.List[object]]::new()
    $uncertainLines = [System.Collections.Generic.List[string]]::new()
    foreach ($record in @($Snapshot.records)) {
        $isNew = $false
        $isUncertain = $false
        if ($null -ne $record.timestamp -and $null -ne $baselineMaxTimestamp) {
            if ([double]$record.timestamp -gt [double]$baselineMaxTimestamp) {
                $isNew = $true
            }
            elseif ([double]$record.timestamp -eq [double]$baselineMaxTimestamp -and
                -not $baselineIdentities.Contains([string]$record.identity)) {
                $isNew = $true
            }
        }
        elseif (-not $baselineIdentities.Contains([string]$record.identity)) {
            # The runner requests epoch timestamps, but retain a bounded
            # fingerprint-only fallback for images that omit them.  It is
            # explicitly marked uncertain so an ANR match cannot be healthy.
            $isNew = $true
            $isUncertain = $true
        }
        if ($isNew) {
            $newRecords.Add($record)
            if ($isUncertain) {
                $uncertainLines.Add([string]$record.text)
            }
        }
    }
    return [ordered]@{
        records = @($newRecords.ToArray())
        uncertainLines = @($uncertainLines.ToArray())
        precision = if ($uncertainLines.Count -gt 0) {
            'bounded-fingerprint-only'
        }
        else {
            'bounded-timestamp-and-fingerprint'
        }
    }
}

function Parse-SystemHealthObservation {
    [CmdletBinding()]
    param(
        [string]$Source = 'system-health',
        [string]$DeviceId = $script:DeviceId,
        [string]$PackageName = $script:packageName,
        [string]$Timestamp = '',
        [string]$AdbState = '',
        [string]$BootCompleted = '',
        [string]$SystemServerPidText = '',
        [string]$SystemUiPidText = '',
        [string]$SystemUiPidStatus = 'available',
        [string]$WindowDump = '',
        [string]$ActivityDump = '',
        [string]$LogcatText = '',
        [object[]]$AnrSources = @(),
        [string[]]$ProbeErrors = @(),
        [object[]]$ProbeCommandErrors = @(),
        [string]$BaselineMode = '',
        [string]$BaselineCapturedAt = '',
        [string[]]$BaselineLimitations = @(),
        $NewLinesByBuffer = $null
    )

    if ([string]::IsNullOrWhiteSpace($Timestamp)) {
        $Timestamp = (Get-Date).ToString('o')
    }
    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($probeError in @($ProbeErrors)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$probeError)) {
            $errors.Add([string]$probeError)
        }
    }
    if ([string]::IsNullOrWhiteSpace($BaselineMode)) {
        $errors.Add('workload-start ANR baseline/cursor is missing; system health cannot be classified safely')
    }
    $adbStateValue = ([string]$AdbState).Trim()
    if ($adbStateValue -notmatch '(?i)^device$') {
        $errors.Add("adb state is not device: '$adbStateValue'")
    }
    $bootValue = ([string]$BootCompleted).Trim()
    if ($bootValue -notmatch '(?i)^(1|true)$') {
        $errors.Add("sys.boot_completed is not complete: '$bootValue'")
    }
    $systemServerPid = Get-SystemHealthPid $SystemServerPidText
    if ($null -eq $systemServerPid) {
        $errors.Add('system_server PID is missing')
    }
    $systemUiPid = Get-SystemHealthPid $SystemUiPidText
    if ($null -eq $systemUiPid) {
        if ($SystemUiPidStatus -ne 'error') {
            $SystemUiPidStatus = 'optional/unavailable'
            $warnings.Add('com.android.systemui PID is optional/unavailable')
        }
    }
    if ($SystemUiPidStatus -eq 'available' -and $null -eq $systemUiPid) {
        $SystemUiPidStatus = 'optional/unavailable'
    }

    $focusedWindow = Get-SystemHealthField $WindowDump @(
        '(?m)^\s*mCurrentFocus\s*=\s*(?<value>.+?)\s*$',
        '(?m)^\s*mCurrentFocus\s*:\s*(?<value>.+?)\s*$',
        '(?m)^\s*mFocusedWindow\s*=\s*(?<value>.+?)\s*$'
    )
    $currentWindow = Get-SystemHealthField $WindowDump @(
        '(?m)^\s*mCurrentFocus\s*=\s*(?<value>.+?)\s*$',
        '(?m)^\s*mCurrentFocus\s*:\s*(?<value>.+?)\s*$',
        '(?m)^\s*mFocusedWindow\s*=\s*(?<value>.+?)\s*$',
        '(?m)^\s*mFocusedApp\s*=\s*(?<value>.+?)\s*$'
    )
    $resumedActivity = Get-SystemHealthField $ActivityDump @(
        '(?m)^\s*mResumedActivity\s*[:=]\s*(?<value>.+?)\s*$',
        '(?m)^\s*ResumedActivity\s*[:=]\s*(?<value>.+?)\s*$',
        '(?m)^\s*topResumedActivity\s*[:=]\s*(?<value>.+?)\s*$'
    )
    $topActivity = Get-SystemHealthField $ActivityDump @(
        '(?m)^\s*topResumedActivity\s*[:=]\s*(?<value>.+?)\s*$',
        '(?m)^\s*mFocusedApp\s*=\s*(?<value>.+?)\s*$',
        '(?m)^\s*mResumedActivity\s*[:=]\s*(?<value>.+?)\s*$'
    )
    if ([string]::IsNullOrWhiteSpace($topActivity)) {
        $topActivity = Get-SystemHealthField $WindowDump @(
            '(?m)^\s*mFocusedApp\s*=\s*(?<value>.+?)\s*$'
        )
    }
    if ([string]::IsNullOrWhiteSpace($focusedWindow)) {
        $warnings.Add('focused/current window was unavailable in dumpsys window output')
    }
    if ([string]::IsNullOrWhiteSpace($resumedActivity)) {
        $warnings.Add('resumed/top activity was unavailable in dumpsys activity output')
    }

    $foregroundText = @(
        $focusedWindow,
        $currentWindow,
        $resumedActivity,
        $topActivity
    ) -join [Environment]::NewLine
    $readerForeground = $null
    if (-not [string]::IsNullOrWhiteSpace($foregroundText)) {
        if ($foregroundText.IndexOf($PackageName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $readerForeground = $true
        }
        elseif ($foregroundText -match '(?i)com\.android\.systemui|system_server') {
            $readerForeground = $false
        }
    }
    $systemUiForeground = $foregroundText -match '(?i)com\.android\.systemui'

    $dialogPattern = "(?i)(?:Process\s+System\s+is(?:n['’]t| not)\s+responding|System\s+is(?:n['’]t| not)\s+responding|Application\s+Not\s+Responding)"
    $normalizedAnrSources = [System.Collections.Generic.List[object]]::new()
    foreach ($sourceEntry in @($AnrSources)) {
        if ($null -eq $sourceEntry) { continue }
        $entrySource = [string]$sourceEntry.source
        $entryText = [string]$sourceEntry.text
        if (-not [string]::IsNullOrWhiteSpace($entryText)) {
            $normalizedAnrSources.Add([ordered]@{ source = $entrySource; text = $entryText })
        }
    }
    if ($normalizedAnrSources.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($LogcatText)) {
        $normalizedAnrSources.Add([ordered]@{ source = 'logcat'; text = $LogcatText })
    }
    if (-not [string]::IsNullOrWhiteSpace($WindowDump)) {
        $normalizedAnrSources.Add([ordered]@{ source = 'window'; text = $WindowDump })
    }
    if (-not [string]::IsNullOrWhiteSpace($ActivityDump)) {
        $normalizedAnrSources.Add([ordered]@{ source = 'activity'; text = $ActivityDump })
    }

    $anrObservations = [System.Collections.Generic.List[object]]::new()
    $escapedPackageName = [regex]::Escape($PackageName)
    foreach ($sourceEntry in @($normalizedAnrSources.ToArray())) {
        foreach ($line in @(([string]$sourceEntry.text) -split '\r?\n')) {
            if ([string]::IsNullOrWhiteSpace([string]$line)) { continue }
            $lineText = ([string]$line).Trim()
            $lineAnrMatch = [regex]::Match(
                $lineText,
                '(?i)\bANR\s+in\s+(?<target>[A-Za-z0-9._/{}-]+)'
            )
            $isAmAnr = $lineText -match '(?i)\bam_anr\b'
            $dialogMatches = [regex]::Matches($lineText, $dialogPattern)
            $dialogTargetMatch = [regex]::Match(
                $lineText,
                '(?i)Application\s+Not\s+Responding\s*:\s*(?<target>[A-Za-z0-9._/-]+)'
            )
            $windowOwnerAnr = $lineText -match '(?i)(?:AppNotRespondingDialog|AnrDialog|ApplicationErrorReport\$AnrInfo|ANR\s+dialog|application[_\s-]*not[_\s-]*responding)'
            if (-not $lineAnrMatch.Success -and -not $isAmAnr -and
                $dialogMatches.Count -eq 0 -and -not $windowOwnerAnr) {
                continue
            }

            $target = $null
            $classification = 'unknown'
            $kind = 'unknown-anr'
            $targetText = if ($lineAnrMatch.Success) {
                $lineAnrMatch.Groups['target'].Value
            }
            else {
                ''
            }
            $amAnrTargetMatch = [regex]::Match(
                $lineText,
                "(?i)\bam_anr\b[^\r\n]*?(?<target>system_server|com\.android\.systemui|systemui|$escapedPackageName|system)(?=[,\s\]\):]|$)"
            )
            $amAnrTargetText = if ($amAnrTargetMatch.Success) {
                $amAnrTargetMatch.Groups['target'].Value
            }
            else {
                ''
            }
            $amAnrSystem = $isAmAnr -and (
                $amAnrTargetText -match '(?i)^system_server$|^system$'
            )
            $amAnrSystemUi = $isAmAnr -and (
                $amAnrTargetText -match '(?i)^systemui$|^com\.android\.systemui$'
            )
            $amAnrReader = $isAmAnr -and (
                $amAnrTargetText -match "(?i)^$escapedPackageName$"
            )
            if ($targetText -match '(?i)^system_server$|^system$' -or $amAnrSystem) {
                $target = if ([string]::IsNullOrWhiteSpace($targetText)) {
                    $amAnrTargetText
                }
                else {
                    $targetText
                }
                $classification = 'system'
                $kind = if ($lineAnrMatch.Success) { 'anr-in' } else { 'am_anr' }
            }
            elseif ($targetText -match '(?i)systemui|com\.android\.systemui' -or $amAnrSystemUi) {
                $target = if ([string]::IsNullOrWhiteSpace($targetText)) {
                    $amAnrTargetText
                }
                else {
                    $targetText
                }
                $classification = 'systemui'
                $kind = if ($lineAnrMatch.Success) { 'anr-in' } else { 'am_anr' }
            }
            elseif ($targetText -match "(?i)^$escapedPackageName$" -or
                $amAnrReader -or
                $lineText -match "(?i)\bam_anr\b.*$escapedPackageName") {
                $target = if ([string]::IsNullOrWhiteSpace($targetText)) {
                    $PackageName
                }
                else {
                    $targetText
                }
                $classification = 'reader/app'
                $kind = if ($lineAnrMatch.Success) { 'anr-in' } else { 'am_anr' }
            }
            elseif ($isAmAnr -or $lineAnrMatch.Success) {
                $target = $targetText
                $classification = 'unknown'
                $kind = if ($isAmAnr) { 'am_anr' } else { 'anr-in' }
            }
            elseif ($dialogMatches.Count -gt 0 -or $windowOwnerAnr) {
                $kind = if ($dialogMatches.Count -gt 0) { 'dialog' } else { 'window-owner' }
                if ($lineText -match "(?i)$escapedPackageName") {
                    $target = $PackageName
                    $classification = 'reader/app'
                }
                elseif ($lineText -match '(?i)systemui|com\.android\.systemui') {
                    $target = 'com.android.systemui'
                    $classification = 'systemui'
                }
                elseif ($lineText -match "(?i)Process\s+System|Application\s+Not\s+Responding\s*:\s*(?:system_server|system)\b|System\s+is(?:n['’]t| not)\s+responding") {
                    $target = 'system'
                    $classification = 'system'
                }
                elseif ($dialogTargetMatch.Success) {
                    # A dialog can belong to any package while Reader remains the
                    # foreground activity. Preserve that explicit owner instead of
                    # attributing it to Reader via the foreground fallback.
                    $target = $dialogTargetMatch.Groups['target'].Value
                    $classification = 'unknown'
                }
                elseif ($foregroundText -match "(?i)$escapedPackageName") {
                    $target = $PackageName
                    $classification = 'reader/app'
                }
                elseif ($foregroundText -match '(?i)systemui|system_server') {
                    $target = 'systemui'
                    $classification = 'systemui'
                }
            }
            $anrObservations.Add([ordered]@{
                    source = [string]$sourceEntry.source
                    kind = $kind
                    target = $target
                    classification = $classification
                    text = $lineText
                })
        }
    }

    $anrRecords = @($anrObservations.ToArray())
    $systemAnrObservations = @(
        $anrRecords | Where-Object { [string]$_.classification -ceq 'system' }
    )
    $systemUiAnrObservations = @(
        $anrRecords | Where-Object { [string]$_.classification -ceq 'systemui' }
    )
    $readerAnrObservations = @(
        $anrRecords | Where-Object { [string]$_.classification -ceq 'reader/app' }
    )
    $unknownAnrObservations = @(
        $anrRecords | Where-Object { [string]$_.classification -ceq 'unknown' }
    )
    $dialogTextMatches = @(
        $anrRecords | Where-Object {
            [string]$_.kind -ceq 'dialog' -and
            ([string]$_.text -match $dialogPattern)
        }
    )
    $systemAnrDialogMatches = @(
        $anrRecords | Where-Object {
            [string]$_.classification -in @('system', 'systemui') -and
            [string]$_.kind -in @('dialog', 'window-owner')
        }
    )
    $uncertainLogLineCount = 0
    $uncertainAnrLineCount = 0
    if ($null -ne $NewLinesByBuffer) {
        foreach ($bufferName in @($NewLinesByBuffer.Keys)) {
            $buffer = $NewLinesByBuffer[$bufferName]
            $uncertainLogLineCount += @($buffer.uncertainLines).Count
            $uncertainAnrLineCount += @(
                $buffer.uncertainLines | Where-Object {
                    [string]$_ -match '(?i)\bam_anr\b|\bANR\s+in\b|Application\s+Not\s+Responding|AppNotRespondingDialog|AnrDialog'
                }
            ).Count
        }
    }
    if ($uncertainLogLineCount -gt 0) {
        $warnings.Add(
            "logcat baseline used bounded timestamp/fingerprint matching; uncertain new lines=$uncertainLogLineCount"
        )
    }
    if ($BaselineMode -ceq 'bounded-snapshot-timestamp-fingerprint') {
        $warnings.Add(
            'exact logcat cursor is unavailable; only post-baseline timestamp/fingerprint identities were considered'
        )
    }

    $failureReasons = [System.Collections.Generic.List[string]]::new()
    foreach ($error in @($errors)) {
        $failureReasons.Add([string]$error)
    }
    if ($systemAnrObservations.Count -gt 0) {
        $failureReasons.Add('system-level ANR signal observed')
    }
    if ($systemUiAnrObservations.Count -gt 0) {
        $failureReasons.Add('SystemUI-level ANR signal observed')
    }
    if ($unknownAnrObservations.Count -gt 0) {
        $failureReasons.Add('ANR signal target could not be classified safely')
    }
    if ($readerAnrObservations.Count -gt 0) {
        $failureReasons.Add('Reader workload ANR signal observed')
    }

    # Structural probe errors and system/systemui ANRs are environment
    # failures.  Unknown ANRs are also non-healthy and fail closed, while a
    # Reader-only ANR remains an app/workload failure for the existing capture
    # and restore path.
    $classification = if (
        $errors.Count -gt 0 -or
        $systemAnrObservations.Count -gt 0 -or
        $systemUiAnrObservations.Count -gt 0
    ) {
        'environment_invalid'
    }
    elseif ($unknownAnrObservations.Count -gt 0 -or $uncertainAnrLineCount -gt 0) {
        'unknown_anr'
    }
    elseif ($readerAnrObservations.Count -gt 0) {
        'app_workload_failure'
    }
    else {
        'healthy'
    }
    $healthy = $classification -ceq 'healthy'
    $failureDetails = if ($healthy) {
        $null
    }
    else {
        [ordered]@{
            classification = $classification
            reasons = @($failureReasons)
            systemAnrCount = $systemAnrObservations.Count
            systemUiAnrCount = $systemUiAnrObservations.Count
            readerAnrCount = $readerAnrObservations.Count
            unknownAnrCount = $unknownAnrObservations.Count
            uncertainAnrLineCount = $uncertainAnrLineCount
            observations = @($anrRecords | Select-Object -Last 12)
        }
    }
    return [ordered]@{
        schemaVersion = 1
        probe = 'bounded-system-health'
        source = $Source
        timestamp = $Timestamp
        deviceId = $DeviceId
        adb = [ordered]@{
            state = $adbStateValue
        }
        boot = [ordered]@{
            sysBootCompleted = $bootValue
        }
        processes = [ordered]@{
            systemServerPid = $systemServerPid
            systemUiPid = $systemUiPid
            systemUiPidStatus = $SystemUiPidStatus
        }
        window = [ordered]@{
            focusedWindow = $focusedWindow
            currentWindow = $currentWindow
        }
        activity = [ordered]@{
            resumedActivity = $resumedActivity
            topActivity = $topActivity
        }
        foreground = [ordered]@{
            readerForeground = $readerForeground
            systemUiForeground = [bool]$systemUiForeground
            transition = $null
            graceSeconds = $null
            graceExceeded = $false
        }
        signals = [ordered]@{
            dialogPattern = $dialogPattern
            dialogTextMatches = @($dialogTextMatches | ForEach-Object { $_.text })
            systemAnrDialogMatches = @($systemAnrDialogMatches | ForEach-Object { $_.text })
            systemAnrDialogCount = $systemAnrDialogMatches.Count
            processSystemNotResponding = @(
                $anrRecords | Where-Object {
                    [string]$_.text -match "(?i)Process\s+System\s+is(?:n['’]t| not)\s+responding"
                } | ForEach-Object { $_.text }
            )
        }
        anr = [ordered]@{
            classifications = @(
                $anrRecords | ForEach-Object { $_.classification } | Select-Object -Unique
            )
            system = @($systemAnrObservations)
            systemui = @($systemUiAnrObservations)
            readerApp = @($readerAnrObservations)
            unknown = @($unknownAnrObservations)
            observations = @($anrRecords)
        }
        baseline = [ordered]@{
            mode = $BaselineMode
            capturedAt = $BaselineCapturedAt
            limitations = @($BaselineLimitations)
            exactCursor = $false
            uncertainNewLineCount = $uncertainLogLineCount
        }
        newLinesByBuffer = $NewLinesByBuffer
        errors = @($errors)
        warnings = @($warnings)
        commandErrors = @($ProbeCommandErrors)
        classification = $classification
        healthy = $healthy
        failureDetails = $failureDetails
    }
}

function Write-SystemHealthArtifact {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace([string]$script:systemHealthPath)) {
        return $null
    }
    $artifactDirectory = Split-Path -Parent $script:systemHealthPath
    if (-not [string]::IsNullOrWhiteSpace($artifactDirectory)) {
        New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
    }
    $recent = if ($null -ne $script:systemHealthRecent) {
        @($script:systemHealthRecent.ToArray())
    }
    else {
        @()
    }
    $latest = if ($recent.Count -gt 0) {
        $recent[$recent.Count - 1]
    }
    else {
        $null
    }
    $artifact = [ordered]@{
        schemaVersion = 1
        artifact = 'bounded-system-health-sentinel'
        deviceId = $script:DeviceId
        generatedAt = (Get-Date).ToString('o')
        observationCount = [int]$script:systemHealthObservationCount
        maxRecentObservations = 8
        baseline = $script:systemHealthBaseline
        initial = $script:systemHealthInitial
        recent = $recent
        latest = $latest
        firstFailure = $script:systemHealthFirstFailureObservation
        failureClassification = $script:failureClassification
    }
    $artifact | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $script:systemHealthPath -Encoding utf8
    return $script:systemHealthPath
}

function Record-SystemHealthObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Observation
    )

    if ($null -eq $script:systemHealthRecent) {
        $script:systemHealthRecent = [System.Collections.Generic.List[object]]::new()
    }
    if ($null -eq $script:systemHealthForegroundState) {
        $script:systemHealthForegroundState = [ordered]@{
            lastReaderForeground = $null
            lastObservationAt = $null
            notReaderSince = $null
            transitionCount = 0
        }
    }

    $previousReaderForeground = $script:systemHealthForegroundState.lastReaderForeground
    $readerForeground = $null
    $systemUiForeground = $false
    if ($null -ne $Observation.foreground) {
        $readerForeground = $Observation.foreground.readerForeground
        $systemUiForeground = [bool]$Observation.foreground.systemUiForeground
    }
    $transition = $null
    if ($null -ne $readerForeground -and
        $null -ne $previousReaderForeground -and
        [bool]$readerForeground -ne [bool]$previousReaderForeground) {
        $transition = [ordered]@{
            fromReaderForeground = [bool]$previousReaderForeground
            toReaderForeground = [bool]$readerForeground
            at = [string]$Observation.timestamp
            source = [string]$Observation.source
        }
        $script:systemHealthForegroundState.transitionCount += 1
    }
    $now = Get-Date
    if ($readerForeground -eq $true) {
        $script:systemHealthForegroundState.notReaderSince = $null
    }
    elseif ($readerForeground -eq $false -and
        $null -eq $script:systemHealthForegroundState.notReaderSince) {
        $script:systemHealthForegroundState.notReaderSince = $now
    }
    $graceSeconds = $null
    $graceExceeded = $false
    if ($null -ne $script:systemHealthForegroundState.notReaderSince) {
        $graceSeconds = [Math]::Max(
            0,
            ($now - $script:systemHealthForegroundState.notReaderSince).TotalSeconds
        )
        $graceExceeded = $graceSeconds -ge 15
    }
    $Observation['foreground'] = [ordered]@{
        readerForeground = $readerForeground
        systemUiForeground = $systemUiForeground
        transition = $transition
        transitionCount = [int]$script:systemHealthForegroundState.transitionCount
        graceLimitSeconds = 15
        graceSeconds = $graceSeconds
        graceExceeded = $graceExceeded
    }
    $script:systemHealthForegroundState.lastReaderForeground = $readerForeground
    $script:systemHealthForegroundState.lastObservationAt = [string]$Observation.timestamp

    # A transient loss of foreground is diagnostic context.  Only when the
    # same condition lasts beyond the bounded grace window is it safe to abort
    # the workload as an environment failure.
    if ($graceExceeded -and [string]$Observation.classification -ceq 'healthy') {
        $Observation.classification = 'environment_invalid'
        $Observation.healthy = $false
        $Observation.failureDetails = [ordered]@{
            classification = 'environment_invalid'
            reasons = @('Reader was not foreground for at least 15 seconds')
            systemAnrCount = @($Observation.anr.system).Count
            systemUiAnrCount = @($Observation.anr.systemui).Count
            readerAnrCount = @($Observation.anr.readerApp).Count
            unknownAnrCount = @($Observation.anr.unknown).Count
            uncertainAnrLineCount = [int]$Observation.baseline.uncertainNewLineCount
            observations = @($Observation.anr.observations | Select-Object -Last 12)
        }
    }

    $script:systemHealthObservationCount += 1
    if ($null -eq $script:systemHealthInitial) {
        $script:systemHealthInitial = $Observation
    }
    $script:systemHealthRecent.Add($Observation)
    while ($script:systemHealthRecent.Count -gt 8) {
        $script:systemHealthRecent.RemoveAt(0)
    }

    $observationClassification = [string]$Observation.classification
    if ($observationClassification -ceq 'environment_invalid') {
        $script:failureClassification = 'environment_invalid'
    }
    elseif ($observationClassification -ceq 'unknown_anr' -and
        [string]::IsNullOrWhiteSpace([string]$script:failureClassification)) {
        $script:failureClassification = 'unknown_anr'
    }
    elseif ($observationClassification -ceq 'app_workload_failure' -and
        [string]::IsNullOrWhiteSpace([string]$script:failureClassification)) {
        $script:failureClassification = 'app_workload_failure'
    }
    if ($observationClassification -cne 'healthy' -and
        $null -eq $script:systemHealthFirstFailureObservation) {
        $script:systemHealthFirstFailureObservation = $Observation
    }
    try {
        Write-SystemHealthArtifact | Out-Null
    }
    catch {
        # A missing diagnostic artifact must not turn an unsafe probe into a
        # healthy result or hide the original environment classification.
        $script:failureClassification = 'environment_invalid'
        throw "system-health artifact write failed: $($_.Exception.Message)"
    }
    return $Observation
}

function Initialize-SystemHealthBaseline {
    [CmdletBinding()]
    param(
        [string]$Source = 'workload-start',
        [string]$DeviceId = $script:DeviceId
    )

    $capturedAt = (Get-Date).ToString('o')
    $bufferSpecs = @(
        [ordered]@{
            name = 'events'
            arguments = @('-s', $DeviceId, 'logcat', '-b', 'events', '-d', '-v', 'epoch', '-t', '200')
        },
        [ordered]@{
            name = 'main'
            arguments = @('-s', $DeviceId, 'logcat', '-b', 'main', '-d', '-v', 'epoch', '-t', '200')
        },
        [ordered]@{
            name = 'system'
            arguments = @('-s', $DeviceId, 'logcat', '-b', 'system', '-d', '-v', 'epoch', '-t', '200')
        }
    )
    $buffers = [ordered]@{}
    $errors = [System.Collections.Generic.List[string]]::new()
    $commandErrors = [System.Collections.Generic.List[object]]::new()
    foreach ($spec in $bufferSpecs) {
        $snapshot = Get-SystemHealthLogSnapshot -Name $spec.name -Arguments $spec.arguments -TimeoutSeconds 10
        $buffers[$spec.name] = [ordered]@{
            name = $spec.name
            lineIdentities = @(
                $snapshot.records | ForEach-Object { [string]$_.identity }
            )
            lineCount = [int]$snapshot.lineCount
            timestampedLineCount = [int]$snapshot.timestampedLineCount
            maxTimestamp = $snapshot.maxTimestamp
            success = [bool]$snapshot.success
            timedOut = [bool]$snapshot.timedOut
            error = $snapshot.error
        }
        if (-not [bool]$snapshot.success) {
            $errors.Add(
                "baseline $($spec.name) logcat probe failed: $($snapshot.error)"
            )
            $commandErrors.Add([ordered]@{
                    name = $spec.name
                    buffer = $spec.name
                    error = $snapshot.error
                    timedOut = [bool]$snapshot.timedOut
                })
        }
    }
    $baseline = [ordered]@{
        schemaVersion = 1
        source = $Source
        capturedAt = $capturedAt
        mode = 'bounded-snapshot-timestamp-fingerprint'
        exactCursor = $false
        maxLinesPerBuffer = 200
        buffers = $buffers
        limitations = @(
            'adb logcat cursor/serial position is unavailable to this runner',
            'baseline uses bounded -t 200 snapshots with epoch timestamps and SHA-256 line identities',
            'only lines newer than the baseline timestamp or new same-timestamp identities are accepted',
            'identical duplicate lines at the same timestamp cannot be distinguished; uncertain matches fail closed',
            'the bounded snapshot may not include records older than the selected 200-line window'
        )
        errors = @($errors)
    }
    $script:systemHealthBaseline = $baseline
    try {
        Write-SystemHealthArtifact | Out-Null
    }
    catch {
        $script:failureClassification = 'environment_invalid'
        throw "system-health baseline artifact write failed: $($_.Exception.Message)"
    }
    if ($errors.Count -gt 0) {
        $baselineObservation = Parse-SystemHealthObservation -Source "$Source-baseline" -DeviceId $DeviceId -PackageName $script:packageName -BaselineMode $baseline.mode -BaselineCapturedAt $baseline.capturedAt -BaselineLimitations $baseline.limitations -ProbeErrors @($errors) -ProbeCommandErrors @($commandErrors)
        Record-SystemHealthObservation $baselineObservation | Out-Null
        throw "system-health baseline environment_invalid: $($errors -join '; ')"
    }
    return $baseline
}

function Get-SystemHealthProbe {
    [CmdletBinding()]
    param(
        [string]$Source = 'system-health',
        [string]$DeviceId = $script:DeviceId,
        [string]$PackageName = $script:packageName
    )

    $baseline = $script:systemHealthBaseline
    if ($null -eq $baseline) {
        return Parse-SystemHealthObservation -Source $Source -DeviceId $DeviceId -PackageName $PackageName -ProbeErrors @('workload-start ANR baseline/cursor is missing')
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    $commandErrors = [System.Collections.Generic.List[object]]::new()
    $runCommand = {
        param(
            [string]$Name,
            [string[]]$Arguments,
            [double]$TimeoutSeconds,
            [bool]$AllowCleanAbsent
        )
        $command = Invoke-SystemHealthAdbCommand -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds -AllowCleanAbsent:$AllowCleanAbsent
        if (-not [bool]$command.success) {
            [void]$errors.Add("$Name probe failed: $($command.error)")
            [void]$commandErrors.Add([ordered]@{
                    name = $Name
                    arguments = @($Arguments)
                    error = $command.error
                    timedOut = [bool]$command.timedOut
                    startError = $command.startError
                    exitCode = $command.exitCode
                })
        }
        return $command
    }

    $stateCommand = & $runCommand 'adb-state' @('-s', $DeviceId, 'get-state') 5 $false
    $bootCommand = & $runCommand 'sys.boot_completed' @('-s', $DeviceId, 'shell', 'getprop', 'sys.boot_completed') 5 $false
    $systemServerCommand = & $runCommand 'system_server-pid' @('-s', $DeviceId, 'shell', 'pidof', 'system_server') 5 $false
    $systemUiCommand = & $runCommand 'systemui-pid' @('-s', $DeviceId, 'shell', 'pidof', 'com.android.systemui') 5 $true
    $windowCommand = & $runCommand 'dumpsys-window' @('-s', $DeviceId, 'shell', 'dumpsys', 'window', 'windows') 10 $false
    $activityCommand = & $runCommand 'dumpsys-activity' @('-s', $DeviceId, 'shell', 'dumpsys', 'activity', 'activities') 10 $false

    $systemUiPidStatus = if ([bool]$systemUiCommand.optionalAbsent) {
        'optional/unavailable'
    }
    elseif ([bool]$systemUiCommand.success) {
        'available'
    }
    else {
        'error'
    }
    $anrSources = [System.Collections.Generic.List[object]]::new()
    $newLinesByBuffer = [ordered]@{}
    $logBufferSpecs = @(
        [ordered]@{
            name = 'events'
            arguments = @('-s', $DeviceId, 'logcat', '-b', 'events', '-d', '-v', 'epoch', '-t', '200')
        },
        [ordered]@{
            name = 'main'
            arguments = @('-s', $DeviceId, 'logcat', '-b', 'main', '-d', '-v', 'epoch', '-t', '200')
        },
        [ordered]@{
            name = 'system'
            arguments = @('-s', $DeviceId, 'logcat', '-b', 'system', '-d', '-v', 'epoch', '-t', '200')
        }
    )
    $anrLikePattern = "(?i)\bam_anr\b|\bANR\s+in\b|Process\s+System\s+is(?:n['’]t| not)\s+responding|System\s+is(?:n['’]t| not)\s+responding|Application\s+Not\s+Responding|AppNotRespondingDialog|AnrDialog"
    foreach ($spec in $logBufferSpecs) {
        $snapshot = Get-SystemHealthLogSnapshot -Name $spec.name -Arguments $spec.arguments -TimeoutSeconds 10
        $baselineBuffer = $baseline.buffers[$spec.name]
        $newRecords = @()
        $uncertainLines = @()
        $precision = 'unavailable'
        if (-not [bool]$snapshot.success) {
            $errors.Add("$($spec.name) logcat observation failed: $($snapshot.error)")
            $commandErrors.Add([ordered]@{
                    name = "$($spec.name)-logcat"
                    buffer = $spec.name
                    arguments = @($spec.arguments)
                    error = $snapshot.error
                    timedOut = [bool]$snapshot.timedOut
                })
        }
        elseif ($null -eq $baselineBuffer) {
            $errors.Add("baseline buffer missing for $($spec.name)")
        }
        else {
            try {
                $delta = Get-SystemHealthNewLines -Snapshot $snapshot -BaselineBuffer $baselineBuffer
                $newRecords = @($delta.records)
                $uncertainLines = @($delta.uncertainLines)
                $precision = [string]$delta.precision
                foreach ($record in $newRecords) {
                    if ([string]$record.text -match $anrLikePattern) {
                        $anrSources.Add([ordered]@{
                                source = "$($spec.name)-buffer"
                                text = [string]$record.text
                            })
                    }
                }
            }
            catch {
                $errors.Add("$($spec.name) logcat baseline comparison failed: $($_.Exception.Message)")
                $commandErrors.Add([ordered]@{
                        name = "$($spec.name)-baseline-comparison"
                        buffer = $spec.name
                        arguments = @($spec.arguments)
                        error = $_.Exception.ToString()
                        timedOut = $false
                    })
            }
        }
        $newLinesByBuffer[$spec.name] = [ordered]@{
            name = $spec.name
            snapshotLineCount = [int]$snapshot.lineCount
            snapshotMaxTimestamp = $snapshot.maxTimestamp
            newLineCount = $newRecords.Count
            uncertainLineCount = $uncertainLines.Count
            precision = $precision
            newLines = @($newRecords)
            uncertainLines = @($uncertainLines)
            anrLikeNewLines = @(
                $newRecords | Where-Object {
                    [string]$_.text -match $anrLikePattern
                } | ForEach-Object { $_.text }
            )
        }
    }

    return Parse-SystemHealthObservation -Source $Source -DeviceId $DeviceId -PackageName $PackageName -Timestamp (Get-Date).ToString('o') -AdbState ([string]$stateCommand.stdout) -BootCompleted ([string]$bootCommand.stdout) -SystemServerPidText ([string]$systemServerCommand.stdout) -SystemUiPidText ([string]$systemUiCommand.stdout) -SystemUiPidStatus $systemUiPidStatus -WindowDump ([string]$windowCommand.stdout) -ActivityDump ([string]$activityCommand.stdout) -AnrSources @($anrSources.ToArray()) -ProbeErrors @($errors) -ProbeCommandErrors @($commandErrors) -BaselineMode ([string]$baseline.mode) -BaselineCapturedAt ([string]$baseline.capturedAt) -BaselineLimitations @($baseline.limitations) -NewLinesByBuffer $newLinesByBuffer
}

function Invoke-SystemHealthSentinel {
    [CmdletBinding()]
    param(
        [string]$Source = 'system-health-sentinel',
        [string]$DeviceId = $script:DeviceId,
        [string]$PackageName = $script:packageName
    )

    $observation = Get-SystemHealthProbe -Source $Source -DeviceId $DeviceId -PackageName $PackageName
    $recordedObservation = Record-SystemHealthObservation $observation
    $classification = [string]$recordedObservation.classification
    if ($classification -ceq 'environment_invalid') {
        $reason = @($recordedObservation.failureDetails.reasons) -join '; '
        throw "system-health sentinel environment_invalid: $reason"
    }
    if ($classification -ceq 'app_workload_failure') {
        $reason = @($recordedObservation.failureDetails.reasons) -join '; '
        throw "system-health sentinel app/workload failure: $reason"
    }
    if ($classification -ceq 'unknown_anr') {
        $reason = @($recordedObservation.failureDetails.reasons) -join '; '
        throw "system-health sentinel unknown ANR (fail closed): $reason"
    }
    return $recordedObservation
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

    $c6StartMatches = [regex]::Matches(
        $Log,
        'READER_C6_CASE_START seed=\d+ caseId=([^\s]+) ordinal=(\d+)'
    )
    $c6ResultMatches = [regex]::Matches(
        $Log,
        # Android logcat may wrap the following JSON for long mixed journeys;
        # progress only needs the durable marker count.  The pulled summary
        # files are the source for aggregate numeric fields.
        'READER_C6_CASE_RESULT\b'
    )
    $c6FailureMatches = [regex]::Matches(
        $Log,
        'READER_C6_CASE_FAILURE\b'
    )
    $c6ProgressMatches = [regex]::Matches(
        $Log,
        'READER_C6_PROGRESS\b'
    )
    $completedCases = $null
    $c6Mode = $false
    if ($c6ResultMatches.Count -gt 0) {
        $c6Mode = $true
        $completedCases = $c6ResultMatches.Count
        $completed = $completedCases
    }
    elseif ($c6StartMatches.Count -gt 0) {
        $c6Mode = $true
        # The marker's ordinal is a manifest field, not a progress counter;
        # count observed starts so a batch-local list never reports an
        # unrelated global ordinal (or thousands of completed cases).
        $completedCases = $c6StartMatches.Count
        $completed = $completedCases
    }
    elseif ($c6ProgressMatches.Count -gt 0) {
        $c6Mode = $true
    }

    $lastActions = @(
        @($actionMatches | ForEach-Object { $_.Value.Trim() }) +
        @($c6StartMatches | ForEach-Object { $_.Value.Trim() }) +
        @($c6ResultMatches | Select-Object -Last 20 | ForEach-Object { $_.Value.Trim() }) +
        @($c6FailureMatches | Select-Object -Last 20 | ForEach-Object { $_.Value.Trim() }) +
        @($c6ProgressMatches | Select-Object -Last 20 | ForEach-Object { $_.Value.Trim() }) |
        Select-Object -Last 20
    )
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
        'READER_CONTINUOUS_PERFORMANCE\s+status=(passed|failed|insufficient)\s+targetP99Micros=([0-9.]+)\s+actualP99Micros=([0-9.]+)\s+frames=(\d+)\s+taskP99Micros=([0-9.]+)\s+worstTaskMicros=([0-9.]+)\s+worstTaskChars=(\d+)\s+tasksOver8ms=(\d+)\s+vsyncP99=([0-9.]+)\s+buildP99=([0-9.]+)\s+rasterP99=([0-9.]+)'
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
        completedActions = if ($c6Mode) { $null } else { $completed }
        completedCases = $completedCases
        c6ProgressMarkers = if ($c6Mode) { $c6ProgressMatches.Count } else { $null }
        c6FailureMarkers = if ($c6Mode) { $c6FailureMatches.Count } else { $null }
        lastActions = $lastActions
        telemetryHeartbeat = $telemetryHeartbeat
        performance = $performance
    }
}

function Invoke-ProcessWithTimeout(
    [string]$FilePath,
    [string[]]$Arguments,
    [int]$TimeoutSeconds,
    [scriptblock]$WhileRunning
) {
    $driverSupervisorStage = 'initializing'
    $process = $null
    try {
        $driverSupervisorStage = 'creating start info'
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $FilePath
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $driverSupervisorStage = 'adding arguments'
        foreach ($argument in $Arguments) {
            $startInfo.ArgumentList.Add($argument)
        }

        $driverSupervisorStage = 'creating process'
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $driverSupervisorStage = 'starting process'
        if (-not $process.Start()) {
            throw "啟動 $FilePath 失敗。"
        }
        Write-Host "driver supervisor started pid=$($process.Id)"
        $driverSupervisorStage = 'redirecting output'
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $driverSupervisorStage = 'watching process'
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $timedOut = $false
        $previousSupervisorDeadline = $script:DriverSupervisorDeadline
        $script:DriverSupervisorDeadline = $deadline
        try {
            while (-not $process.HasExited) {
                if ((Get-Date) -ge $deadline) {
                    $timedOut = $true
                    break
                }
                if ($null -ne $WhileRunning) {
                    & $WhileRunning
                }
                # Synchronous watcher callbacks are deliberately kept small
                # and all their ADB calls inherit the remaining deadline. Do
                # not let a callback that finishes at the boundary extend the
                # child supervisor's finite timeout.
                if ((Get-Date) -ge $deadline) {
                    $timedOut = $true
                    break
                }
                Start-Sleep -Milliseconds 250
            }
        }
        finally {
            if ($null -eq $previousSupervisorDeadline) {
                Remove-Variable -Scope Script -Name DriverSupervisorDeadline -ErrorAction SilentlyContinue
            }
            else {
                $script:DriverSupervisorDeadline = $previousSupervisorDeadline
            }
        }
        if ($timedOut) {
            try {
                $process.Kill($true)
            }
            catch {
                $process.Kill()
            }
            if (-not $process.WaitForExit(3000)) {
                throw 'driver supervisor child cleanup exceeded bounded timeout 3s.'
            }
        }
        if (-not $stdoutTask.Wait(3000) -or -not $stderrTask.Wait(3000)) {
            throw 'driver supervisor output cleanup exceeded bounded timeout 3s.'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        return [ordered]@{
            exitCode = if ($timedOut) { $null } else { $process.ExitCode }
            timedOut = $timedOut
            stdout = $stdout
            stderr = $stderr
        }
    }
    catch {
        if ($null -ne $process -and -not $process.HasExited) {
            try {
                $process.Kill($true)
            }
            catch {
                try { $process.Kill() } catch { }
            }
            try { $process.WaitForExit(3000) } catch { }
        }
        throw "driver supervisor failed at $driverSupervisorStage`: $($_.Exception.ToString())"
    }
}

function Get-ResponseProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-ContinuousMeasurement(
    $Response,
    [string]$SurfaceFlingerText,
    [Nullable[int]]$DriverExitCode,
    [bool]$DriverTimedOut,
    [string]$DriverOutput,
    [bool]$InvariantHookEnabled,
    [ValidateSet('debug', 'profile')]
    [string]$BuildMode,
    [int]$ExpectedSeed,
    [string]$ExpectedAction
) {
    $invalidReasons = [System.Collections.Generic.List[string]]::new()
    $crossSource = [ordered]@{
        status = 'not_checked'
        comparisons = @()
    }

    if ($SurfaceFlingerText -notmatch 'activeMode.*vsyncRate=120\.00 Hz') {
        $invalidReasons.Add('SurfaceFlinger activeMode 未確認 vsyncRate=120.00 Hz')
    }
    if ($DriverTimedOut) {
        $invalidReasons.Add('workload 逾時或被中止')
    }

    $timeline = Get-ResponseProperty $Response 'timeline'
    $appTelemetry = Get-ResponseProperty $Response 'appTelemetry'
    $continuousResult = Get-ResponseProperty $Response 'continuousResult'
    if ($null -eq $Response) {
        $invalidReasons.Add('driver JSON 不存在或無法解析')
    }
    if ($null -eq $timeline) {
        $invalidReasons.Add('driver TimelineSummary 不存在')
    }
    if ($null -eq $appTelemetry) {
        $invalidReasons.Add('app telemetry 不存在')
    }
    if ($null -eq $continuousResult) {
        $invalidReasons.Add('continuous result 不存在，無法證明 workload 完成')
    }

    $appFrames = Get-ResponseProperty $appTelemetry 'frames'
    $timelineFrames = Get-ResponseProperty $timeline 'frame_count'
    if ($appFrames -isnot [ValueType] -or $null -eq $appFrames -or [double]$appFrames -lt 300) {
        $invalidReasons.Add("app telemetry frame 數不足 300：$appFrames")
    }
    if ($timelineFrames -isnot [ValueType] -or $null -eq $timelineFrames) {
        $invalidReasons.Add('driver TimelineSummary 缺少 frame_count')
    }
    elseif ([double]$timelineFrames -lt 300) {
        $invalidReasons.Add("driver TimelineSummary frame 數不足 300：$timelineFrames")
    }

    $completedActions = Get-ResponseProperty $continuousResult 'completedActions'
    $actionMarkers = Get-ResponseProperty $continuousResult 'actionMarkers'
    $logHasActionMarker = $DriverOutput -match 'READER_CONTINUOUS_ACTION seed=\d+ #\d+'
    if ($null -eq $completedActions -or [int]$completedActions -le 0 -or
        (($null -eq $actionMarkers -or @($actionMarkers).Count -eq 0) -and -not $logHasActionMarker)) {
        $invalidReasons.Add('completedActions 不大於 0 或缺少 action marker')
    }

    $markerMatches = [regex]::Matches(
        $DriverOutput,
        '(?m)READER_CONTINUOUS_ACTION seed=(\d+) #\d+ ([^\r\n]+)$'
    )
    if ($markerMatches.Count -eq 0) {
        $invalidReasons.Add('缺少可解析的 READER_CONTINUOUS_ACTION marker')
    }
    else {
        foreach ($markerMatch in $markerMatches) {
            if ([int]$markerMatch.Groups[1].Value -ne $ExpectedSeed) {
                $invalidReasons.Add(
                    "action marker seed 與 requested seed 不一致：marker=$($markerMatch.Groups[1].Value) requested=$ExpectedSeed"
                )
                break
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedAction)) {
            $expectedActionPattern = '(?m)READER_CONTINUOUS_ACTION seed=' +
                [regex]::Escape([string]$ExpectedSeed) +
                '\s+#\d+\s+' + [regex]::Escape($ExpectedAction) + '$'
            if ($DriverOutput -notmatch $expectedActionPattern) {
                $invalidReasons.Add(
                    "action marker 與 requested action 不一致：requested=$ExpectedAction"
                )
            }
        }
    }

    $reportedInvariantHookEnabled = Get-ResponseProperty $appTelemetry 'invariantHookEnabled'
    if ($InvariantHookEnabled) {
        if ($reportedInvariantHookEnabled -ne $true) {
            $invalidReasons.Add("invariantHookEnabled 必須為 true，實際為 $reportedInvariantHookEnabled")
        }
    }
    elseif ($reportedInvariantHookEnabled -ne $false) {
        $invalidReasons.Add("invariantHookEnabled 必須為 false，實際為 $reportedInvariantHookEnabled")
    }

    $expectedCategory = if ($ExpectedAction -match '^scroll_') {
        'scroll'
    }
    elseif ($ExpectedAction -match '^interaction_') {
        'interaction'
    }
    elseif ($ExpectedAction -match '^navigation_') {
        'navigation'
    }
    elseif ($ExpectedAction -match '^entry_') {
        'entry'
    }
    elseif ($ExpectedAction -eq 'chapter_switch_while_ballistic') {
        'scroll'
    }
    else {
        $null
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedAction) -and
        $null -ne $expectedCategory) {
        $operationAttribution = Get-ResponseProperty $continuousResult 'operationAttribution'
        $attributedActions = @(Get-ResponseProperty $operationAttribution 'actions')
        $matchingAttribution = @($attributedActions | Where-Object {
            (Get-ResponseProperty $_ 'action') -eq $ExpectedAction
        })
        if ($matchingAttribution.Count -eq 0) {
            $invalidReasons.Add("operationAttribution 缺少 requested action：$ExpectedAction")
        }
        else {
            $observedCategory = Get-ResponseProperty $matchingAttribution[0] 'category'
            if ($observedCategory -ne $expectedCategory) {
                $invalidReasons.Add(
                    "action category 不一致：action=$ExpectedAction expected=$expectedCategory actual=$observedCategory"
                )
            }
            $exclusiveAction = Get-ResponseProperty $operationAttribution 'exclusiveAction'
            $frameScope = Get-ResponseProperty $operationAttribution 'frameScope'
            if ($exclusiveAction -ne $true -or
                $frameScope -ne 'performance window contains only this forced action') {
                $invalidReasons.Add(
                    "requested action 沒有 exclusive action window：action=$ExpectedAction"
                )
            }
            $frameMetrics = Get-ResponseProperty $operationAttribution 'frameMetrics'
            $categoryFrames = Get-ResponseProperty $frameMetrics 'frames'
            if ($categoryFrames -isnot [ValueType] -or $null -eq $categoryFrames -or
                [double]$categoryFrames -lt 300) {
                $invalidReasons.Add(
                    "category-filtered frame 數不足 300：action=$ExpectedAction frames=$categoryFrames"
                )
            }
        }
    }

    $appBuild = Get-ResponseProperty $appTelemetry 'buildP99Micros'
    $appRaster = Get-ResponseProperty $appTelemetry 'rasterP99Micros'
    $driverBuildMillis = Get-ResponseProperty $timeline '99th_percentile_frame_build_time_millis'
    $driverRasterMillis = Get-ResponseProperty $timeline '99th_percentile_frame_rasterizer_time_millis'
    $comparisons = [System.Collections.Generic.List[object]]::new()
    function Compare-SourceValue([string]$Name, $AppValue, $DriverMillis) {
        if ($null -eq $AppValue -or $null -eq $DriverMillis) {
            if (-not $InvariantHookEnabled) {
                $invalidReasons.Add("兩來源缺少 $Name 分位數")
            }
            return
        }
        $driverMicros = [double]$DriverMillis * 1000.0
        $difference = [Math]::Abs([double]$AppValue - $driverMicros)
        $tolerance = [Math]::Max([Math]::Max([double]$AppValue, $driverMicros) * 0.2, 1000.0)
        $within = $difference -le $tolerance
        $comparisons.Add([ordered]@{
            metric = $Name
            appMicros = [double]$AppValue
            driverMillis = [double]$DriverMillis
            driverMicros = $driverMicros
            differenceMicros = $difference
            toleranceMicros = $tolerance
            withinTolerance = $within
        })
        # Hook-on runs are observational by contract. Keep the comparison in
        # the artifact, but do not make a non-gating P99 discrepancy fail the
        # invariant workload. Hook-off runs retain the strict check.
        if (-not $within -and -not $InvariantHookEnabled) {
            $invalidReasons.Add("兩來源 $Name 不一致：app=$AppValue µs driver=$driverMillis ms")
        }
    }
    Compare-SourceValue 'buildP99' $appBuild $driverBuildMillis
    Compare-SourceValue 'rasterP99' $appRaster $driverRasterMillis
    if ($null -ne $appFrames -and $null -ne $timelineFrames) {
        $frameDifference = [Math]::Abs([double]$appFrames - [double]$timelineFrames)
        $frameTolerance = [Math]::Max([double]$appFrames, [double]$timelineFrames) * 0.2
        $frameWithin = $frameDifference -le $frameTolerance
        $comparisons.Add([ordered]@{
            metric = 'frames'
            appFrames = [int]$appFrames
            driverFrames = [int]$timelineFrames
            difference = $frameDifference
            tolerance = $frameTolerance
            withinTolerance = $frameWithin
        })
        if (-not $frameWithin) {
            $invalidReasons.Add("兩來源 frame 數不一致：app=$appFrames driver=$timelineFrames")
        }
    }
    $crossSource.comparisons = @($comparisons)
    $crossSource.status = if ($InvariantHookEnabled) {
        'observed'
    }
    elseif ($invalidReasons.Count -eq 0) {
        'valid'
    }
    else {
        'invalid'
    }

    $status = 'invalid'
    if ($invalidReasons.Count -eq 0) {
        if ($BuildMode -ne 'profile') {
            # Debug continuous runs prove behavior/races only. They must never
            # become a performance pass even when their timing happens to be low.
            $status = if ($DriverExitCode -eq 0) { 'observed' } else { 'failed' }
        }
        elseif ($InvariantHookEnabled) {
            # The invariant hook is intentionally mutually exclusive with a
            # performance conclusion. Keep workload/120Hz evidence, but do
            # not evaluate P99 while the debug observer is enabled.
            $status = if ($DriverExitCode -eq 0) { 'observed' } else { 'failed' }
        }
        else {
            $frameP99 = [double](Get-ResponseProperty $appTelemetry 'frameP99Micros')
            $status = if ($frameP99 -lt 8000 -and $DriverExitCode -eq 0) {
                'passed'
            }
            else {
                'failed'
            }
        }
    }
    return [ordered]@{
        status = $status
        invalidReasons = @($invalidReasons)
        targetP99Micros = 8000
        appTelemetry = $appTelemetry
        timeline = $timeline
        continuousResult = $continuousResult
        crossSourceValidation = $crossSource
        driverExitCode = $DriverExitCode
        driverTimedOut = $DriverTimedOut
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

function Push-C6InputFiles {
    if ($Scenario -ne 'correctness-subset') { return }
    $manifestSource = if (-not [string]::IsNullOrWhiteSpace($CaseList)) {
        $CaseList
    }
    else {
        $c6ManifestHostPath
    }
    $manifest = Resolve-Path -LiteralPath $manifestSource -ErrorAction Stop
    Invoke-Adb @('-s', $DeviceId, 'shell', 'mkdir', '-p', $fixtureDirectory) | Out-Null
    Invoke-AdbBounded @(
        '-s', $DeviceId, 'push', $manifest.Path, $c6ManifestDevicePath
    ) | ForEach-Object { Write-Host $_ }
    if (-not [string]::IsNullOrWhiteSpace($HostFailureCaseList)) {
        $failures = Resolve-Path -LiteralPath $HostFailureCaseList -ErrorAction Stop
        Invoke-AdbBounded @(
            '-s', $DeviceId, 'push', $failures.Path, $c6HostFailureDevicePath
        ) | ForEach-Object { Write-Host $_ }
    }
    else {
        # An absent host-failure list is an explicit empty input, not a reason
        # for the Android test to invent a replay case.
        $emptyFailurePath = Join-Path $reportDir 'c6-host-failures-empty.json'
        '[]' | Set-Content -LiteralPath $emptyFailurePath -Encoding utf8
        Invoke-AdbBounded @(
            '-s', $DeviceId, 'push', $emptyFailurePath, $c6HostFailureDevicePath
        ) | ForEach-Object { Write-Host $_ }
    }
    Write-Host "C6 manifest pushed: $manifestSource -> $c6ManifestDevicePath"
}

function Capture-C6FailureVideo {
    if ($Scenario -ne 'correctness-subset') { return $null }
    $remote = '/sdcard/NightReader-c6-failure.mp4'
    $local = Join-Path $reportDir 'failure-video-post-detection.mp4'
    try {
        # This is deliberately started only after a C6 failure marker is
        # observed. It is bounded post-detection context, never a per-frame
        # oracle and never an always-on recording.
        Invoke-ProcessWithTimeout `
            -FilePath 'adb' `
            -Arguments @('-s', $DeviceId, 'shell', 'screenrecord', '--time-limit', '20', $remote) `
            -TimeoutSeconds 25 `
            -WhileRunning $null | Out-Null
        # Use the same directory-first transport rule as case evidence.  A
        # direct pull to a Windows file path is version-dependent when the
        # destination already exists or is interpreted as a directory.
        Copy-C6RemoteFileViaStaging `
            -RemoteFile $remote `
            -DestinationPath $local `
            -TimeoutSeconds 5 | Out-Null
        Invoke-Adb @('-s', $DeviceId, 'shell', 'rm', '-f', $remote) | Out-Null
        return $local
    }
    catch {
        Write-Warning "保存 C6 bounded failure video 失敗：$($_.Exception.Message)"
        return $null
    }
}

function Export-C6EvidenceBundles([string]$FailureVideoPath) {
    if ($Scenario -ne 'correctness-subset') { return }

    # Evidence transport is deliberately separate from the C6 oracle.  The app
    # owns case traces; this function only copies them, validates their bytes,
    # and records an explicit incomplete result when a required item is absent.
    # In particular, never create an empty required trace or fallback metadata:
    # that would turn an adb/path collision into apparently complete evidence.
    $pullRoot = Join-Path $reportDir 'c6-evidence-pulled'
    $rawRoot = Join-Path $pullRoot 'cases'
    New-Item -ItemType Directory -Path $pullRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null

    $expectedCaseIds = [System.Collections.Generic.List[string]]::new()
    $pullErrors = [System.Collections.Generic.List[object]]::new()
    if (-not [string]::IsNullOrWhiteSpace($CaseList) -and
        (Test-Path -LiteralPath $CaseList -PathType Leaf)) {
        try {
            $caseListData = Get-Content -Raw -LiteralPath $CaseList | ConvertFrom-Json
            foreach ($case in @($caseListData.cases)) {
                $caseId = [string](Get-ResponseProperty $case 'caseId')
                if (-not [string]::IsNullOrWhiteSpace($caseId) -and
                    -not $expectedCaseIds.Contains($caseId)) {
                    $expectedCaseIds.Add($caseId)
                }
            }
        }
        catch {
            $pullErrors.Add([ordered]@{
                    phase = 'parse-case-list'
                    message = $_.Exception.Message
                })
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($CaseId) -and
        -not $expectedCaseIds.Contains($CaseId)) {
        $expectedCaseIds.Add($CaseId)
    }

    $logSources = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($lastWorkloadLog)) {
        $logSources.Add($lastWorkloadLog)
    }
    foreach ($logPath in @(
        (Join-Path $reportDir 'workload-logcat.txt'),
        (Join-Path $reportDir 'driver-output.txt')
    )) {
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            $logSources.Add((Get-Content -Raw -LiteralPath $logPath))
        }
    }
    $markerLog = $logSources -join "`n"
    $markerCaseIds = [System.Collections.Generic.List[string]]::new()
    # Android logcat can truncate the long JSON result/failure line. The app
    # marker helper extracts its caseId from the intact prefix without treating
    # a truncated marker as a complete summary or as evidence by itself.
    foreach ($markerCaseId in @(Get-C6MarkerCaseIds -Log $markerLog)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$markerCaseId) -and
            -not $markerCaseIds.Contains([string]$markerCaseId)) {
            $markerCaseIds.Add([string]$markerCaseId)
        }
    }

    $caseIds = [System.Collections.Generic.List[string]]::new()
    foreach ($caseId in $expectedCaseIds) { $caseIds.Add([string]$caseId) }
    foreach ($caseId in $markerCaseIds) {
        if (-not $caseIds.Contains([string]$caseId)) {
            $caseIds.Add([string]$caseId)
        }
    }

    $safeNameOwners = @{}
    $safeCaseNames = @{}
    foreach ($caseId in $caseIds) {
        $safeCaseName = Get-C6SafeCaseName ([string]$caseId)
        if ($safeNameOwners.ContainsKey($safeCaseName) -and
            $safeNameOwners[$safeCaseName] -cne [string]$caseId) {
            throw "C6 case directory name collision：$($safeNameOwners[$safeCaseName]) vs $caseId -> $safeCaseName"
        }
        $safeNameOwners[$safeCaseName] = [string]$caseId
        $safeCaseNames[[string]$caseId] = $safeCaseName
    }

    $appRequiredEvidenceFiles = @(
        'metadata.json',
        'operation-trace.jsonl',
        'runtime-frame-trace.jsonl',
        'invariant-violations.jsonl',
        'visual-violations.jsonl',
        'summary.json',
        'summary.md'
    )
    $optionalEvidenceFiles = @(Get-C6OptionalEvidenceFileNames)
    $drainStartedAt = Get-Date
    $drainTimeoutSeconds = 20
    $drainPollIntervalMilliseconds = 500
    $pollSnapshots = [System.Collections.Generic.List[object]]::new()
    $drainDeadlineExceeded = $false
    $appCompleteCaseIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $caseRecords = @{}
    $missingAppCaseIds = @()
    $drainCaseIds = if ($expectedCaseIds.Count -gt 0) {
        @($expectedCaseIds)
    }
    else {
        @($caseIds)
    }

    if ($caseIds.Count -gt 0) {
        $drainDeadline = $drainStartedAt.AddSeconds($drainTimeoutSeconds)
        do {
            # The raw transport directory is refreshed on every poll.  Reset
            # the completion set as well, otherwise a case that was complete
            # in an earlier poll could remain reported as complete after a
            # later refresh/pull failure removed its files.
            $appCompleteCaseIds.Clear()
            foreach ($caseId in $caseIds) {
                if ((Get-Date) -ge $drainDeadline) {
                    $drainDeadlineExceeded = $true
                    break
                }
                $safeCaseId = $safeCaseNames[[string]$caseId]
                $remoteCase = "$c6EvidenceDevicePath/$safeCaseId"
                $localCase = Join-Path $rawRoot $safeCaseId
                $casePullErrors = [System.Collections.Generic.List[object]]::new()
                $remoteFiles = @()
                $transportRefreshFailed = $false
                if (Test-Path -LiteralPath $localCase -PathType Leaf) {
                    $pullError = [ordered]@{
                        phase = 'local-case-directory-collision'
                        caseId = $caseId
                        remoteDirectory = $remoteCase
                        localDirectory = $localCase
                        message = 'local case destination is a file, not a directory'
                    }
                    $pullErrors.Add($pullError)
                    $casePullErrors.Add($pullError)
                }
                else {
                    New-Item -ItemType Directory -Path $localCase -Force | Out-Null
                    # Never let a successful file from an earlier poll satisfy
                    # this poll after a later adb pull fails or the remote file
                    # disappears. These are exporter-owned raw copies; leave
                    # directories intact so path collisions remain visible to
                    # the validator instead of being silently repaired.
                    try {
                        Get-ChildItem -LiteralPath $localCase -Recurse -File `
                            -ErrorAction Stop | ForEach-Object {
                                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                            }
                    }
                    catch {
                        $transportRefreshFailed = $true
                        $pullError = [ordered]@{
                            phase = 'transport-refresh'
                            caseId = $caseId
                            localDirectory = $localCase
                            message = "could not clear prior transport copies: $($_.Exception.Message)"
                        }
                        $pullErrors.Add($pullError)
                        $casePullErrors.Add($pullError)
                    }
                    try {
                        $remoteFiles = @(
                            Invoke-AdbBounded @(
                                '-s', $DeviceId, 'shell', 'find', $remoteCase, '-type', 'f'
                            ) 5
                        ) | ForEach-Object { ([string]$_).Trim() } |
                            Where-Object { $_ -like "$remoteCase/*" }
                    }
                    catch {
                        $pullError = [ordered]@{
                            phase = 'list'
                            caseId = $caseId
                            remoteDirectory = $remoteCase
                            message = $_.Exception.Message
                        }
                        $pullErrors.Add($pullError)
                        $casePullErrors.Add($pullError)
                    }

                    foreach ($remoteFile in $remoteFiles) {
                        if ((Get-Date) -ge $drainDeadline) {
                            $drainDeadlineExceeded = $true
                            break
                        }
                        $relative = ([string]$remoteFile).Substring($remoteCase.Length) -replace '^[/\\]+', ''
                        try {
                            $localFile = Resolve-C6ContainedPath `
                                -BaseDirectory $localCase `
                                -RelativePath $relative
                        }
                        catch {
                            $pullError = [ordered]@{
                                phase = 'validate-remote-path'
                                caseId = $caseId
                                remoteFile = $remoteFile
                                relativePath = $relative
                                message = $_.Exception.Message
                            }
                            $pullErrors.Add($pullError)
                            $casePullErrors.Add($pullError)
                            continue
                        }
                        if (Test-Path -LiteralPath $localFile -PathType Container) {
                            $pullError = [ordered]@{
                                phase = 'local-path-collision'
                                caseId = $caseId
                                remoteFile = $remoteFile
                                relativePath = $relative
                                localFile = $localFile
                                message = 'local destination is a directory, not a file'
                            }
                            $pullErrors.Add($pullError)
                            $casePullErrors.Add($pullError)
                            continue
                        }
                        try {
                            # All adb file copies, including nested evidence and
                            # supplemental captures, use the same isolated
                            # staging -> exact leaf -> final copy helper.
                            Copy-C6RemoteFileViaStaging `
                                -RemoteFile ([string]$remoteFile) `
                                -DestinationPath $localFile `
                                -TimeoutSeconds 5 | Out-Null
                        }
                        catch {
                            $pullError = [ordered]@{
                                phase = 'pull'
                                caseId = $caseId
                                remoteFile = $remoteFile
                                relativePath = $relative
                                localFile = $localFile
                                message = $_.Exception.Message
                            }
                            $pullErrors.Add($pullError)
                            $casePullErrors.Add($pullError)
                        }
                    }
                }

                $appSummaryObject = $null
                $appMetadataObject = $null
                $appSummaryPath = Join-Path $localCase 'summary.json'
                $appMetadataPath = Join-Path $localCase 'metadata.json'
                if (Test-Path -LiteralPath $appSummaryPath -PathType Leaf) {
                    try {
                        $appSummaryObject = Get-Content -Raw -LiteralPath $appSummaryPath |
                            ConvertFrom-Json
                    }
                    catch { }
                }
                if (Test-Path -LiteralPath $appMetadataPath -PathType Leaf) {
                    try {
                        $appMetadataObject = Get-Content -Raw -LiteralPath $appMetadataPath |
                            ConvertFrom-Json
                    }
                    catch { }
                }
                $appFailureKind = Get-C6FailureKind `
                    -Metadata $appMetadataObject `
                    -Summary $appSummaryObject
                $requiresInvariantEvidence = $appFailureKind -eq 'invariant-violation'
                $requiresVisualEvidence = $appFailureKind -eq 'visual-violation'
                foreach ($counterName in @('runtimeViolations', 'temporalViolations')) {
                    $counterValue = Get-ResponseProperty $appSummaryObject $counterName
                    try {
                        if ([int]$counterValue -gt 0) {
                            $requiresInvariantEvidence = $true
                        }
                    }
                    catch { }
                }
                foreach ($counterName in @('visualViolations', 'crossOracleViolations')) {
                    $counterValue = Get-ResponseProperty $appSummaryObject $counterName
                    try {
                        if ([int]$counterValue -gt 0) {
                            $requiresVisualEvidence = $true
                        }
                    }
                    catch { }
                }
                $appFiles = @()
                foreach ($appName in $appRequiredEvidenceFiles) {
                    $appPath = Join-Path $localCase $appName
                    $isFile = Test-Path -LiteralPath $appPath -PathType Leaf
                    $isDirectory = Test-Path -LiteralPath $appPath -PathType Container
                    $size = if ($isFile) { [long](Get-Item -LiteralPath $appPath).Length } else { 0 }
                    $allowEmpty = switch ($appName) {
                        'invariant-violations.jsonl' { -not $requiresInvariantEvidence }
                        'visual-violations.jsonl' { -not $requiresVisualEvidence }
                        default { $false }
                    }
                    $appFiles += [ordered]@{
                        name = $appName
                        path = $appPath
                        exists = $isFile
                        pathIsDirectory = $isDirectory
                        sizeBytes = $size
                        nonEmpty = $isFile -and $size -gt 0
                        allowEmpty = $allowEmpty
                        valid = $isFile -and ($allowEmpty -or $size -gt 0)
                        pullErrors = @($casePullErrors | Where-Object {
                                [string]$_.relativePath -ceq $appName -or
                                [string]$_.phase -in @(
                                    'list',
                                    'local-case-directory-collision',
                                    'transport-refresh'
                                )
                            })
                    }
                }
                $appComplete = -not $transportRefreshFailed -and
                    @($appFiles | Where-Object { -not $_.valid }).Count -eq 0
                if ($appComplete) {
                    [void]$appCompleteCaseIds.Add([string]$caseId)
                }
                $caseRecords[[string]$caseId] = [ordered]@{
                    caseId = [string]$caseId
                    safeCaseDirectory = $safeCaseId
                    remoteDirectory = $remoteCase
                    localDirectory = $localCase
                    remoteFileCount = $remoteFiles.Count
                    remoteFiles = @($remoteFiles)
                    appEvidenceStatus = if ($appComplete) { 'complete' } else { 'incomplete' }
                    appFiles = @($appFiles)
                    pullErrors = @($casePullErrors)
                }
                if ((Get-Date) -ge $drainDeadline) {
                    $drainDeadlineExceeded = $true
                    break
                }
            }
            $missingAppCaseIds = @(
                $drainCaseIds | Where-Object {
                    -not $appCompleteCaseIds.Contains([string]$_)
                }
            )
            $pollSnapshots.Add([ordered]@{
                poll = $pollSnapshots.Count + 1
                capturedAt = (Get-Date).ToString('o')
                completeCaseCount = $appCompleteCaseIds.Count
                missingCaseIds = @($missingAppCaseIds)
            })
            if ($missingAppCaseIds.Count -gt 0 -and (Get-Date) -lt $drainDeadline) {
                Start-Sleep -Milliseconds $drainPollIntervalMilliseconds
            }
        } while ($missingAppCaseIds.Count -gt 0 -and
            -not $drainDeadlineExceeded -and
            (Get-Date) -lt $drainDeadline)
        $drainFinishedAt = Get-Date
        $missingAppCaseIds = @(
            $drainCaseIds | Where-Object {
                -not $appCompleteCaseIds.Contains([string]$_)
            }
        )
    }
    else {
        $drainFinishedAt = Get-Date
    }

    if ($caseIds.Count -eq 0) {
        Write-Warning 'C6 evidence 沒有可解析 case id；只保留 root failure artifacts，bundle 未宣稱完整。'
        $noCaseReport = [ordered]@{
            schemaVersion = 2
            mode = 'bounded-post-result-drain'
            status = 'incomplete'
            expectedCaseCount = 0
            completeCaseCount = 0
            incompleteCaseIds = @()
            pullErrors = @($pullErrors)
            reason = 'no case id was available from CaseList/CaseId/log markers'
        }
        $noCaseReport | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $reportDir 'evidence-drain.json') -Encoding utf8
        return $noCaseReport
    }

    $bundleValidations = @{}
    $finalRefreshErrorsByCase = @{}
    foreach ($caseId in $caseIds) {
        if ((Get-Date) -ge $drainDeadline) {
            $drainDeadlineExceeded = $true
            break
        }
        $safeCaseId = $safeCaseNames[[string]$caseId]
        $bundle = Join-Path $reportDir $safeCaseId
        if (Test-Path -LiteralPath $bundle -PathType Leaf) {
            # A file at the stable bundle directory path is unrecoverable for
            # this case. Preserve it, report it through the normal validator,
            # and continue so other cases still receive their own records.
            $bundleCollisionError = [ordered]@{
                phase = 'local-bundle-directory-collision'
                caseId = $caseId
                localDirectory = $bundle
                message = 'final bundle destination is a file, not a directory'
            }
            $pullErrors.Add($bundleCollisionError)
            $validation = Test-C6BundleDirectory `
                -Directory $bundle `
                -ExpectedCaseId ([string]$caseId)
            $validation['errors'] = @($validation.errors) +
                'final bundle destination is a file, not a directory'
            $validation['status'] = 'incomplete'
            $validation['complete'] = $false
            $bundleValidations[[string]$caseId] = $validation
            continue
        }
        New-Item -ItemType Directory -Path $bundle -Force | Out-Null
        $finalRefreshErrors = [System.Collections.Generic.List[object]]::new()
        # A caller may intentionally reuse a report directory.  Remove only
        # the evidence filenames owned by this exporter so stale screenshots,
        # traces, logcat or video cannot satisfy a later validation after the
        # current transport is incomplete.  Preserve directories to expose a
        # path collision instead of deleting user data or repairing it.
        $finalEvidenceNames = @(
            $appRequiredEvidenceFiles +
            $optionalEvidenceFiles +
            'logcat.txt',
            'failure-video.mp4',
            'screenshot-before.png',
            'screenshot-violation.png',
            'screenshot-after.png',
            'transport-summary.md'
        )
        foreach ($evidenceName in $finalEvidenceNames) {
            if ((Get-Date) -ge $drainDeadline) {
                $drainDeadlineExceeded = $true
                break
            }
            $stalePath = Join-Path $bundle $evidenceName
            if (Test-Path -LiteralPath $stalePath -PathType Leaf) {
                try {
                    Remove-Item -LiteralPath $stalePath -Force -ErrorAction Stop
                }
                catch {
                    $finalRefreshErrors.Add([ordered]@{
                            phase = 'final-refresh'
                            caseId = $caseId
                            localFile = $stalePath
                            relativePath = $evidenceName
                            message = "could not remove stale final evidence: $($_.Exception.Message)"
                        })
                }
            }
            elseif (Test-Path -LiteralPath $stalePath -PathType Container) {
                $finalRefreshErrors.Add([ordered]@{
                        phase = 'final-refresh'
                        caseId = $caseId
                        localFile = $stalePath
                        relativePath = $evidenceName
                        message = 'final evidence path is a directory; preserved for fail-closed validation'
                    })
            }
        }
        $finalRefreshErrorsByCase[[string]$caseId] = @($finalRefreshErrors)
        $rawCase = Join-Path $rawRoot $safeCaseId
        foreach ($name in @($appRequiredEvidenceFiles + $optionalEvidenceFiles)) {
            $source = Join-Path $rawCase $name
            if (Test-Path -LiteralPath $source -PathType Leaf) {
                Copy-Item -LiteralPath $source -Destination (Join-Path $bundle $name) -Force
            }
        }

        # A failed bundle must identify the actual failure-time log capture.
        # Do not silently downgrade to the filtered workload polling log: if
        # failure-logcat.txt was not captured, logcat.txt stays missing and
        # the fail-closed validator reports the transport gap.
        $logcatSource = Join-Path $reportDir 'failure-logcat.txt'
        if (Test-Path -LiteralPath $logcatSource -PathType Leaf) {
            Copy-Item -LiteralPath $logcatSource `
                -Destination (Join-Path $bundle 'logcat.txt') -Force
        }
        foreach ($file in @('screenshot-before.png', 'screenshot-violation.png', 'screenshot-after.png')) {
            # Only app-owned retained C4 frames are eligible.  The report-level
            # screencap and post-detection screenshots are intentionally not a
            # fallback for these names.
            $source = Join-Path $rawCase $file
            if (Test-Path -LiteralPath $source -PathType Leaf) {
                Copy-Item -LiteralPath $source -Destination (Join-Path $bundle $file) -Force
            }
        }
        $goldenSourceDirectory = Join-Path $rawCase 'golden'
        if (Test-Path -LiteralPath $goldenSourceDirectory -PathType Container) {
            $goldenDirectory = Join-Path $bundle 'golden'
            New-Item -ItemType Directory -Path $goldenDirectory -Force | Out-Null
            Get-ChildItem -LiteralPath $goldenSourceDirectory -Filter '*.png' -File |
                ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName `
                        -Destination (Join-Path $goldenDirectory $_.Name) -Force
                }
        }
        if (-not [string]::IsNullOrWhiteSpace($FailureVideoPath) -and
            (Test-Path -LiteralPath $FailureVideoPath -PathType Leaf)) {
            Copy-Item -LiteralPath $FailureVideoPath `
                -Destination (Join-Path $bundle 'failure-video.mp4') -Force
        }

        # The case bundle contract belongs to the app-owned case outcome. A
        # runner-level error is recorded in root metadata and must not turn a
        # passed case into a failed case that requires logcat/video; doing so
        # makes the exporter and the independent drain validator derive
        # different required-file lists. Test-C6BundleDirectory derives the
        # failure contract from the case metadata/summary itself, including
        # failure-only logcat/video when the case actually failed.
        $validation = Test-C6BundleDirectory `
            -Directory $bundle `
            -ExpectedCaseId ([string]$caseId)
        if ($finalRefreshErrors.Count -gt 0) {
            $validation['errors'] = @($validation.errors) + @(
                $finalRefreshErrors | ForEach-Object {
                    "final-refresh $($_.relativePath): $($_.message)"
                }
            )
            $validation['status'] = 'incomplete'
            $validation['complete'] = $false
        }
        # The app-owned manifest describes what the app wrote.  Replace it
        # after transport with the final host-side validation so consumers do
        # not mistake an app-owned pre-transport manifest for a complete
        # bundle.
        try {
            $null = Write-C6BundleManifest -Directory $bundle -Validation $validation
        }
        catch {
            Write-Warning "寫入 C6 final bundle manifest 失敗：$($_.Exception.Message)"
        }
        $bundleValidations[[string]$caseId] = $validation

        if (-not [bool]$validation.complete) {
            # This is a human-readable transport diagnosis, not a replacement
            # for the required app-owned summary.md.
            $transportErrorLines = if (@($validation.errors).Count -eq 0) {
                @('- none reported')
            }
            else {
                @($validation.errors | ForEach-Object { "- $_" })
            }
            $transportLines = @(
                '# C6 evidence transport summary',
                '',
                "- caseId: $caseId",
                '- status: incomplete',
                "- failureKind: $($validation.failureKind)",
                "- firstBadFrameSource: $($validation.firstBadFrameSource)",
                '',
                '## Missing or invalid evidence',
                ''
            ) + @($transportErrorLines) + @(
                '',
                'The required app-owned evidence was not fabricated or replaced by a post-detection screenshot.'
            )
            Set-Content -LiteralPath (Join-Path $bundle 'transport-summary.md') `
                -Value $transportLines -Encoding utf8
        }
    }

    $caseReports = @()
    foreach ($caseId in $caseIds) {
        $caseRecord = if ($caseRecords.ContainsKey([string]$caseId)) {
            $caseRecords[[string]$caseId]
        } else { $null }
        $validation = $bundleValidations[[string]$caseId]
        $bundleFiles = @()
        if ($null -ne $validation) {
            foreach ($file in @($validation.files)) {
                $pullForFile = if ($null -ne $caseRecord) {
                    @($caseRecord.pullErrors | Where-Object {
                            [string]$_.relativePath -ceq [string]$file.name -or
                            [string]$_.phase -in @(
                                'list',
                                'local-case-directory-collision',
                                'transport-refresh'
                            )
                        })
                } else { @() }
                $pullForFile = @($pullForFile) + @(
                    $finalRefreshErrorsByCase[[string]$caseId] | Where-Object {
                        [string]$_.relativePath -ceq [string]$file.name
                    }
                )
                $bundleFiles += [ordered]@{
                    name = $file.name
                    required = $file.required
                    allowEmpty = $file.allowEmpty
                    source = $file.source
                    reason = $file.reason
                    path = $file.path
                    exists = $file.exists
                    pathIsDirectory = $file.pathIsDirectory
                    sizeBytes = $file.sizeBytes
                    nonEmpty = $file.nonEmpty
                    state = $file.state
                    valid = $file.valid
                    pullErrors = @($pullForFile)
                }
            }
        }
        $caseReports += [ordered]@{
            caseId = [string]$caseId
            safeCaseDirectory = $safeCaseNames[[string]$caseId]
            remoteDirectory = if ($null -ne $caseRecord) { $caseRecord.remoteDirectory } else { "$c6EvidenceDevicePath/$($safeCaseNames[[string]$caseId])" }
            localDirectory = if ($null -ne $caseRecord) { $caseRecord.localDirectory } else { Join-Path $rawRoot $safeCaseNames[[string]$caseId] }
            appEvidenceStatus = if ($null -ne $caseRecord) { $caseRecord.appEvidenceStatus } else { 'incomplete' }
            appFiles = if ($null -ne $caseRecord) { @($caseRecord.appFiles) } else { @() }
            bundleStatus = if ($null -ne $validation) { $validation.status } else { 'incomplete' }
            bundleComplete = if ($null -ne $validation) { $validation.complete } else { $false }
            bundleFailureKind = if ($null -ne $validation) { $validation.failureKind } else { 'unclassified-failure' }
            firstBadFrameSource = if ($null -ne $validation) { $validation.firstBadFrameSource } else { $null }
            requiredFiles = $bundleFiles
            missingRequiredFiles = if ($null -ne $validation) { @($validation.missingRequiredFiles) } else { @() }
            errors = if ($null -ne $validation) { @($validation.errors) } else { @('bundle was not assembled') }
            pullErrors = @(
                if ($null -ne $caseRecord) { @($caseRecord.pullErrors) }
                @($finalRefreshErrorsByCase[[string]$caseId])
            )
        }
    }
    $incompleteBundleIds = @(
        $caseReports | Where-Object { -not $_.bundleComplete } |
            ForEach-Object { $_.caseId }
    )
    $allBundleComplete = $caseReports.Count -gt 0 -and $incompleteBundleIds.Count -eq 0
    $missingMarkerCaseIds = @(
        $expectedCaseIds | Where-Object { -not $markerCaseIds.Contains([string]$_) }
    )
    $unexpectedMarkerCaseIds = @(
        $markerCaseIds | Where-Object { -not $expectedCaseIds.Contains([string]$_) }
    )
    $drainReport = [ordered]@{
        schemaVersion = 2
        mode = 'bounded-post-result-drain'
        expectedCaseCount = $expectedCaseIds.Count
        expectedCaseIds = @($expectedCaseIds)
        markerCaseCount = $markerCaseIds.Count
        markerCaseIds = @($markerCaseIds)
        markerMismatch = $expectedCaseIds.Count -gt 0 -and
            ($missingMarkerCaseIds.Count -gt 0 -or $unexpectedMarkerCaseIds.Count -gt 0)
        missingMarkerCaseIds = @($missingMarkerCaseIds)
        unexpectedMarkerCaseIds = @($unexpectedMarkerCaseIds)
        drainCaseCount = $drainCaseIds.Count
        drainTimeoutSeconds = $drainTimeoutSeconds
        pollIntervalMilliseconds = $drainPollIntervalMilliseconds
        pollCount = $pollSnapshots.Count
        appEvidenceCompleteCaseCount = $appCompleteCaseIds.Count
        appEvidenceIncompleteCaseIds = @($missingAppCaseIds)
        completeCaseCount = @($caseReports | Where-Object { $_.bundleComplete }).Count
        incompleteCaseIds = @($incompleteBundleIds)
        status = if ($allBundleComplete) { 'complete' } else { 'incomplete' }
        startedAt = $drainStartedAt.ToString('o')
        finishedAt = $drainFinishedAt.ToString('o')
        pollSnapshots = @($pollSnapshots)
        pullErrors = @($pullErrors)
        cases = @($caseReports)
        deadlineExceeded = [bool]$drainDeadlineExceeded
        requiredEvidenceContract = [ordered]@{
            semanticSettleTimeout = 'screenshots not-applicable; metadata/operation/runtime/summary/logcat/video remain required'
            invariantOrVisualViolation = 'retained C4 before/violation/after screenshots required; missing files are incomplete'
            missingOrEmptyRequired = 'no empty-file or fallback substitution is accepted'
        }
    }
    $drainReport | ConvertTo-Json -Depth 16 |
        Set-Content -LiteralPath (Join-Path $reportDir 'evidence-drain.json') -Encoding utf8
    $hostDrainValidation = Test-C6EvidenceDrain `
        -Directory $reportDir `
        -ExpectedCaseIds @($expectedCaseIds)
    $drainReport['hostValidation'] = [ordered]@{
        mode = 'independent-host-recheck'
        complete = [bool]$hostDrainValidation.complete
        status = [string]$hostDrainValidation.status
        errors = @($hostDrainValidation.errors)
    }
    if (-not [bool]$hostDrainValidation.complete) {
        $drainReport['status'] = 'incomplete'
    }
    $drainReport | ConvertTo-Json -Depth 16 |
        Set-Content -LiteralPath (Join-Path $reportDir 'evidence-drain.json') -Encoding utf8
    if (-not $allBundleComplete) {
        Write-Warning (
            'C6 evidence bundle drain 未完成：complete={0}/{1} timeout={2}s' -f
            @($caseReports | Where-Object { $_.bundleComplete }).Count, $caseReports.Count, $drainTimeoutSeconds
        )
    }
    return $drainReport
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
    $supplementalScreenshot = Join-Path $reportDir 'failure-screenshot-post-detection.png'
    try {
        Invoke-Adb @('-s', $DeviceId, 'shell', 'screencap', '-p', $remoteScreenshot) | Out-Null
        # This image is supplemental post-detection context.  It is never
        # promoted to the C6 retained before/violation/after contract, but it
        # must use the same staging/leaf/copy transport rule as every other
        # adb-pulled file so a destination collision cannot look successful.
        Copy-C6RemoteFileViaStaging `
            -RemoteFile $remoteScreenshot `
            -DestinationPath $supplementalScreenshot `
            -TimeoutSeconds 5 | Out-Null
        Invoke-Adb @('-s', $DeviceId, 'shell', 'rm', '-f', $remoteScreenshot) | Out-Null
    }
    catch {
        Write-Warning "保存 failure screenshot 失敗：$($_.Exception.Message)"
    }

    $failureVideo = Capture-C6FailureVideo
    $null = Export-C6EvidenceBundles -FailureVideoPath $failureVideo
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
$maxAllowedTimeoutSeconds = if ($Scenario -eq 'continuous') {
    600
}
elseif ($Scenario -eq 'visual-oracle') {
    300
}
elseif ($Scenario -eq 'correctness-subset') {
    300
}
else {
    3600
}
if ($effectiveTimeoutSeconds -gt $maxAllowedTimeoutSeconds) {
    throw "workload timeout $effectiveTimeoutSeconds 秒超過 runner 上限 $maxAllowedTimeoutSeconds 秒。"
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
$driverResponsePath = if ([string]::IsNullOrWhiteSpace($DriverResponsePathOverride)) {
    Join-Path $repoRoot 'build/integration_response_data.json'
}
else {
    [System.IO.Path]::GetFullPath($DriverResponsePathOverride)
}
$driverResponseArtifactPath = $null
$driverOutputPath = $null
$driverExitCode = $null
$driverTimedOut = $false
$driverOutput = ''
$performanceAssessment = $null
$c6ScreenshotEnvironmentConfigured = $false
$evidenceCaptureError = $null

try {
    $emulators = Invoke-Captured 'flutter' @('emulators')
    $devices = Invoke-Adb @('devices', '-l')
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
    Invoke-Adb @('-s', $DeviceId, 'root') | ForEach-Object { Write-Host $_ }
    Start-Sleep -Milliseconds 1000

    # Clear before pushing: pm clear also removes the app-specific external
    # directory used as the deterministic fixture destination.
    Write-Host '清除 app data（在 fixture push 前）。'
    $installedPackagePath = @()
    try {
        $installedPackagePath = Invoke-Adb @('-s', $DeviceId, 'shell', 'pm', 'path', $packageName)
    }
    catch {
        Write-Warning "查詢已安裝 package path 失敗，視為尚未安裝：$($_.Exception.Message)"
    }
    $packageInstalled = ($installedPackagePath -match '^package:')
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
        Invoke-AdbBounded @('-s', $DeviceId, 'install', '-r', '-d', $normalApkPath) |
            ForEach-Object { Write-Host $_ }
        Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'start', '-W', '-n', $activityName) |
            ForEach-Object { Write-Host $_ }
        Start-Sleep -Milliseconds 1500
        Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
    }

    Write-Host "推送 fixture：$fixtureHostPath -> $FixtureDevicePath"
    $fixtureDirectory = $FixtureDevicePath.Substring(0, $FixtureDevicePath.LastIndexOf('/'))
    Invoke-Adb @('-s', $DeviceId, 'shell', 'mkdir', '-p', $fixtureDirectory) | Out-Null
    Invoke-AdbBounded @('-s', $DeviceId, 'push', $fixture.Path, $FixtureDevicePath) | ForEach-Object { Write-Host $_ }
    $fixtureSize = (Get-Item -LiteralPath $fixture.Path).Length
    Set-AppExternalFixtureOwnership $fixtureDirectory
    Push-C6InputFiles

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
            $buildArguments += "--dart-define=NIGHT_READER_MONKEY_ENABLE_INVARIANTS=$($EnableInvariantHook.IsPresent.ToString().ToLowerInvariant())"
        }
        if ($Scenario -eq 'continuous') {
            $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_SEED=$Seed"
            $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_ITERATIONS=$Iterations"
            $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_DURATION_SECONDS=$DurationSeconds"
            $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_ENABLE_INVARIANTS=$($EnableInvariantHook.IsPresent.ToString().ToLowerInvariant())"
            $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_SIMPLE_CONTROL=$($SimpleScrollControl.IsPresent.ToString().ToLowerInvariant())"
            $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_CAPTURE_SETTLED_SCREENSHOTS=$($CaptureSettledScreenshots.IsPresent.ToString().ToLowerInvariant())"
            if ($BuildMode -eq 'debug') {
                # Debug continuous is semantic/invariant evidence only; do not
                # let the app's strict timing assertion turn it into a perf run.
                $buildArguments += '--dart-define=NIGHT_READER_CONTINUOUS_ENFORCE_FRAME_P99=false'
            }
            if (-not [string]::IsNullOrWhiteSpace($Action)) {
                $buildArguments += "--dart-define=NIGHT_READER_CONTINUOUS_ACTION=$Action"
            }
        }
        if ($Scenario -eq 'correctness-subset') {
            $buildArguments += "--dart-define=NIGHT_READER_C6_CASE_ID=$CaseId"
            $buildArguments += "--dart-define=NIGHT_READER_C6_CASE_LIST_PATH=$c6ManifestDevicePath"
            $buildArguments += "--dart-define=NIGHT_READER_C6_DEVICE_ID=$DeviceId"
            $buildArguments += "--dart-define=NIGHT_READER_C6_CAPTURE_GOLDEN=$($CaptureGolden.IsPresent.ToString().ToLowerInvariant())"
            $buildArguments += "--dart-define=NIGHT_READER_C6_CAPTURE_FAILURE_SCREENSHOTS=$($true.ToString().ToLowerInvariant())"
            # C6 correctness is only valid when both app-side observation hooks
            # are actually enabled.  Persist the same fact in root/case
            # provenance so an outer batch flag cannot report hook-off.
            $buildArguments += '--dart-define=NIGHT_READER_C6_INVARIANT_HOOK=true'
            $buildArguments += '--dart-define=NIGHT_READER_C6_VISUAL_ORACLE=true'
        }
        Invoke-Captured 'flutter' $buildArguments | ForEach-Object { Write-Host $_ }
    }
    finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $workloadApkPath)) {
        throw "找不到 integration workload APK：$workloadApkPath"
    }

    if ($Scenario -eq 'continuous') {
        # Continuous measurements use Flutter's supported driver path. The
        # driver builds and launches the target itself so the integration-test
        # VM-service route remains intact. Because flutter drive can uninstall
        # the package before installing its freshly built APK, a short-lived
        # watcher re-pushes the app-specific fixture after install and before
        # the test harness imports it.
        if (Test-Path -LiteralPath $driverResponsePath) {
            Remove-Item -LiteralPath $driverResponsePath -Force
        }
        Invoke-Adb @('-s', $DeviceId, 'logcat', '-c') | Out-Null
        $startLog = Get-WorkloadLogcat
        $lastWorkloadLog = $startLog
        Initialize-SystemHealthBaseline `
            -Source 'driver-workload-start' `
            -DeviceId $DeviceId | Out-Null
        $startSample = Capture-PerformanceSnapshot `
            -Name 'sample-000-start' `
            -ElapsedSeconds 0 `
            -WorkloadLog $startLog
        if ($null -ne $startSample) { $sampleCount += 1 }

        $workloadStartedAt = Get-Date
        $driverArguments = @(
            'drive', "--$BuildMode",
            '--driver=test_driver/integration_test.dart',
            "--target=$testTarget",
            '-d', $DeviceId,
            '--no-dds',
            '--timeout', [string]$effectiveTimeoutSeconds,
            "--dart-define=NIGHT_READER_FIXTURE_PATH=$FixtureDevicePath",
            "--dart-define=NIGHT_READER_FIXTURE_HOST_PATH=$fixtureHostPath",
            "--dart-define=NIGHT_READER_CONTINUOUS_SEED=$Seed",
            "--dart-define=NIGHT_READER_CONTINUOUS_ITERATIONS=$Iterations",
            "--dart-define=NIGHT_READER_CONTINUOUS_DURATION_SECONDS=$DurationSeconds",
            "--dart-define=NIGHT_READER_CONTINUOUS_ENABLE_INVARIANTS=$($EnableInvariantHook.IsPresent.ToString().ToLowerInvariant())",
            "--dart-define=NIGHT_READER_CONTINUOUS_SIMPLE_CONTROL=$($SimpleScrollControl.IsPresent.ToString().ToLowerInvariant())",
            "--dart-define=NIGHT_READER_CONTINUOUS_CAPTURE_SETTLED_SCREENSHOTS=$($CaptureSettledScreenshots.IsPresent.ToString().ToLowerInvariant())"
        )
        if ($BuildMode -eq 'debug') {
            $driverArguments += '--dart-define=NIGHT_READER_CONTINUOUS_ENFORCE_FRAME_P99=false'
        }
        if (-not [string]::IsNullOrWhiteSpace($Action)) {
            $driverArguments += "--dart-define=NIGHT_READER_CONTINUOUS_ACTION=$Action"
        }
        Write-Host "執行 Flutter driver workload：flutter $($driverArguments -join ' ')"
        $testApkInstalled = $true
        # flutter drive owns the profile/debug test APK install and does not
        # expose a build-number option. Remove the restored normal APK first so
        # its default integration version code cannot be rejected as a
        # downgrade; the watcher will re-push the fixture after replacement.
        try {
            Invoke-Adb @('-s', $DeviceId, 'shell', 'pm', 'uninstall', $packageName) |
                ForEach-Object { Write-Host $_ }
        }
        catch {
            Write-Warning "移除 driver 目標 package 前置步驟失敗：$($_.Exception.Message)"
        }
        $flutterExecutable = (Get-Command flutter -ErrorAction Stop).Path
        if ([string]::IsNullOrWhiteSpace($flutterExecutable)) {
            throw '找不到可執行的 flutter path，無法啟動 driver。'
        }
        $driverInitialVersionCode = Get-InstalledVersionCode
        $fixtureWatcherState = @{
            pushed = $false
            sawPackageMissing = $false
            workloadPackageReplaced = $false
            lastProgressProbeAt = (Get-Date).AddSeconds(-10)
            lastSystemHealthProbeAt = (Get-Date).AddSeconds(-10)
            lastProgressAt = Get-Date
            lastCompletedActions = -1
            lastProgressReportAt = (Get-Date).AddSeconds(-10)
        }
        $fixtureWatcher = {
            $now = Get-Date
            if (($now - $fixtureWatcherState.lastSystemHealthProbeAt).TotalSeconds -ge 3) {
                $fixtureWatcherState.lastSystemHealthProbeAt = $now
                Invoke-SystemHealthSentinel `
                    -Source 'driver-watcher' `
                    -DeviceId $DeviceId `
                    -PackageName $packageName | Out-Null
            }
            $installedPath = @()
            try {
                $installedPath = Invoke-Adb @('-s', $DeviceId, 'shell', 'pm', 'path', $packageName) 10
            }
            catch {
                $installedPath = @()
            }
            if ($installedPath -notmatch '^package:') {
                $fixtureWatcherState.sawPackageMissing = $true
            }
            else {
                $installedVersionCode = Get-InstalledVersionCode
                if ($installedVersionCode -ne $driverInitialVersionCode) {
                    # pm uninstall/install can replace the package between two
                    # 250ms polls. Version-code change is the durable signal
                    # that flutter drive has installed the workload APK.
                    $fixtureWatcherState.workloadPackageReplaced = $true
                }
            }

            if (-not $fixtureWatcherState.pushed -and
                ($fixtureWatcherState.sawPackageMissing -or
                 $fixtureWatcherState.workloadPackageReplaced)) {
                try {
                    Invoke-Adb @('-s', $DeviceId, 'shell', 'mkdir', '-p', $fixtureDirectory) | Out-Null
                    Invoke-AdbBounded @('-s', $DeviceId, 'push', $fixture.Path, $FixtureDevicePath) | Out-Null
                    Set-AppExternalFixtureOwnership $fixtureDirectory
                    $fixtureWatcherState.pushed = $true
                    Write-Host 'flutter drive 安裝 workload APK 後已重新推送 fixture。'
                }
                catch {
                    # Retry while the package manager finishes the install.
                    Write-Host "fixture watcher retry: $($_.Exception.Message)"
                }
            }

            if (($now - $fixtureWatcherState.lastProgressProbeAt).TotalSeconds -lt 2) {
                return
            }
            $fixtureWatcherState.lastProgressProbeAt = $now
            $progressLog = Get-WorkloadLogcat
            $progress = Get-WorkloadProgress $progressLog
            if ($null -ne $progress.completedActions -and
                $progress.completedActions -ne $fixtureWatcherState.lastCompletedActions) {
                $fixtureWatcherState.lastCompletedActions = $progress.completedActions
                $fixtureWatcherState.lastProgressAt = $now
                if (($now - $fixtureWatcherState.lastProgressReportAt).TotalSeconds -ge 2) {
                    Write-Host "watchdog progress actions=$($progress.completedActions)"
                    $fixtureWatcherState.lastProgressReportAt = $now
                }
            }

            if ($fixtureWatcherState.workloadPackageReplaced -and
                (Get-AndroidPid) -ne $null -and
                ($now - $fixtureWatcherState.lastProgressAt).TotalSeconds -ge 120) {
                throw 'workload no-progress watchdog：package 已替換且 process 存在，但 120 秒沒有新的 action marker。'
            }
        }
        if ($CaptureSettledScreenshots) {
            New-Item -ItemType Directory -Path $screenshotDir -Force | Out-Null
            $env:NIGHT_READER_SCREENSHOT_DIR = $screenshotDir
        }
        try {
            $driverRun = Invoke-ProcessWithTimeout `
                -FilePath $flutterExecutable `
                -Arguments $driverArguments `
                -TimeoutSeconds $effectiveTimeoutSeconds `
                -WhileRunning $fixtureWatcher
        }
        finally {
            if ($null -eq $previousScreenshotDirectory) {
                Remove-Item Env:NIGHT_READER_SCREENSHOT_DIR -ErrorAction SilentlyContinue
            }
            else {
                $env:NIGHT_READER_SCREENSHOT_DIR = $previousScreenshotDirectory
            }
        }
        $driverExitCode = $driverRun.exitCode
        $driverTimedOut = [bool]$driverRun.timedOut
        $driverOutput = "$($driverRun.stdout)`n$($driverRun.stderr)"
        $driverOutputPath = Write-ReportFile 'driver-output.txt' $driverOutput
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
        $endElapsedSeconds = [int]([Math]::Floor(
            ($workloadFinishedAt - $workloadStartedAt).TotalSeconds
        ))
        $endSample = Capture-PerformanceSnapshot `
            -Name 'end' `
            -ElapsedSeconds $endElapsedSeconds `
            -WorkloadLog $finalFilteredLog
        if ($null -ne $endSample) { $sampleCount += 1 }

        $response = $null
        if (Test-Path -LiteralPath $driverResponsePath -PathType Leaf) {
            $driverResponseArtifactPath = Join-Path $reportDir 'driver-response-data.json'
            Copy-Item -LiteralPath $driverResponsePath `
                -Destination $driverResponseArtifactPath -Force
            try {
                $response = Get-Content -Raw -LiteralPath $driverResponsePath |
                    ConvertFrom-Json
            }
            catch {
                Write-Warning "解析 driver JSON 失敗：$($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "找不到 driver response JSON：$driverResponsePath"
        }
        $surfaceFlingerText = (Invoke-Adb @(
            '-s', $DeviceId, 'shell', 'dumpsys', 'SurfaceFlinger'
        )) -join [Environment]::NewLine
        $performanceAssessment = Test-ContinuousMeasurement `
            -Response $response `
            -SurfaceFlingerText $surfaceFlingerText `
            -DriverExitCode $driverExitCode `
            -DriverTimedOut $driverTimedOut `
            -DriverOutput $driverOutput `
            -InvariantHookEnabled $EnableInvariantHook.IsPresent `
            -BuildMode $BuildMode `
            -ExpectedSeed $Seed `
            -ExpectedAction $Action
        if ($performanceAssessment.status -eq 'invalid') {
            throw "Android continuous workload INVALID：$($performanceAssessment.invalidReasons -join '；')"
        }
        if ($performanceAssessment.status -eq 'failed') {
            throw "Android continuous workload performance failed：frame P99 gate or test failed。"
        }
        if ($BuildMode -ne 'profile') {
            Write-Host 'Android continuous driver workload observed（debug；未作效能判定）。'
        }
        elseif ($EnableInvariantHook) {
            Write-Host 'Android continuous driver workload observed（invariant hook enabled；未作效能判定）。'
        }
        else {
            Write-Host 'Android continuous driver workload 通過。'
        }
    }
    else {
        Write-Host '清除 app data 並安裝 workload APK。'
        Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
        Invoke-AdbBounded @('-s', $DeviceId, 'install', '-r', '-d', $workloadApkPath) | ForEach-Object { Write-Host $_ }
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
        Invoke-AdbBounded @('-s', $DeviceId, 'push', $fixture.Path, $FixtureDevicePath) |
            ForEach-Object { Write-Host $_ }
        Set-AppExternalFixtureOwnership $fixtureDirectory
        Push-C6InputFiles
        Invoke-Adb @('-s', $DeviceId, 'logcat', '-c') | Out-Null
        Initialize-SystemHealthBaseline `
            -Source 'direct-workload-start' `
            -DeviceId $DeviceId | Out-Null
        if ($Scenario -eq 'correctness-subset') {
            New-Item -ItemType Directory -Path $screenshotDir -Force | Out-Null
            $env:NIGHT_READER_SCREENSHOT_DIR = $screenshotDir
            $c6ScreenshotEnvironmentConfigured = $true
        }
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
    $lastProgressAt = $workloadStartedAt
    $lastObservedCompletedActions = -1
    $lastFixtureWatchAt = $workloadStartedAt.AddSeconds(-10)
    $lastSystemHealthProbeAt = $workloadStartedAt.AddSeconds(-10)
    $fixtureWatcherPushed = $false
    $passed = $false
    $failure = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 1000
        $now = Get-Date
        $log = Get-WorkloadLogcat
        $lastWorkloadLog = $log
        if (($now - $lastSystemHealthProbeAt).TotalSeconds -ge 3) {
            $lastSystemHealthProbeAt = $now
            Invoke-SystemHealthSentinel `
                -Source 'direct-loop' `
                -DeviceId $DeviceId `
                -PackageName $packageName | Out-Null
        }
        # Direct debug workloads do not go through flutter drive's process
        # supervisor, so keep the same finite fixture watcher and 120-second
        # no-progress watchdog used by the driver path.
        if (($now - $lastFixtureWatchAt).TotalSeconds -ge 2) {
            $lastFixtureWatchAt = $now
            $fixturePresent = $true
            try {
                Invoke-Adb @('-s', $DeviceId, 'shell', 'test', '-f', $FixtureDevicePath) 10 | Out-Null
            }
            catch {
                $fixturePresent = $false
            }
            if (-not $fixturePresent) {
                try {
                    Write-Host "fixture watcher：檔案遺失，重新推送 $FixtureDevicePath"
                    Invoke-Adb @('-s', $DeviceId, 'shell', 'mkdir', '-p', $fixtureDirectory) | Out-Null
                    Invoke-AdbBounded @('-s', $DeviceId, 'push', $fixture.Path, $FixtureDevicePath) | ForEach-Object { Write-Host $_ }
                    Set-AppExternalFixtureOwnership $fixtureDirectory
                    $fixtureWatcherPushed = $true
                }
                catch {
                    Write-Host "fixture watcher retry：$($_.Exception.Message)"
                }
            }
        }
        $progress = Get-WorkloadProgress $log
        $progressSignal = if ($Scenario -eq 'correctness-subset') {
            if ($null -ne $progress.completedCases -or
                ($null -ne $progress.c6ProgressMarkers -and
                 $progress.c6ProgressMarkers -gt 0)) {
                'cases={0};sixDimensionMarkers={1}' -f `
                    $progress.completedCases, $progress.c6ProgressMarkers
            }
            else { $null }
        }
        elseif ($null -ne $progress.completedActions) {
            [string]$progress.completedActions
        }
        else { $null }
        if ($null -ne $progressSignal -and
            $progressSignal -ne $lastObservedCompletedActions) {
            $lastObservedCompletedActions = $progressSignal
            $lastProgressAt = $now
            Write-Host "watchdog progress $progressSignal"
        }
        if (($now - $lastProgressAt).TotalSeconds -ge 120 -and
            $null -ne (Get-AndroidPid)) {
            $failure = 'workload no-progress watchdog：process 存在，但 120 秒沒有新的 case 或六面向 progress marker。'
            break
        }
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
        if ($log -match 'READER_(E2E|MONKEY|CONTINUOUS)_RESULT status=passed' -or
            $log -match 'READER_C6_RESULT .*"status":"passed"') {
            $passed = $true
            break
        }
        $failurePattern = 'READER_(E2E|MONKEY|CONTINUOUS|C6)_(?:CASE_)?(FAILURE|ANOMALY|WATCHDOG_ABORT)|READER_C6_RESULT[^\r\n]*"status":"failed"|Some tests failed|FATAL EXCEPTION|ANR in|SIGSEGV|SIGABRT|Null check operator used on a null value|Unhandled exception'
        if ($log -match $failurePattern) {
            $failure = ($log -split "`r?`n" | Where-Object {
                $_ -match $failurePattern
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
    if ($Scenario -eq 'correctness-subset' -and $passed) {
        # Success evidence is exported before the app-owned external tree is
        # removed during normal APK restoration.  The same exporter is used
        # for failure bundles so success and failure traces have identical
        # per-case schemas; no failure video is created on this path.
        $evidenceDrain = Export-C6EvidenceBundles -FailureVideoPath $null
        if ($null -eq $evidenceDrain -or $evidenceDrain.status -ne 'complete') {
            throw 'C6 evidence bundle transport incomplete；拒絕把缺少的 required evidence 當成 pass。'
        }
    }
    if (-not $passed) {
        if ($null -eq $failure) {
            $failure = "在 $effectiveTimeoutSeconds 秒內沒有看到 workload passed marker。"
        }
        throw "Android $Scenario workload 失敗：$failure"
    }
    Write-Host "Android $Scenario workload 通過。"
    }
}
catch {
    # Keep the original exception text stable when the final reporting path
    # runs under PowerShell's ErrorRecord/remote-output handling.  Storing the
    # exception string also prevents a secondary null-valued method failure
    # from hiding the actual workload failure.
    $testError = $_.Exception.ToString()
    try {
        Capture-FailureArtifacts
    }
    catch {
        # Evidence capture is secondary to the original workload failure. Keep
        # its structured error for the root metadata and let the final
        # fail-closed drain validation reject any incomplete bundle; never let
        # a second transport exception erase the first failure.
        $evidenceCaptureError = $_.Exception.ToString()
        Write-Warning "C6 failure evidence capture 失敗：$evidenceCaptureError"
    }
}
finally {
    $finishedAt = Get-Date
    $workloadProgress = Get-WorkloadProgress $lastWorkloadLog
    $c6HookObserved = $false
    $c6HookObservationError = $null
    if ($Scenario -eq 'correctness-subset') {
        $hookMarkerMatch = [regex]::Match(
            [string]$lastWorkloadLog,
            'READER_C6_HOOK_PROVENANCE\s+(\{[^\r\n]*\})'
        )
        if (-not $hookMarkerMatch.Success) {
            $c6HookObservationError = 'structured READER_C6_HOOK_PROVENANCE marker was not observed'
        }
        else {
            try {
                $hookMarker = $hookMarkerMatch.Groups[1].Value | ConvertFrom-Json
                $hookInvariant = Get-ResponseProperty $hookMarker 'invariantHookEnabled'
                $hookVisualOracle = Get-ResponseProperty $hookMarker 'visualOracleEnabled'
                $hookProvenance = [string](Get-ResponseProperty $hookMarker 'hookProvenance')
                $hookMode = [string](Get-ResponseProperty $hookMarker 'hookMode')
                $hookSource = [string](Get-ResponseProperty $hookMarker 'hookSource')
                $c6HookObserved =
                    $hookInvariant -is [bool] -and [bool]$hookInvariant -and
                    $hookVisualOracle -is [bool] -and [bool]$hookVisualOracle -and
                    $hookProvenance -ceq 'c6-correctness-integration-hook-on' -and
                    $hookMode -ceq 'correctness-hook-on' -and
                    $hookSource -ceq 'integration_test/reader_correctness_android_subset_test.dart'
                if (-not $c6HookObserved) {
                    $c6HookObservationError = 'structured hook marker fields did not prove both C6 hooks were enabled'
                }
            }
            catch {
                $c6HookObservationError = "structured hook marker was not valid JSON: $($_.Exception.Message)"
            }
        }
    }
    $c6RootInvariantHookEnabled = if ($Scenario -eq 'correctness-subset') {
        [bool]$c6HookObserved
    }
    else {
        $EnableInvariantHook.IsPresent
    }
    $c6RootVisualOracleEnabled = if ($Scenario -eq 'correctness-subset') {
        [bool]$c6HookObserved
    }
    else {
        $false
    }
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
        status = if ($null -eq $testError -and $null -eq $restoreError) { 'passed' } else { 'failed' }
        seed = $Seed
        requestedIterations = $Iterations
        requestedDurationSeconds = $DurationSeconds
        invariantHookEnabled = $c6RootInvariantHookEnabled
        visualOracleEnabled = $c6RootVisualOracleEnabled
        hookProvenance = if ($c6HookObserved) { 'c6-correctness-integration-hook-on' } else { $null }
        hookMode = if ($c6HookObserved) { 'correctness-hook-on' } else { $null }
        hookSource = if ($c6HookObserved) {
            'integration_test/reader_correctness_android_subset_test.dart'
        }
        else { $null }
        hookObservation = if ($Scenario -eq 'correctness-subset') {
            if ($c6HookObserved) { 'app-marker-observed' } else { 'not-observed' }
        }
        else { 'not-applicable' }
        hookObservationError = $c6HookObservationError
        captureSettledScreenshots = $CaptureSettledScreenshots.IsPresent
        screenshotDirectory = if ($CaptureSettledScreenshots) { $screenshotDir } else { $null }
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
        completedCases = $workloadProgress.completedCases
        c6ProgressMarkers = $workloadProgress.c6ProgressMarkers
        c6FailureMarkers = $workloadProgress.c6FailureMarkers
        lastActions = $workloadProgress.lastActions
        caseId = if ($Scenario -eq 'correctness-subset') { $CaseId } else { $null }
        caseListHostPath = if ($Scenario -eq 'correctness-subset') {
            if (-not [string]::IsNullOrWhiteSpace($CaseList)) { $CaseList } else { $c6ManifestHostPath }
        } else { $null }
        caseListDevicePath = if ($Scenario -eq 'correctness-subset') { $c6ManifestDevicePath } else { $null }
        c6EvidenceDevicePath = if ($Scenario -eq 'correctness-subset') { $c6EvidenceDevicePath } else { $null }
        c6ScreenshotDirectory = if ($Scenario -eq 'correctness-subset') { $screenshotDir } else { $null }
        performance = if ($null -ne $performanceAssessment) {
            $performanceAssessment
        }
        else {
            $workloadProgress.performance
        }
        driverResponsePath = $driverResponseArtifactPath
        driverOutputPath = $driverOutputPath
        driverExitCode = $driverExitCode
        driverTimedOut = $driverTimedOut
        failureClassification = $script:failureClassification
        systemHealthPath = if (Test-Path -LiteralPath $script:systemHealthPath -PathType Leaf) {
            $script:systemHealthPath
        }
        else { $null }
        systemHealthObservationCount = [int]$script:systemHealthObservationCount
        systemHealthFirstFailure = $script:systemHealthFirstFailureObservation
        effectiveBuildNumber = $effectiveBuildNumber
        testError = if ($null -ne $testError) { $testError.ToString() } else { $null }
        evidenceCaptureError = if ($null -ne $evidenceCaptureError) {
            $evidenceCaptureError.ToString()
        }
        else { $null }
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

    if ($c6ScreenshotEnvironmentConfigured) {
        if ($null -eq $previousScreenshotDirectory) {
            Remove-Item Env:NIGHT_READER_SCREENSHOT_DIR -ErrorAction SilentlyContinue
        }
        else {
            $env:NIGHT_READER_SCREENSHOT_DIR = $previousScreenshotDirectory
        }
    }

    $metadata.restoreError = if ($null -ne $restoreError) { $restoreError.ToString() } else { $null }
    $metadata.status = if ($null -eq $testError -and $null -eq $restoreError) { 'passed' } else { 'failed' }
    $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportDir 'metadata.json') -Encoding utf8

    if ($Scenario -eq 'correctness-subset') {
        $finalExpectedCaseIds = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($CaseList) -and
            (Test-Path -LiteralPath $CaseList -PathType Leaf)) {
            try {
                $finalCaseList = Get-Content -Raw -LiteralPath $CaseList | ConvertFrom-Json
                foreach ($case in @($finalCaseList.cases)) {
                    $finalCaseId = [string](Get-ResponseProperty $case 'caseId')
                    if (-not [string]::IsNullOrWhiteSpace($finalCaseId) -and
                        -not $finalExpectedCaseIds.Contains($finalCaseId)) {
                        $finalExpectedCaseIds.Add($finalCaseId)
                    }
                }
            }
            catch {
                Write-Warning "C6 final case-list parse 失敗：$($_.Exception.Message)"
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($CaseId) -and
            -not $finalExpectedCaseIds.Contains($CaseId)) {
            $finalExpectedCaseIds.Add($CaseId)
        }
        $finalDrainValidation = $null
        try {
            $finalDrainValidation = Test-C6EvidenceDrain `
                -Directory $reportDir `
                -ExpectedCaseIds @($finalExpectedCaseIds) `
                -RequireRootProvenance
        }
        catch {
            $finalDrainValidation = [ordered]@{
                complete = $false
                status = 'validator-error'
                errors = @($_.Exception.ToString())
            }
        }
        $metadata['finalEvidenceDrainComplete'] = [bool]$finalDrainValidation.complete
        $metadata['finalEvidenceDrainErrors'] = @($finalDrainValidation.errors)
        if (-not [bool]$finalDrainValidation.complete) {
            $finalDrainError = 'C6 final root/evidence validation incomplete: ' +
                (@($finalDrainValidation.errors) -join '; ')
            if ($null -eq $testError) {
                $testError = $finalDrainError
            }
            $metadata.status = 'failed'
            $metadata.testError = $testError.ToString()
        }
        $finalDrainPath = Join-Path $reportDir 'evidence-drain.json'
        if (Test-Path -LiteralPath $finalDrainPath -PathType Leaf) {
            try {
                $finalDrainReport = Get-Content -Raw -LiteralPath $finalDrainPath |
                    ConvertFrom-Json
                $finalDrainReport | Add-Member -Force -MemberType NoteProperty `
                    -Name finalRootValidation -Value ([ordered]@{
                        mode = 'final-root-provenance-recheck'
                        complete = [bool]$finalDrainValidation.complete
                        status = [string]$finalDrainValidation.status
                        errors = @($finalDrainValidation.errors)
                    })
                if (-not [bool]$finalDrainValidation.complete) {
                    $finalDrainReport.status = 'incomplete'
                }
                $finalDrainReport | ConvertTo-Json -Depth 20 |
                    Set-Content -LiteralPath $finalDrainPath -Encoding utf8
            }
            catch {
                Write-Warning "C6 final evidence-drain annotation 失敗：$($_.Exception.Message)"
            }
        }
        $metadata | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $reportDir 'metadata.json') -Encoding utf8
    }
    Remove-Item -LiteralPath $backupApkPath -Force -ErrorAction SilentlyContinue
}

if ($null -ne $testError) { Write-Error ([string]$testError) }
if ($null -ne $restoreError) { Write-Error "恢復一般 debug APK 失敗：$restoreError" }
if ($null -ne $testError -and $null -ne $restoreError) { exit 3 }
if ($null -ne $restoreError) { exit 2 }
if ($null -ne $testError) { exit 1 }
exit 0
