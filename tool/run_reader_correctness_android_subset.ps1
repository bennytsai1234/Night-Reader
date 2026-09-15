[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [int]$Seed = 9132051,

    # 'smoke' 是預設的 C6 lane：每個 operation 一個代表 case、不跑 mixed
    # journey，維度覆蓋與舊的 acceptance lane 相同（36 ops / 10 positions /
    # 12 states / 3 race phases），但兩 seed 各 58 cases 而非 279。
    # 'acceptance' 保留 279-case 的原始選取，只為重現既有 evidence 與其
    # subset hash，不再是驗收門。
    [ValidateSet('smoke', 'acceptance')]
    [string]$Lane = 'smoke',

    [string]$ManifestHostPath = '',

    [string]$HostFailureCaseList = '',

    [string]$ReportRoot = '',

    # Resume only from a previously recorded, complete prefix.  The resumed
    # run always writes a new report root so an invalid attempt is preserved
    # and cannot be mistaken for the replacement batch.
    [ValidateRange(0, 10000)]
    [int]$StartBatchIndex = 0,

    # Optional bounded prefix execution.  The index is exclusive: with
    # StartBatchIndex=5 and StopAfterBatchIndex=10, only batches 5..9 run.
    # The resulting aggregate is deliberately non-acceptance and fail-closed;
    # it exists only as a durable exact prefix for a later continuation.
    [ValidateRange(-1, 10000)]
    [int]$StopAfterBatchIndex = -1,

    [string]$ResumeFromReportRoot = '',

    # Explicitly allow carrying a complete prefix into a different planner
    # budget only after the target and source case-list files are compared
    # entry-for-entry. This is used for the bounded 36-op -> 20-op fallback;
    # an incomplete or duration-triggering batch is never part of the prefix.
    [switch]$AllowCompatiblePrefixResume,

    # An interrupted parent planner may have finished individual batches but
    # not reached its final aggregate write.  This explicit mode reconstructs
    # only a complete prefix from the batch case-list, metadata, app result
    # marker, and durable case summaries.  It never treats an incomplete batch
    # as a carried result; the source root is preserved and the reconstructed
    # evidence is written to the new root.
    [switch]$AllowArtifactPrefixResume,

    # The underlying workload runner still accepts at most 60 iterations and
    # 300 seconds.  C6 cases have a wide settled/reload cost, however, so a
    # 60-case C6 batch is not a safe duration plan: final-r7/batch-000 reached
    # the five-minute test timeout after 45/60 cases.  Keep the planner's
    # default and caller-selectable budget conservative while leaving the
    # underlying runner's 60/300 guardrail unchanged.
    [ValidateRange(1, 20)]
    [int]$MaxCasesPerBatch = 20,

    [ValidateRange(1, 36)]
    [int]$MaxEstimatedOperationsPerBatch = 20,

    # Keep the existing deterministic prefix batch boundaries, then apply a
    # smaller budget to the remaining cases.  This is an explicit continuation
    # plan for a duration fallback; it never treats the fallback batch as a
    # passed result and never changes the underlying runner limits.
    [ValidateRange(-1, 10000)]
    [int]$RemainderFromBatchIndex = -1,

    [ValidateRange(1, 20)]
    [int]$RemainderMaxCasesPerBatch = 1,

    [ValidateRange(1, 36)]
    [int]$RemainderMaxEstimatedOperationsPerBatch = 36,

    # A bounded, non-acceptance pilot. It selects the highest operation-count
    # cases from the complete deterministic subset, records their exact ids,
    # and never changes the full 279-case plan.
    [ValidateRange(3, 4)]
    [int]$PilotCaseCount = 3,

    [switch]$PilotOnly,

    [switch]$CaptureGolden,

    [switch]$DryRun
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'C6 Android subset runner must run under PowerShell 7: use pwsh -NoProfile.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$c6EvidenceModulePath = Join-Path $repoRoot 'tool/c6_evidence_bundle.psm1'
Import-Module -Name $c6EvidenceModulePath -Force
$manifestPath = if ([string]::IsNullOrWhiteSpace($ManifestHostPath)) {
    Join-Path $repoRoot "docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-$Seed.json"
}
else {
    [System.IO.Path]::GetFullPath($ManifestHostPath)
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "找不到 C5 manifest：$manifestPath"
}
$failurePath = if ([string]::IsNullOrWhiteSpace($HostFailureCaseList)) {
    $null
}
else {
    [System.IO.Path]::GetFullPath($HostFailureCaseList)
}
if ($null -ne $failurePath -and -not (Test-Path -LiteralPath $failurePath -PathType Leaf)) {
    throw "找不到 host failure case list：$failurePath"
}
$reportRoot = if ([string]::IsNullOrWhiteSpace($ReportRoot)) {
    Join-Path $repoRoot "artifacts/android-reader/c6-subset-seed-$Seed-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
else {
    [System.IO.Path]::GetFullPath($ReportRoot)
}
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null

$hasResumeSource = -not [string]::IsNullOrWhiteSpace($ResumeFromReportRoot)
$resumeSourceRoot = ''
if ($hasResumeSource) {
    $resumeSourceRoot = [System.IO.Path]::GetFullPath($ResumeFromReportRoot)
}
if ($StartBatchIndex -gt 0 -and -not $hasResumeSource) {
    throw 'StartBatchIndex > 0 requires ResumeFromReportRoot; use a new ReportRoot to preserve the prior attempt.'
}
if ($StartBatchIndex -eq 0 -and $hasResumeSource) {
    throw 'ResumeFromReportRoot requires StartBatchIndex > 0; refusing an ambiguous resume.'
}
if ($hasResumeSource -and -not (Test-Path -LiteralPath $resumeSourceRoot -PathType Container)) {
    throw "找不到續跑來源 report root：$resumeSourceRoot"
}
if ($PilotOnly -and ($StartBatchIndex -gt 0 -or $hasResumeSource)) {
    throw 'PilotOnly 不可與 resume prefix 混用；pilot 必須使用新的 report root 並明確標示為非 acceptance。'
}
if ($StopAfterBatchIndex -ge 0 -and $StopAfterBatchIndex -le $StartBatchIndex) {
    throw "StopAfterBatchIndex=$StopAfterBatchIndex 必須大於 StartBatchIndex=$StartBatchIndex。"
}
if ($PilotOnly -and $StopAfterBatchIndex -ge 0) {
    throw 'PilotOnly 不可與 bounded prefix stop 混用。'
}
if ($PilotOnly -and $PilotCaseCount -gt $MaxCasesPerBatch) {
    throw "PilotCaseCount=$PilotCaseCount 超過 MaxCasesPerBatch=$MaxCasesPerBatch；拒絕產生超出 planner budget 的 pilot。"
}
if ($PilotOnly -and $RemainderFromBatchIndex -ge 0) {
    throw 'PilotOnly 不可與 remainder plan 混用；pilot 必須使用單一明確 budget。'
}
if ($RemainderFromBatchIndex -eq 0) {
    throw 'RemainderFromBatchIndex=0 不保留任何原 planner prefix；請使用一般 MaxCasesPerBatch budget。'
}

$subsetPath = Join-Path $reportRoot "subset-seed-$Seed-$Lane.json"
$coveragePath = Join-Path $reportRoot "subset-coverage-seed-$Seed-$Lane.json"
$generateArguments = @(
    'run', 'tool/generate_reader_correctness_android_subset.dart',
    '--manifest', $manifestPath,
    '--lane', $Lane,
    '--output', $subsetPath,
    '--summary', $coveragePath
)
if ($null -ne $failurePath) {
    $generateArguments += @('--host-failures', $failurePath)
}
& dart @generateArguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$subset = Get-Content -Raw -LiteralPath $subsetPath | ConvertFrom-Json
$allCases = @($subset.cases)
if ($allCases.Count -eq 0) { throw 'C6 subset generator produced zero cases; refusing to run.' }

# This is a planner safety limit, not a relaxation of the workload runner's
# 60-iteration/300-second ceiling.  The C6 Dart harness owns case semantics;
# the PowerShell layer only counts manifest entries and operation ids to keep
# each finite batch well below the observed timeout boundary. The accelerated
# plan uses 4 cases / 36 operation ids; the legacy 20/20 default remains
# available for compatibility. Neither setting changes the underlying
# workload's 60-iteration/300-second guardrail.
$durationFallbackThresholdSeconds = 280
$c6PlannerSafety = [ordered]@{
    maxCasesPerBatch = $MaxCasesPerBatch
    maxEstimatedOperationsPerBatch = $MaxEstimatedOperationsPerBatch
    runnerIterationsLimit = 60
    runnerTimeoutSeconds = 300
    durationFallbackThresholdSeconds = $durationFallbackThresholdSeconds
    observedOversizedBatch = [ordered]@{
        artifact = 'artifacts/android-reader/c6-subset-seed-9132051-final-r7/batch-000'
        requestedCases = 60
        completedCases = 45
        workloadDurationSeconds = 297.7628288
        outcome = 'failed_or_invalid'
        reason = 'flutter test TimeoutException after 0:05:00; no final aggregate marker'
    }
        policy = 'C6 planner keeps the full subset in the plan and never silently truncates it; callers may use the explicit bounded 4-case/36-operation pilot or the legacy 20-case/20-operation default, while the underlying runner remains capped at 60 iterations and 300 seconds.'
}

function New-C6Batches {
    param(
        [object[]]$Cases,
        [int]$CasesPerBatch,
        [int]$OperationsPerBatch
    )

    $result = [System.Collections.Generic.List[object]]::new()
    $current = [System.Collections.Generic.List[object]]::new()
    $estimatedOperations = 0
    foreach ($case in $Cases) {
        # This is only a bounded duration estimate. The operation semantics
        # stay in Dart; the batch layer does not interpret or recreate an
        # action.
        $operationCount = @($case.operationIds).Count
        if ($operationCount -gt $OperationsPerBatch) {
            throw "Case $($case.caseId) has $operationCount operation ids, exceeding MaxEstimatedOperationsPerBatch=$OperationsPerBatch; refusing an oversized batch."
        }
        $wouldExceed = $current.Count -ge $CasesPerBatch -or
            ($current.Count -gt 0 -and
             ($estimatedOperations + $operationCount) -gt $OperationsPerBatch)
        if ($wouldExceed) {
            $result.Add([pscustomobject]@{
                index = $result.Count
                cases = @($current)
                estimatedOperations = $estimatedOperations
            })
            $current = [System.Collections.Generic.List[object]]::new()
            $estimatedOperations = 0
        }
        $current.Add($case)
        $estimatedOperations += $operationCount
    }
    if ($current.Count -gt 0) {
        $result.Add([pscustomobject]@{
            index = $result.Count
            cases = @($current)
            estimatedOperations = $estimatedOperations
        })
    }
    return @($result)
}

$baseBatches = @(New-C6Batches `
        -Cases $allCases `
        -CasesPerBatch $MaxCasesPerBatch `
        -OperationsPerBatch $MaxEstimatedOperationsPerBatch)
$batches = [System.Collections.Generic.List[object]]::new()
$remainderPlan = $null
if ($RemainderFromBatchIndex -ge 0) {
    if ($RemainderFromBatchIndex -ge $baseBatches.Count) {
        throw "RemainderFromBatchIndex=$RemainderFromBatchIndex 超過 base batch count=$($baseBatches.Count)。"
    }
    $prefixBatches = @($baseBatches[0..($RemainderFromBatchIndex - 1)])
    $prefixCaseCount = [int](
        ($prefixBatches | ForEach-Object { $_.cases.Count } |
            Measure-Object -Sum).Sum
    )
    $remainderCases = @($allCases[$prefixCaseCount..($allCases.Count - 1)])
    $remainderBatches = @(New-C6Batches `
            -Cases $remainderCases `
            -CasesPerBatch $RemainderMaxCasesPerBatch `
            -OperationsPerBatch $RemainderMaxEstimatedOperationsPerBatch)
    foreach ($batch in $prefixBatches + $remainderBatches) {
        $batches.Add([pscustomobject]@{
            index = $batches.Count
            cases = @($batch.cases)
            estimatedOperations = $batch.estimatedOperations
        })
    }
    $remainderPlan = [ordered]@{
        fromBatchIndex = $RemainderFromBatchIndex
        prefixCaseCount = $prefixCaseCount
        prefixMaxCasesPerBatch = $MaxCasesPerBatch
        prefixMaxEstimatedOperationsPerBatch = $MaxEstimatedOperationsPerBatch
        maxCasesPerBatch = $RemainderMaxCasesPerBatch
        maxEstimatedOperationsPerBatch = $RemainderMaxEstimatedOperationsPerBatch
        policy = 'The exact base-plan batches before fromBatchIndex are retained; only the deterministic suffix is repartitioned. Prefix validation remains case-list, seed, subset-hash, evidence, duration, and exit-code fail-closed.'
    }
}
else {
    foreach ($batch in $baseBatches) {
        $batches.Add($batch)
    }
}

$pilotRows = @()
$pilotSelection = @()
$executionBatches = @($batches)
if ($PilotOnly) {
    # This ranking is intentionally structural: only the already-declared
    # operation-id count is used. PowerShell does not decode or recreate case
    # semantics; the Dart case model remains the sole source of behavior.
    $pilotRows = @(
        $allCases |
            ForEach-Object {
                [pscustomobject]@{
                    case = $_
                    caseId = [string]$_.caseId
                    estimatedOperations = @($_.operationIds).Count
                }
            } |
            Sort-Object `
                @{ Expression = { $_.estimatedOperations }; Descending = $true }, `
                @{ Expression = { $_.caseId }; Descending = $false } |
            Select-Object -First $PilotCaseCount
    )
    $pilotSelection = @($pilotRows | ForEach-Object { $_.case })
    if ($pilotSelection.Count -ne $PilotCaseCount) {
        throw "Pilot selection produced $($pilotSelection.Count) cases; expected $PilotCaseCount."
    }
    $pilotOperationCount = [int](
        ($pilotRows | Measure-Object -Property estimatedOperations -Sum).Sum
    )
    if ($pilotOperationCount -gt $MaxEstimatedOperationsPerBatch) {
        throw "Pilot selection has $pilotOperationCount operation ids, exceeding MaxEstimatedOperationsPerBatch=$MaxEstimatedOperationsPerBatch."
    }
    $executionBatches = @(
        [pscustomobject]@{
            index = -1
            executionIndex = 0
            cases = @($pilotSelection)
            estimatedOperations = $pilotOperationCount
            source = 'pilot-highest-operation-count'
        }
    )
}

$plan = [ordered]@{
    seed = $Seed
    sourceManifest = $manifestPath
    subsetPath = $subsetPath
    subsetSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $subsetPath).Hash.ToLowerInvariant()
    totalCases = $allCases.Count
    batchCount = $batches.Count
    maxCasesPerBatch = $MaxCasesPerBatch
    maxEstimatedOperationsPerBatch = $MaxEstimatedOperationsPerBatch
    remainder = $remainderPlan
    executionScope = if ($PilotOnly) {
        'pilot-only-non-acceptance'
    }
    elseif ($StopAfterBatchIndex -ge 0) {
        'bounded-prefix-non-acceptance'
    }
    else { 'complete-subset' }
    pilot = if ($PilotOnly) {
        [ordered]@{
            caseCount = $pilotSelection.Count
            estimatedOperations = $pilotOperationCount
            selectionRule = 'Sort the complete deterministic subset by descending operationIds.Count, then ordinal caseId; select the first PilotCaseCount cases.'
            caseIds = @($pilotRows | ForEach-Object { $_.caseId })
            operationCounts = @($pilotRows | ForEach-Object { $_.estimatedOperations })
            acceptanceEligible = $false
            note = 'Pilot evidence chooses the next batch budget only; it is not a subset aggregate and cannot satisfy the 279-case acceptance.'
        }
    }
    else { $null }
    resume = [ordered]@{
        startBatchIndex = $StartBatchIndex
        stopAfterBatchIndex = $StopAfterBatchIndex
        sourceReportRoot = if ($hasResumeSource) { $resumeSourceRoot } else { $null }
        invalidAttemptsExcluded = $StartBatchIndex -gt 0
        allowCompatiblePrefixResume = $AllowCompatiblePrefixResume.IsPresent
        policy = 'Only complete batches before startBatchIndex may be carried into a new root; the source invalid/incomplete attempt is never copied or counted.'
    }
    plannerSafety = $c6PlannerSafety
    batches = @(
        foreach ($batch in $batches) {
            [ordered]@{
                index = $batch.index
                caseCount = $batch.cases.Count
                estimatedOperations = $batch.estimatedOperations
                firstCaseId = $batch.cases[0].caseId
                lastCaseId = $batch.cases[-1].caseId
            }
        }
    )
}
$planPath = Join-Path $reportRoot 'batch-plan.json'
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8
Write-Host ('C6_BATCH_PLAN ' + ($plan | ConvertTo-Json -Compress -Depth 8))

