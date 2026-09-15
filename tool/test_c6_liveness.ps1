[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$runnerPath = Join-Path $PSScriptRoot 'run_android_reader_workload.ps1'
$runnerSource = Get-Content -Raw -LiteralPath $runnerPath
$parseErrors = $null
$tokens = $null
$runnerAst = [System.Management.Automation.Language.Parser]::ParseInput(
    $runnerSource,
    [ref]$tokens,
    [ref]$parseErrors
)
Assert-True (@($parseErrors).Count -eq 0) 'runner must parse before liveness checks'

function Get-FunctionText([string]$Name) {
    $functionAst = $runnerAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $Name
        }, $true)
    Assert-True ($null -ne $functionAst) "runner must define $Name"
    return $functionAst.Extent.Text
}

$adbBoundedText = Get-FunctionText 'Invoke-AdbBounded'
$androidPidText = Get-FunctionText 'Get-AndroidPid'
$logcatText = Get-FunctionText 'Get-Logcat'
$workloadLogcatText = Get-FunctionText 'Get-WorkloadLogcat'
$processText = Get-FunctionText 'Invoke-ProcessWithTimeout'

# These are source-contract checks for the paths that must stay finite even
# when ADB or a child process stops responding.
Assert-True ($runnerSource.Contains('function Invoke-AdbBoundedResult')) 'ADB result helper must expose timeout/exit semantics'
Assert-True ($adbBoundedText -notmatch '\.WaitForExit\(\)') 'ADB cleanup must not use an unbounded WaitForExit()'
Assert-True ($processText -notmatch '\.WaitForExit\(\)') 'process cleanup must not use an unbounded WaitForExit()'
Assert-True (([regex]::Matches($runnerSource, '(?im)^\s*Invoke-Captured\s+[''"]adb[''"]')).Count -eq 0) 'runner must not invoke adb through unbounded Invoke-Captured'
Assert-True ($runnerSource -notmatch '(?m)\.WaitForExit\(\)') 'runner must not use an unbounded WaitForExit() anywhere'
Assert-True ($runnerSource.Contains('function Parse-SystemHealthObservation')) 'system-health parser must exist'
Assert-True ($runnerSource.Contains('function Get-SystemHealthProbe')) 'system-health probe must exist'
Assert-True ($runnerSource.Contains('function Invoke-SystemHealthSentinel')) 'system-health sentinel must exist'
Assert-True ($runnerSource.Contains('system-health.json')) 'system-health artifact path must exist'
Assert-True ($runnerSource.Contains('failureClassification')) 'root metadata must record failure classification'
$baselineCallTexts = @(
    $runnerAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Initialize-SystemHealthBaseline'
        }, $true) | ForEach-Object { $_.Extent.Text }
)
Assert-True (($baselineCallTexts -match "driver-workload-start").Count -eq 1) 'driver path must initialize a workload-start system-health baseline'
Assert-True (($baselineCallTexts -match "direct-workload-start").Count -eq 1) 'direct path must initialize a workload-start system-health baseline'
$sentinelCallTexts = @(
    $runnerAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Invoke-SystemHealthSentinel'
        }, $true) | ForEach-Object { $_.Extent.Text }
)
Assert-True (($sentinelCallTexts -match "driver-watcher").Count -eq 1) 'driver watcher must invoke the system-health sentinel'
Assert-True (($sentinelCallTexts -match "direct-loop").Count -eq 1) 'direct loop must invoke the system-health sentinel'
Assert-True (([regex]::Matches($runnerSource, 'lastSystemHealthProbeAt')).Count -ge 3) 'both monitoring paths must rate-limit system-health probes'
Assert-True ($runnerSource.Contains("'-b', 'events'")) 'baseline/probe must inspect the events logcat buffer'
Assert-True ($runnerSource.Contains('$stdoutTask.Wait(3000)')) 'ADB output draining must have bounded cleanup'
Assert-True ($logcatText -match 'Invoke-AdbBounded') 'full logcat must use bounded ADB execution'
Assert-True ($workloadLogcatText -match 'Invoke-AdbBounded') 'filtered logcat must use bounded ADB execution'
Assert-True ($logcatText -notmatch 'Invoke-Captured') 'full logcat must not bypass the ADB timeout'
Assert-True ($workloadLogcatText -notmatch 'Invoke-Captured') 'filtered logcat must not bypass the ADB timeout'
Assert-True ($androidPidText -notmatch 'catch\s*\{\s*return \$null\s*\}') 'PID transport errors must not become process-absent'
Assert-True (([regex]::Matches($runnerSource, '\$drainDeadline')).Count -ge 3) 'drain deadline must be checked at case/file boundaries'
Assert-True (([regex]::Matches($processText, 'Get-Date\) -ge \$deadline')).Count -ge 2) 'supervisor must check its deadline before and after the callback'

