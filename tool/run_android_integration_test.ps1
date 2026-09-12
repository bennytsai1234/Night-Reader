[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [int]$BuildNumber = 2178,

    [ValidateRange(15, 900)]
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageName = 'com.inkpage.reader.debug'
$activityName = "$packageName/com.inkpage.reader.MainActivity"
$apkPath = Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-debug.apk'
$backupApkPath = Join-Path ([System.IO.Path]::GetTempPath()) (
    "night-reader-debug-{0}.apk" -f [Guid]::NewGuid()
)

function Assert-Command([string]$Name) {
    if ($null -eq (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "找不到命令 $Name，請先把 Flutter 與 Android Platform Tools 加入 PATH。"
    }
}

function Invoke-Checked([string]$FilePath, [string[]]$Arguments) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath $($Arguments -join ' ') 失敗，exit code=$LASTEXITCODE。"
    }
}

function Invoke-Adb([string[]]$Arguments) {
    $output = & adb @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb $($Arguments -join ' ') 失敗，exit code=$LASTEXITCODE：$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Invoke-AdbInstallWithTimeout([string]$ApkFilePath) {
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $arguments = @('-s', $DeviceId, 'install', '-r', $ApkFilePath)
        $process = Start-Process `
            -FilePath 'adb' `
            -ArgumentList $arguments `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -PassThru `
            -WindowStyle Hidden
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            throw "adb install 超過 $TimeoutSeconds 秒；請確認 Android 裝置上的安裝確認頁已完成。"
        }
        $process.WaitForExit()
        $output = @()
        if (Test-Path -LiteralPath $stdoutPath) {
            $output += @(Get-Content -LiteralPath $stdoutPath)
        }
        if (Test-Path -LiteralPath $stderrPath) {
            $output += @(Get-Content -LiteralPath $stderrPath)
        }
        if ($process.ExitCode -ne 0) {
            throw "adb install 失敗，exit code=$($process.ExitCode)：$($output -join [Environment]::NewLine)"
        }
        return @($output)
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
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

function Get-AndroidPid {
    $output = & adb -s $DeviceId shell pidof -s $packageName 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    foreach ($line in @($output)) {
        if ([string]$line -match '(\d+)') {
            return [int]$Matches[1]
        }
    }
    return $null
}

function Wait-ForAndroidPid([int]$WaitSeconds = 15) {
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $processId = Get-AndroidPid
        if ($null -ne $processId) { return $processId }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

function Start-NightReader([switch]$TestLaunch) {
    $arguments = @('-s', $DeviceId, 'shell', 'am', 'start', '-W', '-n', $activityName)
    if ($TestLaunch) {
        $arguments += @(
            '--ez', 'test-flag', 'true',
            '--ez', 'disable-service-auth-codes', 'true',
            '--ez', 'disable-service-origin-check', 'true'
        )
    }
    $output = Invoke-Adb $arguments
    $text = $output -join [Environment]::NewLine
    # `am start -W` can report `Status: timeout` on a cold Flutter debug
    # engine even though the Activity and process were started successfully.
    # The caller performs the authoritative foreground/Ready-log checks, so a
    # timeout is recoverable; only an explicit start error remains fatal.
    $hasStartStatus = $text -match '(?im)^\s*Status:\s*(ok|timeout)\s*$'
    $hasExpectedActivity = $text -match [regex]::Escape("Activity: $activityName")
    if ($text -match '(?i)Error:|Error type|Security exception' -or
        -not $hasStartStatus -or -not $hasExpectedActivity) {
        throw "Night Reader Activity 啟動失敗：$text"
    }
    if ($text -match '(?im)^\s*Status:\s*timeout\s*$') {
        Write-Warning 'am start -W 等待超時；繼續用 process、前景 Activity 與 Ready log 驗證。'
    }
    return @($output)
}

function Assert-NightReaderForeground {
    $dump = Invoke-Adb @('-s', $DeviceId, 'shell', 'dumpsys', 'activity', 'activities')
    $top = $dump | Where-Object { $_ -match 'topResumedActivity' } | Select-Object -First 1
    if ($null -eq $top -or $top -notmatch [regex]::Escape($activityName)) {
        throw "Night Reader 沒有位於前景；目前 topResumedActivity：$top"
    }
}

function Get-DeviceLog {
    $output = & adb -s $DeviceId logcat -d -v brief -s `
        flutter:I `
        AndroidRuntime:E `
        ActivityManager:E `
        ActivityTaskManager:E `
        DEBUG:E `
        libc:F 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "無法讀取裝置 logcat，exit code=$LASTEXITCODE。"
    }
    return ($output -join [Environment]::NewLine)
}

function Get-NightReaderFailureLine([string]$Log, [int]$ProcessId) {
    $pidPattern = "\(\s*$ProcessId\s*\)"
    $packagePattern = [regex]::Escape($packageName)
    $markerPattern = 'Some tests failed|Test failed|FATAL EXCEPTION|ANR in|SIGSEGV|Null check operator used on a null value|Unhandled exception'
    return ($Log -split "`r?`n" | Where-Object {
        $_ -match $markerPattern -and
        (($_ -match $pidPattern) -or ($_ -match $packagePattern))
    } | Select-Object -Last 1)
}

function Wait-ForNormalReady([int]$WaitSeconds = 30) {
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $log = Get-DeviceLog
        if ($log -match '夜讀 Ready to Run') {
            Assert-NightReaderForeground
            return
        }
        $failure = Get-NightReaderFailureLine -Log $log -ProcessId 0
        if ($null -ne $failure) {
            throw "一般 debug 啟動失敗：$failure"
        }
        Start-Sleep -Milliseconds 500
    }
    throw "一般 debug APK 在 $WaitSeconds 秒內沒有出現『夜讀 Ready to Run』。"
}