$overallExitCode = 0

function Get-C6NumericSum {
    param(
        [object]$Items,
        [string]$PropertyName
    )

    $sum = [double]0
    $found = $false
    # Enumerate both arrays and Generic.List instances.  Passing a
    # List[object] as object[] can otherwise leave the whole list as one item
    # in PowerShell and incorrectly produce a null aggregate total.
    foreach ($item in $Items) {
        if ($null -eq $item) { continue }
        # Newly-created batch results are [ordered] dictionaries, while
        # carried results from a resume source are PSCustomObjects.  A
        # dictionary key is not exposed through PSObject.Properties, so use
        # the IDictionary lookup first and retain the PSCustomObject path for
        # deserialized resume results and case summaries.
        $hasValue = $false
        $value = $null
        if ($item -is [System.Collections.IDictionary]) {
            if ($item.Contains($PropertyName)) {
                $hasValue = $true
                $value = $item[$PropertyName]
            }
        }
        else {
            $property = $item.PSObject.Properties[$PropertyName]
            if ($null -ne $property) {
                $hasValue = $true
                $value = $property.Value
            }
        }
        if (-not $hasValue -or $null -eq $value) {
            return $null
        }
        if ($value -isnot [ValueType]) {
            return $null
        }
        $sum += [double]$value
        $found = $true
    }
    if (-not $found) { return $null }
    return $sum
}