# Semantic system-health checks use the runner's parsed function bodies with
# deterministic inputs.  They keep the parser's classification contract
# executable without starting an Android workload or changing the production
# release gate.
foreach ($functionName in @(
        'Get-SystemHealthField',
        'Get-SystemHealthPid',
        'Get-SystemHealthLineIdentity',
        'Get-SystemHealthNewLines',
        'Parse-SystemHealthObservation',
        'Write-SystemHealthArtifact',
        'Record-SystemHealthObservation'
    )) {
    . ([scriptblock]::Create((Get-FunctionText $functionName)))
}
$script:systemHealthPath = ''
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
function Assert-SystemHealthSemantic([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "SYSTEM HEALTH ASSERT FAILED: $Message" }
}
$semanticBase = @{
    Source = 'liveness-semantic-test'
    DeviceId = 'emulator-5556'
    PackageName = 'com.inkpage.reader.debug'
    Timestamp = '2026-09-15T00:00:00.0000000+08:00'
    AdbState = 'device'
    BootCompleted = '1'
    SystemServerPidText = '123'
    SystemUiPidText = '456'
    SystemUiPidStatus = 'available'
    WindowDump = 'mCurrentFocus=Window{123 u0 com.inkpage.reader.debug/com.inkpage.reader.MainActivity}'
    ActivityDump = 'mResumedActivity: ActivityRecord{123 u0 com.inkpage.reader.debug/.MainActivity}'
    BaselineMode = 'bounded-snapshot-timestamp-fingerprint'
    BaselineCapturedAt = '2026-09-15T00:00:00.0000000+08:00'
    BaselineLimitations = @('bounded test baseline')
}
$healthyObservation = Parse-SystemHealthObservation @semanticBase
Assert-SystemHealthSemantic ([bool]$healthyObservation.healthy) 'healthy probe must be healthy'
Assert-SystemHealthSemantic ([string]$healthyObservation.classification -ceq 'healthy') 'healthy probe classification'
Assert-SystemHealthSemantic ([bool]$healthyObservation.foreground.readerForeground) 'reader foreground must be true'

$optionalSystemUi = $semanticBase.Clone()
$optionalSystemUi.SystemUiPidText = ''
$optionalSystemUi.SystemUiPidStatus = 'available'
$optionalObservation = Parse-SystemHealthObservation @optionalSystemUi
Assert-SystemHealthSemantic ([bool]$optionalObservation.healthy) 'missing SystemUI PID is optional when otherwise healthy'
Assert-SystemHealthSemantic (
    [string]$optionalObservation.processes.systemUiPidStatus -ceq 'optional/unavailable'
) 'missing SystemUI PID must be recorded as optional/unavailable'