Assert-Command 'adb'
Assert-Command 'flutter'

$testError = $null
$restoreError = $null
$testApkInstalled = $false
$backupCreated = $false
$effectiveBuildNumber = $BuildNumber

try {
    $state = Invoke-Adb @('-s', $DeviceId, 'get-state')
    if (($state -join "`n") -notmatch '(?m)^\s*device\s*$') {
        throw "裝置 $DeviceId 沒有以 device 狀態連線；請先執行 adb connect 或確認手機的無線偵錯。"
    }

    $installedBuildNumber = Get-InstalledVersionCode
    $effectiveBuildNumber = [Math]::Max($BuildNumber, $installedBuildNumber + 1)
    Write-Host "使用 Android versionCode=$effectiveBuildNumber（目前裝置版本碼=$installedBuildNumber）。"

    Write-Host '先建置一般 debug APK 並建立 restore backup...'
    Push-Location $repoRoot
    try {
        Invoke-Checked 'flutter' @('build', 'apk', '--debug', "--build-number=$effectiveBuildNumber")
    }
    finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "找不到一般 debug APK：$apkPath"
    }
    Copy-Item -LiteralPath $apkPath -Destination $backupApkPath -Force
    $backupCreated = $true

    Write-Host '建置 integration_test APK（會暫時覆寫 app-debug.apk）...'
    Push-Location $repoRoot
    try {
        Invoke-Checked 'flutter' @(
            'build', 'apk', '--debug',
            '--target=integration_test/app_boot_test.dart',
            "--build-number=$effectiveBuildNumber"
        )
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "找不到測試 APK：$apkPath"
    }

    Write-Host '停止舊的 debug process，安裝測試 APK...'
    Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
    $installOutput = Invoke-AdbInstallWithTimeout -ApkFilePath $apkPath
    $installOutput | ForEach-Object { Write-Host $_ }
    if (($installOutput -join "`n") -notmatch '(?m)^\s*Success\s*$') {
        throw '測試 APK 安裝沒有同時取得 adb exit code 0 與 Success。請確認 Android 裝置上的安裝確認頁已完成。'
    }
    $testApkInstalled = $true

    Write-Host '清除舊 log 並啟動測試 APK；runner 以 process PID 與裝置端 log 驗證結果。'
    Invoke-Adb @('-s', $DeviceId, 'logcat', '-c') | Out-Null
    Start-NightReader -TestLaunch | ForEach-Object { Write-Host $_ }
    Assert-NightReaderForeground
    $testPid = Wait-ForAndroidPid
    if ($null -eq $testPid) {
        throw '測試 APK 啟動後沒有取得 Night Reader process PID。'
    }
    Write-Host "測試 process PID=$testPid。"

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $passed = $false
    $failureLine = $null
    $passedPattern = "\(\s*$testPid\s*\).*All tests passed!"
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 1000
        $log = Get-DeviceLog
        if ($log -match $passedPattern) {
            $passed = $true
            break
        }
        $failureLine = Get-NightReaderFailureLine -Log $log -ProcessId $testPid
        if ($null -ne $failureLine) {
            break
        }
        if ($null -eq (Get-AndroidPid)) {
            $failureLine = '測試 process 在回報結果前消失。'
            break
        }
    }

    if (-not $passed) {
        if ($null -ne $failureLine) {
            throw "裝置端整合測試失敗：$failureLine"
        }
        throw "裝置端整合測試在 $TimeoutSeconds 秒內沒有看到本次 process 的 All tests passed!。"
    }
    Write-Host '裝置端 integration_test 通過：All tests passed!'
}
catch {
    $testError = $_
}
finally {
    if ($testApkInstalled) {
        try {
            Invoke-Adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $packageName) | Out-Null
            if (-not $backupCreated) {
                throw '沒有可用的測試前一般 debug APK backup，無法安全 restore。'
            }

            Write-Host '恢復一般 debug APK...'
            $restoreBuildSucceeded = $false
            try {
                Push-Location $repoRoot
                try {
                    Invoke-Checked 'flutter' @('build', 'apk', '--debug', "--build-number=$effectiveBuildNumber")
                }
                finally {
                    Pop-Location
                }
                $restoreBuildSucceeded = Test-Path -LiteralPath $apkPath
            }
            catch {
                Write-Warning "一般 debug APK 重建失敗，改用測試前 backup：$($_.Exception.Message)"
            }
            if (-not $restoreBuildSucceeded) {
                Copy-Item -LiteralPath $backupApkPath -Destination $apkPath -Force
            }

            $restoreOutput = Invoke-AdbInstallWithTimeout -ApkFilePath $apkPath
            $restoreOutput | ForEach-Object { Write-Host $_ }
            if (($restoreOutput -join "`n") -notmatch '(?m)^\s*Success\s*$') {
                throw '一般 debug APK 安裝沒有同時取得 adb exit code 0 與 Success。'
            }

            Invoke-Adb @('-s', $DeviceId, 'logcat', '-c') | Out-Null
            Start-NightReader | ForEach-Object { Write-Host $_ }
            Assert-NightReaderForeground
            Wait-ForNormalReady
            Write-Host '手機已恢復到一般 debug 版，且已驗證前景 Activity 與 Ready log。'
        }
        catch {
            $restoreError = $_
        }
    }
}

if ($null -ne $testError) {
    Write-Error $testError
}
if ($null -ne $restoreError) {
    Write-Error "恢復一般 debug APK 失敗：$restoreError"
}
if ($null -ne $testError -and $null -ne $restoreError) { exit 3 }
if ($null -ne $restoreError) { exit 2 }
if ($null -ne $testError) { exit 1 }
exit 0