function Get-C6CaseSummaries {
    param([string]$Directory)

    # Export-C6EvidenceBundles keeps one host-side case directory and one
    # transport copy under c6-evidence-pulled.  Deduplicate by case id so the
    # aggregate never double-counts a bundle merely because it was pulled.
    $byCaseId = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -Recurse -Filter 'summary.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $summary = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
        }
        catch {
            continue
        }
        if ($null -eq $summary.caseId) { continue }
        if ($summary.status -notin @('passed', 'failed')) { continue }
        if (-not $byCaseId.ContainsKey([string]$summary.caseId)) {
            $byCaseId[[string]$summary.caseId] = $summary
        }
    }
    return @($byCaseId.Values)
}

function Get-C6FailureClassification {
    param(
        [object]$Metadata,
        [object[]]$CaseSummaries,
        [int]$ExitCode,
        [string]$RunnerInvocationError,
        [bool]$EvidenceDrainComplete = $true
    )

    $errorText = @(
        if ($null -ne $Metadata) { [string]$Metadata.testError }
        [string]$RunnerInvocationError
    ) -join "`n"
    $environmentPattern = '(?is)(adb\s+.*(?:超過 bounded timeout|失敗|Input/output error|Transport endpoint|device [^\r\n]*not found|offline)|Error type 3|Activity class .* does not exist|ActivityManagerService.*NullPointerException|pm clear .*NullPointerException)'
    if ($CaseSummaries.Count -eq 0 -and $errorText -match $environmentPattern) {
        return 'environment_invalid'
    }
    if (-not $EvidenceDrainComplete) {
        return 'evidence_transport_incomplete'
    }
    if ($ExitCode -ne 0 -or $CaseSummaries.Count -eq 0) {
        return 'runner_or_case_failure'
    }
    return 'not_failed'
}