function Get-SystemHealthSemanticAnr([string]$Text) {
    $arguments = $semanticBase.Clone()
    $arguments.AnrSources = @([ordered]@{ source = 'events'; text = $Text })
    return Parse-SystemHealthObservation @arguments
}
$systemDialogObservation = Get-SystemHealthSemanticAnr 'Application Not Responding: Process System is not responding'
Assert-SystemHealthSemantic (
    [string]$systemDialogObservation.classification -ceq 'environment_invalid'
) 'system dialog must be environment_invalid'
Assert-SystemHealthSemantic (@($systemDialogObservation.anr.system).Count -eq 1) 'system dialog must classify as system'
Assert-SystemHealthSemantic (
    [string]$systemDialogObservation.anr.system[0].source -ceq 'events'
) 'system dialog must retain events source'
$systemUiDialogObservation = Get-SystemHealthSemanticAnr 'Application Not Responding: com.android.systemui'
Assert-SystemHealthSemantic (
    [string]$systemUiDialogObservation.classification -ceq 'environment_invalid'
) 'SystemUI dialog must be environment_invalid'
Assert-SystemHealthSemantic (@($systemUiDialogObservation.anr.systemui).Count -eq 1) 'SystemUI dialog must classify as systemui'
$systemAmAnrObservation = Get-SystemHealthSemanticAnr 'am_anr: [0,123,system_server,reason]'
Assert-SystemHealthSemantic (@($systemAmAnrObservation.anr.system).Count -eq 1) 'system am_anr must classify as system'
$systemUiAmAnrObservation = Get-SystemHealthSemanticAnr 'am_anr: [0,123,com.android.systemui,reason]'
Assert-SystemHealthSemantic (@($systemUiAmAnrObservation.anr.systemui).Count -eq 1) 'SystemUI am_anr must classify as systemui'
$readerAnrObservation = Get-SystemHealthSemanticAnr 'ANR in com.inkpage.reader.debug'
Assert-SystemHealthSemantic (
    [string]$readerAnrObservation.classification -ceq 'app_workload_failure'
) 'Reader app ANR must be app_workload_failure'
Assert-SystemHealthSemantic (@($readerAnrObservation.anr.readerApp).Count -eq 1) 'Reader app ANR must classify as reader/app'
$unknownAnrObservation = Get-SystemHealthSemanticAnr 'ANR in com.example.unknown'
Assert-SystemHealthSemantic (
    [string]$unknownAnrObservation.classification -ceq 'unknown_anr'
) 'unknown ANR must fail closed as unknown_anr'
Assert-SystemHealthSemantic (-not [bool]$unknownAnrObservation.healthy) 'unknown ANR must not be healthy'

$missingBaseline = $semanticBase.Clone()
$missingBaseline.BaselineMode = ''
$missingBaselineObservation = Parse-SystemHealthObservation @missingBaseline
Assert-SystemHealthSemantic (
    [string]$missingBaselineObservation.classification -ceq 'environment_invalid'
) 'missing old baseline must be environment_invalid'
$transportError = $semanticBase.Clone()
$transportError.ProbeErrors = @('adb state probe failed: device offline')
$transportObservation = Parse-SystemHealthObservation @transportError
Assert-SystemHealthSemantic (-not [bool]$transportObservation.healthy) 'transport error must not be healthy'
Assert-SystemHealthSemantic (
    [string]$transportObservation.classification -ceq 'environment_invalid'
) 'transport error must be environment_invalid'

$initialRecord = Record-SystemHealthObservation (Parse-SystemHealthObservation @semanticBase)
Assert-SystemHealthSemantic ([bool]$initialRecord.foreground.readerForeground) 'initial reader foreground record'
Assert-SystemHealthSemantic ($null -eq $initialRecord.foreground.transition) 'initial foreground has no transition'
$temporaryForeground = $semanticBase.Clone()
$temporaryForeground.WindowDump = 'mCurrentFocus=Window{123 u0 com.android.systemui/com.android.systemui.SystemUIService}'
$temporaryForeground.ActivityDump = 'mResumedActivity: ActivityRecord{123 u0 com.android.systemui/.SystemUIService}'
$temporaryRecord = Record-SystemHealthObservation (
    Parse-SystemHealthObservation @temporaryForeground
)
Assert-SystemHealthSemantic ($null -ne $temporaryRecord.foreground.transition) 'temporary foreground transition must be recorded'
Assert-SystemHealthSemantic (
    [bool]$temporaryRecord.foreground.transition.fromReaderForeground
) 'transition must start from Reader'
Assert-SystemHealthSemantic (
    -not [bool]$temporaryRecord.foreground.transition.toReaderForeground
) 'transition must leave Reader'
Assert-SystemHealthSemantic (
    -not [bool]$temporaryRecord.foreground.graceExceeded
) 'temporary transition must remain within grace window'
$restoredRecord = Record-SystemHealthObservation (
    Parse-SystemHealthObservation @semanticBase
)
Assert-SystemHealthSemantic ($null -ne $restoredRecord.foreground.transition) 'return foreground transition must be recorded'
Assert-SystemHealthSemantic (
    -not [bool]$restoredRecord.foreground.transition.fromReaderForeground
) 'return transition must start outside Reader'
Assert-SystemHealthSemantic (
    [bool]$restoredRecord.foreground.transition.toReaderForeground
) 'return transition must reach Reader'

# A record already present at workload start must not be rediscovered on the
# first probe.  A later record at a newer epoch timestamp must remain visible.
$oldAnrText = '100.000  123  456 I am_anr: [0,123,system_server,old-record]'
$newAnrText = '101.000  123  456 I am_anr: [0,123,system_server,new-record]'
$oldIdentity = Get-SystemHealthLineIdentity $oldAnrText
$delta = Get-SystemHealthNewLines `
    -Snapshot ([ordered]@{
        records = @(
            [ordered]@{ timestamp = 100.0; identity = $oldIdentity; text = $oldAnrText }
            [ordered]@{ timestamp = 101.0; identity = (Get-SystemHealthLineIdentity $newAnrText); text = $newAnrText }
        )
    }) `
    -BaselineBuffer ([ordered]@{
        lineIdentities = @($oldIdentity)
        maxTimestamp = 100.0
    })
Assert-SystemHealthSemantic (@($delta.records).Count -eq 1) 'old ANR baseline record must be ignored'
Assert-SystemHealthSemantic (
    [string]$delta.records[0].text -ceq $newAnrText
) 'new ANR after the baseline must be retained'

# Once a foreground transition exceeds its bounded grace period, the
# observation must become an environment failure instead of remaining healthy.
$script:systemHealthForegroundState.notReaderSince = (Get-Date).AddSeconds(-20)
$graceExceededRecord = Record-SystemHealthObservation (
    Parse-SystemHealthObservation @temporaryForeground
)
Assert-SystemHealthSemantic (
    [string]$graceExceededRecord.classification -ceq 'environment_invalid'
) 'foreground grace expiry must fail closed as environment_invalid'
Assert-SystemHealthSemantic (
    -not [bool]$graceExceededRecord.healthy
) 'foreground grace expiry must not remain healthy'
Write-Host 'C6 system-health semantic checks passed.'

# Fake/stub PID results prove present, absent, and transport-error semantics
# without requiring a live device or changing the production gate.
$script:DeviceId = 'fake-device'
$script:packageName = 'fake.package'
$script:pidProbeMode = 'present'
$effectiveTimeoutAst = $runnerAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Get-EffectiveAdbTimeoutSeconds'
    }, $true)
Assert-True ($null -ne $effectiveTimeoutAst) 'effective ADB timeout helper must exist'
. ([scriptblock]::Create($effectiveTimeoutAst.Extent.Text))
function Invoke-AdbBoundedResult {
    param([string[]]$Arguments, [int]$TimeoutSeconds = 30)
    switch ($script:pidProbeMode) {
        'present' { return [pscustomobject]@{ timedOut = $false; exitCode = 0; stdout = "1234`n"; stderr = '' } }
        'absent' { return [pscustomobject]@{ timedOut = $false; exitCode = 1; stdout = ''; stderr = '' } }
        'transport-error' { return [pscustomobject]@{ timedOut = $false; exitCode = 1; stdout = ''; stderr = 'device offline' } }
        'timeout' { return [pscustomobject]@{ timedOut = $true; exitCode = $null; stdout = ''; stderr = 'bounded timeout' } }
    }
}
$pidFunctionAst = $runnerAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Get-AndroidPid'
    }, $true)
. ([scriptblock]::Create($pidFunctionAst.Extent.Text))
$script:pidProbeMode = 'present'
Assert-True ((Get-AndroidPid) -eq 1234) 'present PID must be returned'
$script:pidProbeMode = 'absent'
Assert-True ($null -eq (Get-AndroidPid)) 'clean no-PID result must remain absent'
foreach ($mode in @('transport-error', 'timeout')) {
    $script:pidProbeMode = $mode
    $threw = $false
    try { Get-AndroidPid } catch { $threw = $true }
    Assert-True $threw "$mode must remain an explicit transport failure"
}

# A fake sleeping child proves supervisor timeout cleanup returns promptly.
$processFunctionAst = $runnerAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Invoke-ProcessWithTimeout'
    }, $true)
. ([scriptblock]::Create($processFunctionAst.Extent.Text))
$startedAt = Get-Date
$processResult = Invoke-ProcessWithTimeout `
    -FilePath 'pwsh' `
    -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10') `
    -TimeoutSeconds 1 `
    -WhileRunning $null
$elapsedSeconds = ((Get-Date) - $startedAt).TotalSeconds
Assert-True ([bool]$processResult.timedOut) 'sleeping child must time out'
Assert-True ($elapsedSeconds -lt 5) "timeout cleanup must be bounded; elapsed=$elapsedSeconds"

Write-Host 'C6 liveness fake/stub tests passed.'