function Get-C6ArtifactBatchResult {
    param(
        [string]$Directory,
        [object]$ExpectedBatch
    )

    $metadataPath = Join-Path $Directory 'metadata.json'
    $caseListPath = Join-Path $Directory 'case-list.json'
    $workloadLogPath = Join-Path $Directory 'workload-logcat.txt'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $caseListPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $workloadLogPath -PathType Leaf)) {
        throw "artifact prefix batch 缺少 metadata/case-list/workload-logcat：$Directory"
    }

    $metadata = Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json
    $caseList = Get-Content -Raw -LiteralPath $caseListPath | ConvertFrom-Json
    $workloadLog = Get-Content -Raw -LiteralPath $workloadLogPath
    $caseSummaries = @(Get-C6CaseSummaries -Directory $Directory)
    $expectedCaseIds = @($ExpectedBatch.cases | ForEach-Object { [string]$_.caseId })
    $evidenceDrainValidation = Test-C6EvidenceDrain `
        -Directory $Directory `
        -ExpectedCaseIds $expectedCaseIds `
        -RequireRootProvenance
    if (-not [bool]$evidenceDrainValidation.complete) {
        throw (
            'artifact prefix batch evidence-drain incomplete：batch={0} errors={1}' -f
            $ExpectedBatch.index,
            (@($evidenceDrainValidation.errors) -join '; ')
        )
    }
    $observedCaseIds = @($caseSummaries | ForEach-Object { [string]$_.caseId })
    $caseListIds = @($caseList.cases | ForEach-Object { [string]$_.caseId })
    if ($caseListIds.Count -ne $expectedCaseIds.Count) {
        throw "artifact prefix case-list count 不一致：batch=$($ExpectedBatch.index)"
    }
    for ($caseIndex = 0; $caseIndex -lt $expectedCaseIds.Count; $caseIndex++) {
        if ($caseListIds[$caseIndex] -cne $expectedCaseIds[$caseIndex]) {
            throw "artifact prefix case-list id 不一致：batch=$($ExpectedBatch.index) case=$caseIndex"
        }
    }

    $expectedCaseIdSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $observedCaseIdSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($caseId in $expectedCaseIds) { [void]$expectedCaseIdSet.Add($caseId) }
    foreach ($caseId in $observedCaseIds) { [void]$observedCaseIdSet.Add($caseId) }
    $caseIdsMatchExpected =
        $expectedCaseIdSet.Count -eq $observedCaseIdSet.Count -and
        $expectedCaseIdSet.IsSubsetOf($observedCaseIdSet)
    $caseSummaryCountMatchesExpected =
        $caseSummaries.Count -eq $expectedCaseIds.Count
    $allCaseSummariesPassed = @(
        $caseSummaries | Where-Object { $_.status -ne 'passed' }
    ).Count -eq 0
    $metadataCompletedCases = if ($null -ne $metadata.completedCases) {
        [int]$metadata.completedCases
    }
    else { $null }
    $metadataCaseCountMatchesSummary = $null -ne $metadataCompletedCases -and
        $metadataCompletedCases -eq $caseSummaries.Count
    $resultMarker = [regex]::IsMatch(
        $workloadLog,
        '(?m)READER_C6_RESULT\s+\{[^\r\n]*"status":"passed"'
    )
    if ($null -ne $metadata.testError -and
        -not [string]::IsNullOrWhiteSpace([string]$metadata.testError)) {
        throw "artifact prefix batch metadata has testError：batch=$($ExpectedBatch.index)"
    }
    if ([bool]$metadata.driverTimedOut -or $null -ne $metadata.restoreError) {
        throw "artifact prefix batch metadata has timeout/restore error：batch=$($ExpectedBatch.index)"
    }
    if (-not $resultMarker) {
        throw "artifact prefix batch lacks final passed C6 result marker：batch=$($ExpectedBatch.index)"
    }
    if (-not $caseSummaryCountMatchesExpected -or
        -not $caseIdsMatchExpected -or
        -not $allCaseSummariesPassed -or
        -not $metadataCaseCountMatchesSummary) {
        throw "artifact prefix batch case summaries incomplete or failed：batch=$($ExpectedBatch.index)"
    }

    $actualDurationSeconds = if ($null -ne $metadata.actualDurationSeconds) {
        [double]$metadata.actualDurationSeconds
    }
    else { $null }
    $workloadDurationSeconds = if ($null -ne $metadata.workloadDurationSeconds) {
        [double]$metadata.workloadDurationSeconds
    }
    else { $null }
    $durationSafetySeconds = @(
        $actualDurationSeconds,
        $workloadDurationSeconds
    ) | Where-Object { $null -ne $_ } | Measure-Object -Maximum |
        Select-Object -ExpandProperty Maximum
    $durationFallbackRequired = $null -ne $durationSafetySeconds -and
        $durationSafetySeconds -gt $durationFallbackThresholdSeconds
    if ($durationFallbackRequired) {
        throw "artifact prefix batch crossed duration fallback threshold：batch=$($ExpectedBatch.index) seconds=$durationSafetySeconds"
    }

    $numeric = [ordered]@{}
    foreach ($propertyName in @(
        'runtimeViolations', 'temporalViolations', 'visualViolations',
        'crossOracleViolations', 'invariantActionObservations',
        'runtimeActionObservations', 'temporalActionObservations',
        'visualActionObservations', 'visualTotalFrames',
        'visualCapturedFrames', 'visualDroppedFrames'
    )) {
        $value = Get-C6NumericSum -Items $caseSummaries -PropertyName $propertyName
        if ($null -eq $value) {
            throw "artifact prefix batch numeric field missing：batch=$($ExpectedBatch.index) property=$propertyName"
        }
        $numeric[$propertyName] = $value
    }

    return [ordered]@{
        index = $ExpectedBatch.index
        plannedBatchIndex = $ExpectedBatch.index
        executionScope = 'complete-subset'
        # Planner batch objects carry the case array, not a persisted caseCount
        # property. Derive this field from the exact case list so artifact-
        # reconstructed prefix results remain self-consistent and cannot expose
        # a null count to the aggregate/resume validator.
        caseCount = $expectedCaseIds.Count
        estimatedOperations = $ExpectedBatch.estimatedOperations
        exitCode = 0
        # This is derived from a complete app result marker, clean metadata,
        # and complete durable summaries because the interrupted parent did
        # not persist its outer C6_BATCH_RESULT line. It is not inferred from
        # an empty directory or a partial log.
        runnerExitCodeObserved = $true
        runnerExitObservation = 'artifact-derived-clean-run'
        runnerInvocationError = $null
        status = 'passed'
        failureClassification = 'not_failed'
        reportDir = $Directory
        completedCases = $metadataCompletedCases
        testError = $null
        caseSummaryCount = $caseSummaries.Count
        caseSummaryCountMatchesExpected = $caseSummaryCountMatchesExpected
        caseIdsMatchExpected = $caseIdsMatchExpected
        allCaseSummariesPassed = $allCaseSummariesPassed
        metadataCaseCountMatchesSummary = $metadataCaseCountMatchesSummary
        caseSummaryComplete = $true
        evidenceDrainComplete = [bool]$evidenceDrainValidation.complete
        evidenceDrainStatus = [string]$evidenceDrainValidation.status
        evidenceDrainErrors = @($evidenceDrainValidation.errors)
        c6ProgressMarkers = $metadata.c6ProgressMarkers
        c6FailureMarkers = $metadata.c6FailureMarkers
        durationSafetySeconds = $durationSafetySeconds
        durationFallbackThresholdSeconds = $durationFallbackThresholdSeconds
        durationFallbackRequired = $false
        runtimeViolations = $numeric.runtimeViolations
        temporalViolations = $numeric.temporalViolations
        visualViolations = $numeric.visualViolations
        crossOracleViolations = $numeric.crossOracleViolations
        invariantActionObservations = $numeric.invariantActionObservations
        runtimeActionObservations = $numeric.runtimeActionObservations
        temporalActionObservations = $numeric.temporalActionObservations
        visualActionObservations = $numeric.visualActionObservations
        visualTotalFrames = $numeric.visualTotalFrames
        visualCapturedFrames = $numeric.visualCapturedFrames
        visualDroppedFrames = $numeric.visualDroppedFrames
        actualDurationSeconds = $actualDurationSeconds
        workloadDurationSeconds = $workloadDurationSeconds
    }
}

$batchResults = [System.Collections.Generic.List[object]]::new()
if ($StartBatchIndex -gt 0) {
    $sourceAggregatePath = Join-Path $resumeSourceRoot 'aggregate.json'
    $sourcePlanPath = Join-Path $resumeSourceRoot 'batch-plan.json'
    if (-not (Test-Path -LiteralPath $sourceAggregatePath -PathType Leaf) -and
        -not $AllowArtifactPrefixResume) {
        throw "續跑來源缺少 aggregate.json：$sourceAggregatePath"
    }
    if (-not (Test-Path -LiteralPath $sourcePlanPath -PathType Leaf)) {
        throw "續跑來源缺少 batch-plan.json：$sourcePlanPath"
    }
    $sourceAggregate = if (Test-Path -LiteralPath $sourceAggregatePath -PathType Leaf) {
        Get-Content -Raw -LiteralPath $sourceAggregatePath | ConvertFrom-Json
    }
    else { $null }
    $sourcePlan = Get-Content -Raw -LiteralPath $sourcePlanPath | ConvertFrom-Json
    if (($null -ne $sourceAggregate -and [int]$sourceAggregate.seed -ne $Seed) -or
        [int]$sourcePlan.seed -ne $Seed) {
        throw '續跑來源 seed 與目前 seed 不一致；拒絕混合 aggregate。'
    }
    if (($null -ne $sourceAggregate -and
         [string]$sourceAggregate.subsetSha256 -ne [string]$plan.subsetSha256) -or
        [string]$sourcePlan.subsetSha256 -ne [string]$plan.subsetSha256) {
        throw '續跑來源 subsetSha256 與目前 subset 不一致；拒絕混合 aggregate。'
    }
    $sameBatchPlan = $null -ne $sourceAggregate -and
        [int]$sourceAggregate.plannedBatchCount -eq $batches.Count -and
        [int]$sourcePlan.batchCount -eq $batches.Count
    if (-not $sameBatchPlan -and -not ($AllowCompatiblePrefixResume -or $AllowArtifactPrefixResume)) {
        throw '續跑來源 batch plan 與目前 batch plan 不一致；若要跨 planner budget 續跑，必須明確使用 AllowCompatiblePrefixResume。'
    }
    if (-not $sameBatchPlan) {
        if ($StartBatchIndex -le 0) {
            throw '跨 planner budget resume 必須至少指定一個要驗證的 complete prefix batch。'
        }
        for ($index = 0; $index -lt $StartBatchIndex; $index++) {
            $sourceBatchDirectory = Join-Path $resumeSourceRoot ('batch-{0:D3}' -f $index)
            $sourceCaseListPath = Join-Path $sourceBatchDirectory 'case-list.json'
            if (-not (Test-Path -LiteralPath $sourceCaseListPath -PathType Leaf)) {
                throw "跨 planner resume 來源缺少 case-list：index=$index"
            }
            $sourceCaseList = Get-Content -Raw -LiteralPath $sourceCaseListPath | ConvertFrom-Json
            $sourceCaseIds = @($sourceCaseList.cases | ForEach-Object { [string]$_.caseId })
            $targetCaseIds = @($batches[$index].cases | ForEach-Object { [string]$_.caseId })
            if ($sourceCaseIds.Count -ne $targetCaseIds.Count) {
                throw "跨 planner resume prefix case count 不一致：index=$index"
            }
            for ($caseIndex = 0; $caseIndex -lt $targetCaseIds.Count; $caseIndex++) {
                if ($sourceCaseIds[$caseIndex] -cne $targetCaseIds[$caseIndex]) {
                    throw "跨 planner resume prefix case id 不一致：batch=$index case=$caseIndex"
                }
            }
        }
    }

    $sourceBatchResults = if ($null -ne $sourceAggregate) {
        @($sourceAggregate.batches)
    }
    else {
        $derivedResults = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $StartBatchIndex; $index++) {
            $sourceBatchDirectory = Join-Path $resumeSourceRoot ('batch-{0:D3}' -f $index)
            $derivedResults.Add(
                (Get-C6ArtifactBatchResult `
                    -Directory $sourceBatchDirectory `
                    -ExpectedBatch $batches[$index])
            )
        }
        @($derivedResults)
    }
    for ($index = 0; $index -lt $StartBatchIndex; $index++) {
        $sourceBatchDirectory = Join-Path $resumeSourceRoot ('batch-{0:D3}' -f $index)
        $evidenceDrainValidation = Test-C6EvidenceDrain `
            -Directory $sourceBatchDirectory `
            -ExpectedCaseIds @($batches[$index].cases | ForEach-Object { [string]$_.caseId }) `
            -RequireRootProvenance
        if (-not [bool]$evidenceDrainValidation.complete) {
            throw (
                '續跑來源 prefix batch evidence-drain incomplete：index={0} errors={1}' -f
                $index,
                (@($evidenceDrainValidation.errors) -join '; ')
            )
        }
        $sourceResult = @($sourceBatchResults | Where-Object { [int]$_.index -eq $index })
        if ($sourceResult.Count -ne 1) {
            throw "續跑來源缺少唯一的完整 batch result：index=$index"
        }
        $sourceResult = $sourceResult[0]
        if (-not [bool]$sourceResult.caseSummaryComplete -or
            [string]$sourceResult.status -ne 'passed' -or
            -not [bool]$sourceResult.runnerExitCodeObserved -or
            [int]$sourceResult.exitCode -ne 0 -or
            -not [bool]$sourceResult.caseIdsMatchExpected -or
            -not [bool]$sourceResult.allCaseSummariesPassed) {
            throw "續跑來源 prefix batch 不是完整 passed result：index=$index"
        }
        $sourceMetadataPath = Join-Path $sourceBatchDirectory 'metadata.json'
        if (-not (Test-Path -LiteralPath $sourceBatchDirectory -PathType Container) -or
            -not (Test-Path -LiteralPath $sourceMetadataPath -PathType Leaf)) {
            throw "續跑來源 prefix batch 缺少完整 metadata：index=$index"
        }
        $destinationBatchDirectory = Join-Path $reportRoot ('batch-{0:D3}' -f $index)
        Copy-Item -LiteralPath $sourceBatchDirectory -Destination $destinationBatchDirectory -Recurse -Force
        $carriedDrainValidation = Test-C6EvidenceDrain `
            -Directory $destinationBatchDirectory `
            -ExpectedCaseIds @($batches[$index].cases | ForEach-Object { [string]$_.caseId }) `
            -RequireRootProvenance
        if (-not [bool]$carriedDrainValidation.complete) {
            throw (
                '續跑 carried batch evidence-drain recheck incomplete：index={0} errors={1}' -f
                $index,
                (@($carriedDrainValidation.errors) -join '; ')
            )
        }
        $carriedResult = $sourceResult | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $carriedResult.reportDir = $destinationBatchDirectory
        # Normalize the carried result against the target plan. Older artifact
        # reconstruction used a planner object without a persisted caseCount;
        # the exact target case list is authoritative for this structural field.
        $carriedResult.caseCount = @($batches[$index].cases).Count
        $carriedResult.evidenceDrainComplete = $true
        $carriedResult.evidenceDrainStatus = 'complete'
        $carriedResult.evidenceDrainErrors = @()
        $batchResults.Add($carriedResult)
    }
    if ($AllowArtifactPrefixResume -and $null -eq $sourceAggregate) {
        [ordered]@{
            schemaVersion = 1
            sourceReportRoot = $resumeSourceRoot
            mode = 'complete-prefix-reconstructed-from-batch-artifacts'
            carriedBatchCount = $batchResults.Count
            carriedBatchIndexes = @($batchResults | ForEach-Object { [int]$_.index })
            incompleteSourceAttemptsExcluded = $true
            proof = 'Each carried batch required exact case-list ids, complete passed case summaries, schema-v2 evidence-drain with exact per-required-file transport records and final bundle validation, metadata completedCases match, clean metadata, final READER_C6_RESULT passed marker, non-timeout duration, and non-null numeric fields.'
        } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $reportRoot 'prefix-resume-evidence.json') -Encoding utf8
    }
    Write-Host (
        'C6_BATCH_RESUME start={0} carriedCompleteBatches={1} source={2} invalidAttemptsExcluded=true' -f
        $StartBatchIndex, $batchResults.Count, $resumeSourceRoot
    )
}

if ($DryRun) {
    Write-Host 'C6_BATCH_DRY_RUN no Android workload started.'
    exit 0
}

foreach ($batch in $executionBatches) {
    if (-not $PilotOnly -and $batch.index -lt $StartBatchIndex) {
        continue
    }
    $batchDirectoryName = if ($PilotOnly) {
        'pilot-batch-{0:D3}' -f $batch.executionIndex
    }
    else {
        'batch-{0:D3}' -f $batch.index
    }
    $batchDirectory = Join-Path $reportRoot $batchDirectoryName
    New-Item -ItemType Directory -Path $batchDirectory -Force | Out-Null
    $batchManifestPath = Join-Path $batchDirectory 'case-list.json'
    [ordered]@{
        schemaVersion = $subset.schemaVersion
        seed = $subset.seed
        caseCount = $batch.cases.Count
        cases = @($batch.cases)
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $batchManifestPath -Encoding utf8

    $runnerArguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        (Join-Path $repoRoot 'tool/run_android_reader_workload.ps1'),
        '-DeviceId', $DeviceId,
        '-Scenario', 'correctness-subset',
        '-BuildMode', 'debug',
        '-Seed', $Seed,
        '-CaseList', $batchManifestPath,
        '-TimeoutSeconds', '300',
        '-ReportDir', $batchDirectory,
        '-EnableInvariantHook'
    )
    if ($CaptureGolden) { $runnerArguments += '-CaptureGolden' }
    Write-Host "C6_BATCH_START index=$($batch.index) cases=$($batch.cases.Count) estimatedOperations=$($batch.estimatedOperations)"
    $runnerInvocationError = $null
    $rawExitCode = $null
    try {
        & pwsh @runnerArguments
        $rawExitCode = $LASTEXITCODE
    }
    catch {
        # A vanished/failed child must still produce an explicit failed batch
        # record.  Do not let PowerShell's invocation error bypass aggregation
        # and leave Relay with an ambiguous partial directory.
        $runnerInvocationError = $_.Exception.ToString()
    }
    $runnerExitCodeObserved = $null -ne $rawExitCode
    $exitCode = if ($runnerExitCodeObserved) { [int]$rawExitCode } else { 1 }
    if ($exitCode -ne 0 -and $overallExitCode -eq 0) { $overallExitCode = $exitCode }
    $metadataPath = Join-Path $batchDirectory 'metadata.json'
    $metadata = if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
        Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json
    }
    else { $null }
    $caseSummaries = @(Get-C6CaseSummaries -Directory $batchDirectory)
    $metadataCompletedCases = if ($null -ne $metadata -and $null -ne $metadata.completedCases) {
        [int]$metadata.completedCases
    }
    else { $null }
    $metadataCaseCountMatchesSummary = $null -ne $metadataCompletedCases -and
        $metadataCompletedCases -eq $caseSummaries.Count
    $caseSummaryCountMatchesExpected = $caseSummaries.Count -eq $batch.cases.Count
    $expectedCaseIds = @($batch.cases | ForEach-Object { [string]$_.caseId })
    $observedCaseIds = @($caseSummaries | ForEach-Object { [string]$_.caseId })
    $expectedCaseIdSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $observedCaseIdSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($caseId in $expectedCaseIds) { [void]$expectedCaseIdSet.Add($caseId) }
    foreach ($caseId in $observedCaseIds) { [void]$observedCaseIdSet.Add($caseId) }
    $caseIdsMatchExpected = $expectedCaseIdSet.Count -eq $observedCaseIdSet.Count -and
        $expectedCaseIdSet.IsSubsetOf($observedCaseIdSet)
    $allCaseSummariesPassed = @(
        $caseSummaries | Where-Object { $_.status -ne 'passed' }
    ).Count -eq 0
    $evidenceDrainValidation = Test-C6EvidenceDrain `
        -Directory $batchDirectory `
        -ExpectedCaseIds $expectedCaseIds `
        -RequireRootProvenance
    $caseSummaryComplete = $caseSummaryCountMatchesExpected -and
        $caseIdsMatchExpected -and
        $allCaseSummariesPassed -and
        $metadataCaseCountMatchesSummary -and
        [bool]$evidenceDrainValidation.complete -and
        $runnerExitCodeObserved -and
        $exitCode -eq 0 -and
        $null -eq $runnerInvocationError
    $failureClassification = Get-C6FailureClassification `
        -Metadata $metadata `
        -CaseSummaries $caseSummaries `
        -ExitCode $exitCode `
        -RunnerInvocationError $runnerInvocationError `
        -EvidenceDrainComplete ([bool]$evidenceDrainValidation.complete)
    # A zero process exit is not sufficient evidence that every requested case
    # produced a durable summary with matching metadata.  Keep the aggregate
    # fail-closed if a runner ever exits early without surfacing a nonzero code,
    # or if metadata reports fewer cases than the durable summaries.
    if (-not $caseSummaryComplete -and $overallExitCode -eq 0) {
        $overallExitCode = 1
    }
    $actualDurationSeconds = if ($null -ne $metadata -and $null -ne $metadata.actualDurationSeconds) {
        [double]$metadata.actualDurationSeconds
    }
    else { $null }
    $workloadDurationSeconds = if ($null -ne $metadata -and $null -ne $metadata.workloadDurationSeconds) {
        [double]$metadata.workloadDurationSeconds
    }
    else { $null }
    $durationSafetySeconds = @(
        $actualDurationSeconds,
        $workloadDurationSeconds
    ) | Where-Object { $null -ne $_ } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
    $durationFallbackRequired = $null -ne $durationSafetySeconds -and
        $durationSafetySeconds -gt $durationFallbackThresholdSeconds
    if ($durationFallbackRequired -and $overallExitCode -eq 0) {
        $overallExitCode = 1
    }
    $batchResult = [ordered]@{
        index = if ($PilotOnly) { $batch.executionIndex } else { $batch.index }
        plannedBatchIndex = $batch.index
        executionScope = if ($PilotOnly) { 'pilot-only-non-acceptance' } else { 'complete-subset' }
        caseCount = $batch.cases.Count
        estimatedOperations = $batch.estimatedOperations
        exitCode = $exitCode
        runnerExitCodeObserved = $runnerExitCodeObserved
        runnerInvocationError = $runnerInvocationError
        status = if ($caseSummaryComplete) { 'passed' } else { 'failed_or_invalid' }
        failureClassification = $failureClassification
        reportDir = $batchDirectory
        completedCases = $metadataCompletedCases
        testError = if ($null -ne $metadata) { $metadata.testError } else { 'metadata missing' }
        caseSummaryCount = $caseSummaries.Count
        caseSummaryCountMatchesExpected = $caseSummaryCountMatchesExpected
        caseIdsMatchExpected = $caseIdsMatchExpected
        allCaseSummariesPassed = $allCaseSummariesPassed
        metadataCaseCountMatchesSummary = $metadataCaseCountMatchesSummary
        caseSummaryComplete = $caseSummaryComplete
        evidenceDrainComplete = [bool]$evidenceDrainValidation.complete
        evidenceDrainStatus = [string]$evidenceDrainValidation.status
        evidenceDrainErrors = @($evidenceDrainValidation.errors)
        c6ProgressMarkers = if ($null -ne $metadata) { $metadata.c6ProgressMarkers } else { $null }
        c6FailureMarkers = if ($null -ne $metadata) { $metadata.c6FailureMarkers } else { $null }
        durationSafetySeconds = $durationSafetySeconds
        durationFallbackThresholdSeconds = $durationFallbackThresholdSeconds
        durationFallbackRequired = $durationFallbackRequired
        runtimeViolations = Get-C6NumericSum -Items $caseSummaries -PropertyName 'runtimeViolations'
        temporalViolations = Get-C6NumericSum -Items $caseSummaries -PropertyName 'temporalViolations'
        visualViolations = Get-C6NumericSum -Items $caseSummaries -PropertyName 'visualViolations'
        crossOracleViolations = Get-C6NumericSum -Items $caseSummaries -PropertyName 'crossOracleViolations'
        invariantActionObservations = Get-C6NumericSum -Items $caseSummaries -PropertyName 'invariantActionObservations'
        runtimeActionObservations = Get-C6NumericSum -Items $caseSummaries -PropertyName 'runtimeActionObservations'
        temporalActionObservations = Get-C6NumericSum -Items $caseSummaries -PropertyName 'temporalActionObservations'
        visualActionObservations = Get-C6NumericSum -Items $caseSummaries -PropertyName 'visualActionObservations'
        visualTotalFrames = Get-C6NumericSum -Items $caseSummaries -PropertyName 'visualTotalFrames'
        visualCapturedFrames = Get-C6NumericSum -Items $caseSummaries -PropertyName 'visualCapturedFrames'
        visualDroppedFrames = Get-C6NumericSum -Items $caseSummaries -PropertyName 'visualDroppedFrames'
        actualDurationSeconds = $actualDurationSeconds
        workloadDurationSeconds = $workloadDurationSeconds
    }
    $batchResults.Add($batchResult)
    $batchResult | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath (Join-Path $batchDirectory 'batch-result.json') -Encoding utf8
    $batchResults | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath (Join-Path $reportRoot 'batch-results-checkpoint.json') -Encoding utf8
    Write-Host ('C6_BATCH_RESULT ' + ($batchResult | ConvertTo-Json -Compress -Depth 8))
    if ($durationFallbackRequired) {
        Write-Host (
            'C6_BATCH_STOP index={0} reason=duration-near-hard-limit safetySeconds={1} thresholdSeconds={2} fallback=20-op' -f
            $batch.index, $durationSafetySeconds, $durationFallbackThresholdSeconds
        )
        break
    }
    if ($StopAfterBatchIndex -ge 0 -and
        ($batch.index + 1) -ge $StopAfterBatchIndex) {
        # This is a deliberate prefix boundary, not a successful aggregate:
        # the final aggregate below remains fail-closed because planned
        # batches are still outstanding.  The complete prefix is reusable only
        # through the explicit resume validation above.
        $overallExitCode = 1
        Write-Host (
            'C6_BATCH_STOP index={0} reason=bounded-prefix-stop nextBatch={1} planned={2} acceptanceEligible=false' -f
            $batch.index, $StopAfterBatchIndex, $batches.Count
        )
        break
    }
    if (-not $caseSummaryComplete) {
        # A failed case or an environment-invalid setup cannot become valid by
        # continuing on the same run.  Stop before starting another batch so a
        # broken emulator/ADB session is never treated as a retry loop.
        Write-Host (
            'C6_BATCH_STOP index={0} reason={1} executed={2} planned={3}' -f
            $batch.index, $failureClassification, $batchResults.Count, $executionBatches.Count
        )
        break
    }
}

$aggregateCaseSummaryComplete = @($batchResults | Where-Object { -not $_.caseSummaryComplete }).Count -eq 0
$aggregateEvidenceDrainComplete = $batchResults.Count -gt 0 -and
    @($batchResults | Where-Object { -not [bool]$_.evidenceDrainComplete }).Count -eq 0
$aggregateEvidenceDrainErrors = @(
    $batchResults | ForEach-Object { @($_.evidenceDrainErrors) }
)
$aggregateCaseSummaryCount = Get-C6NumericSum -Items $batchResults -PropertyName 'caseSummaryCount'
$aggregateCompletedCases = Get-C6NumericSum -Items $batchResults -PropertyName 'completedCases'
$aggregateCaseCountMatchesExpected = $aggregateCaseSummaryComplete -and
    $aggregateCaseSummaryCount -eq $allCases.Count -and
    $aggregateCompletedCases -eq $allCases.Count
# The aggregate is a pass only when every requested case has a durable
# summary.json, a complete evidence-drain, and runner metadata that agrees
# with those counts.  This protects Relay from treating a vanished driver,
# truncated transport, or stale case directory as an empty pass even when a
# child process returned zero.
if (-not $aggregateCaseCountMatchesExpected -and $overallExitCode -eq 0) {
    $overallExitCode = 1
}
$aggregateVisualTotalFrames = if ($aggregateCaseSummaryComplete) {
    Get-C6NumericSum -Items $batchResults -PropertyName 'visualTotalFrames'
}
else { $null }
$aggregateVisualCapturedFrames = if ($aggregateCaseSummaryComplete) {
    Get-C6NumericSum -Items $batchResults -PropertyName 'visualCapturedFrames'
}
else { $null }
$aggregateVisualCoverage = if ($null -ne $aggregateVisualTotalFrames -and $aggregateVisualTotalFrames -gt 0) {
    [math]::Round($aggregateVisualCapturedFrames / $aggregateVisualTotalFrames, 6)
}
else { $null }

$aggregate = [ordered]@{
    schemaVersion = 1
    seed = $Seed
    sourceManifest = $manifestPath
    subsetPath = $subsetPath
    subsetSha256 = $plan.subsetSha256
    totalCases = $allCases.Count
    batchCount = $batches.Count
    plannedBatchCount = $batches.Count
    executedBatchCount = $batchResults.Count
    status = if ($overallExitCode -eq 0) { 'passed' } else { 'failed_or_invalid' }
    invalidOrFailedBatchCount = @($batchResults | Where-Object { $_.exitCode -ne 0 }).Count
    invalidOrIncompleteBatchCount = @(
        $batchResults | Where-Object {
            $_.exitCode -ne 0 -or -not $_.caseSummaryComplete
        }
    ).Count
    durationFallbackBatchCount = @(
        $batchResults | Where-Object { [bool]$_.durationFallbackRequired }
    ).Count
    durationFallbackRequired = @(
        $batchResults | Where-Object { [bool]$_.durationFallbackRequired }
    ).Count -gt 0
    expectedCaseCount = $allCases.Count
    executionScope = if ($PilotOnly) {
        'pilot-only-non-acceptance'
    }
    elseif ($StopAfterBatchIndex -ge 0) {
        'bounded-prefix-non-acceptance'
    }
    else { 'complete-subset' }
    stopAfterBatchIndex = $StopAfterBatchIndex
    pilot = if ($PilotOnly) {
        [ordered]@{
            caseCount = $pilotSelection.Count
            estimatedOperations = $pilotOperationCount
            caseIds = @($pilotRows | ForEach-Object { $_.caseId })
            acceptanceEligible = $false
        }
    }
    else { $null }
    totalCompletedCases = $aggregateCompletedCases
    totalCaseSummaryCount = $aggregateCaseSummaryCount
    caseCountMatchesExpected = $aggregateCaseCountMatchesExpected
    evidenceDrainComplete = $aggregateEvidenceDrainComplete
    evidenceDrainErrors = $aggregateEvidenceDrainErrors
    allBatchesHaveObservedExitCode = @(
        $batchResults | Where-Object { -not $_.runnerExitCodeObserved }
    ).Count -eq 0
    totalElapsedSeconds = Get-C6NumericSum -Items $batchResults -PropertyName 'actualDurationSeconds'
    totalWorkloadSeconds = Get-C6NumericSum -Items $batchResults -PropertyName 'workloadDurationSeconds'
    caseSummaryComplete = $aggregateCaseSummaryComplete
    allPlannedBatchesExecuted = -not $PilotOnly -and $batchResults.Count -eq $batches.Count
    acceptanceEligible = -not $PilotOnly -and
        $StopAfterBatchIndex -lt 0 -and
        $aggregateCaseCountMatchesExpected -and
        $aggregateEvidenceDrainComplete -and
        $batchResults.Count -eq $batches.Count
    runtimeViolations = if ($aggregateCaseSummaryComplete) { Get-C6NumericSum -Items $batchResults -PropertyName 'runtimeViolations' } else { $null }
    temporalViolations = if ($aggregateCaseSummaryComplete) { Get-C6NumericSum -Items $batchResults -PropertyName 'temporalViolations' } else { $null }
    visualViolations = if ($aggregateCaseSummaryComplete) { Get-C6NumericSum -Items $batchResults -PropertyName 'visualViolations' } else { $null }
    crossOracleViolations = if ($aggregateCaseSummaryComplete) { Get-C6NumericSum -Items $batchResults -PropertyName 'crossOracleViolations' } else { $null }
    invariantActionObservations = if ($aggregateCaseSummaryComplete) { Get-C6NumericSum -Items $batchResults -PropertyName 'invariantActionObservations' } else { $null }
    runtimeActionObservations = if ($aggregateCaseSummaryComplete) { Get-C6NumericSum -Items $batchResults -PropertyName 'runtimeActionObservations' } else { $null }
    temporalActionObservations = if ($aggregateCaseSummaryComplete) { Get-C6NumericSum -Items $batchResults -PropertyName 'temporalActionObservations' } else { $null }
    visualActionObservations = if ($aggregateCaseSummaryComplete) { Get-C6NumericSum -Items $batchResults -PropertyName 'visualActionObservations' } else { $null }
    visualTotalFrames = $aggregateVisualTotalFrames
    visualCapturedFrames = $aggregateVisualCapturedFrames
    visualDroppedFrames = if ($aggregateCaseSummaryComplete) { Get-C6NumericSum -Items $batchResults -PropertyName 'visualDroppedFrames' } else { $null }
    visualCoverage = $aggregateVisualCoverage
    batches = @($batchResults)
    evidenceBoundary = 'C6 Android debug subset; hook/visual capture is correctness evidence only and is excluded from P2 performance judgment.'
}
$aggregatePath = Join-Path $reportRoot 'aggregate.json'
$aggregate | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $aggregatePath -Encoding utf8
Write-Host ('C6_BATCH_AGGREGATE ' + ($aggregate | ConvertTo-Json -Compress -Depth 12))
exit $overallExitCode
