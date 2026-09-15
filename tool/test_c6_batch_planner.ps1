[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$plannerPath = Join-Path $repoRoot 'tool/run_reader_correctness_android_subset.ps1'
$evidenceModulePath = Join-Path $repoRoot 'tool/c6_evidence_bundle.psm1'
$sourceRoot = Join-Path $repoRoot 'artifacts/android-reader/c6-subset-seed-9132051-c6-full-after-liveness-contract-20260915'
$manifestPath = Join-Path $repoRoot 'docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-9132051.json'

function Assert-C6PlannerTest {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "C6 planner contract failed: $Message"
    }
}

function Invoke-C6Planner {
    param([string[]]$Arguments)

    $output = (& pwsh -NoProfile @Arguments 2>&1 | Out-String)
    [pscustomobject]@{
        exitCode = [int]$LASTEXITCODE
        output = $output
    }
}

Assert-C6PlannerTest (Test-Path -LiteralPath $plannerPath -PathType Leaf) 'planner is missing'
Assert-C6PlannerTest (Test-Path -LiteralPath $sourceRoot -PathType Container) 'batch-016 source root is missing'
Assert-C6PlannerTest (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'seed-9132051 manifest is missing'

$parseErrors = [System.Collections.Generic.List[object]]::new()
[System.Management.Automation.Language.Parser]::ParseFile(
    $plannerPath,
    [ref]$null,
    [ref]$parseErrors
) | Out-Null
Assert-C6PlannerTest ($parseErrors.Count -eq 0) 'PowerShell parser reported errors'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'night-reader-c6-planner-contract-{0}' -f [Guid]::NewGuid().ToString('N')
)
$planRoot = Join-Path $testRoot 'plan'
$resumeRoot = Join-Path $testRoot 'resume'
$brokenBatchRoot = Join-Path $testRoot 'broken-batch-016'

try {
    $commonArguments = @(
        '-File', $plannerPath,
        '-DeviceId', 'emulator-5556',
        '-Seed', '9132051',
        # 本檔驗的是 batching/resume 契約，與 lane 無關；批次幾何
        # （batch 16/17、batchCount 231）來自 279-case 的 acceptance 形狀，
        # 因此明確釘住 lane，不隨預設值改變而漂移。
        '-Lane', 'acceptance',
        '-ManifestHostPath', $manifestPath,
        '-MaxCasesPerBatch', '4',
        '-MaxEstimatedOperationsPerBatch', '36',
        '-RemainderFromBatchIndex', '16',
        '-RemainderMaxCasesPerBatch', '1',
        '-RemainderMaxEstimatedOperationsPerBatch', '36',
        '-DryRun'
    )
    $dryRunArguments = @('-NoProfile') + $commonArguments + @(
        '-ReportRoot', $planRoot
    )
    $dryRun = Invoke-C6Planner -Arguments $dryRunArguments
    Assert-C6PlannerTest ($dryRun.exitCode -eq 0) (
        "remainder dry-run exited $($dryRun.exitCode): " +
        $dryRun.output.Substring([Math]::Max(0, $dryRun.output.Length - 1600))
    )

    $planPath = Join-Path $planRoot 'batch-plan.json'
    $subsetPath = Join-Path $planRoot 'subset-seed-9132051-acceptance.json'
    Assert-C6PlannerTest (Test-Path -LiteralPath $planPath -PathType Leaf) 'dry-run did not write batch-plan.json'
    Assert-C6PlannerTest (Test-Path -LiteralPath $subsetPath -PathType Leaf) 'dry-run did not write deterministic subset'
    Assert-C6PlannerTest (-not (Test-Path -LiteralPath (Join-Path $planRoot 'aggregate.json') -PathType Leaf)) 'dry-run wrote an aggregate'

    $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
    $subset = Get-Content -Raw -LiteralPath $subsetPath | ConvertFrom-Json
    Assert-C6PlannerTest ([int]$plan.seed -eq 9132051) 'plan seed changed'
    Assert-C6PlannerTest ([int]$plan.totalCases -eq 279) 'plan totalCases is not 279'
    Assert-C6PlannerTest ([int]$plan.remainder.fromBatchIndex -eq 16) 'remainder starts at the wrong batch'
    Assert-C6PlannerTest ([int]$plan.remainder.prefixCaseCount -eq 64) 'remainder prefix is not 64 cases'
    Assert-C6PlannerTest ([int]$plan.plannerSafety.runnerIterationsLimit -eq 60) 'runner iteration gate changed'
    Assert-C6PlannerTest ([int]$plan.plannerSafety.runnerTimeoutSeconds -eq 300) 'runner timeout gate changed'
    Assert-C6PlannerTest ([int]$plan.plannerSafety.durationFallbackThresholdSeconds -eq 280) 'duration fallback gate changed'
    Assert-C6PlannerTest ([string]$plan.subsetSha256 -ceq (Get-FileHash -Algorithm SHA256 -LiteralPath $subsetPath).Hash.ToLowerInvariant()) 'subset hash changed'

    $offset = 0
    foreach ($batch in @($plan.batches)) {
        $count = [int]$batch.caseCount
        Assert-C6PlannerTest ($count -gt 0) "batch $($batch.index) is empty"
        $lastOffset = $offset + $count - 1
        Assert-C6PlannerTest ($lastOffset -lt @($subset.cases).Count) "batch $($batch.index) exceeds subset"
        Assert-C6PlannerTest ([string]$batch.firstCaseId -ceq [string]$subset.cases[$offset].caseId) "batch $($batch.index) first case reordered"
        Assert-C6PlannerTest ([string]$batch.lastCaseId -ceq [string]$subset.cases[$lastOffset].caseId) "batch $($batch.index) last case reordered"
        if ([int]$batch.index -lt 16) {
            Assert-C6PlannerTest ($count -eq 4) "prefix batch $($batch.index) is not 4 cases"
        }
        else {
            Assert-C6PlannerTest ($count -eq 1) "remainder batch $($batch.index) is not 1 case"
            Assert-C6PlannerTest ([int]$batch.estimatedOperations -le 36) "remainder batch $($batch.index) exceeds runner operation estimate"
        }
        $offset = $lastOffset + 1
    }
    Assert-C6PlannerTest ($offset -eq @($subset.cases).Count) 'not every deterministic subset case appears exactly once in the plan'
    Assert-C6PlannerTest ([int]$plan.batchCount -eq 231) 'remainder plan batch count is not 231'

    $resumeArguments = @('-NoProfile') + $commonArguments + @(
        '-ReportRoot', $resumeRoot,
        '-StartBatchIndex', '16',
        '-ResumeFromReportRoot', $sourceRoot,
        '-AllowCompatiblePrefixResume'
    )
    $resumeRun = Invoke-C6Planner -Arguments $resumeArguments
    Assert-C6PlannerTest ($resumeRun.exitCode -eq 0) (
        "compatible-prefix dry-run exited $($resumeRun.exitCode): " +
        $resumeRun.output.Substring([Math]::Max(0, $resumeRun.output.Length - 2000))
    )
    for ($index = 0; $index -lt 16; $index++) {
        $sourceBatch = Join-Path $sourceRoot ('batch-{0:D3}' -f $index)
        $carriedBatch = Join-Path $resumeRoot ('batch-{0:D3}' -f $index)
        Assert-C6PlannerTest (Test-Path -LiteralPath $carriedBatch -PathType Container) "complete prefix batch $index was not carried"
        $sourceIds = @((Get-Content -Raw (Join-Path $sourceBatch 'case-list.json') | ConvertFrom-Json).cases | ForEach-Object { [string]$_.caseId })
        $carriedIds = @((Get-Content -Raw (Join-Path $carriedBatch 'case-list.json') | ConvertFrom-Json).cases | ForEach-Object { [string]$_.caseId })
        Assert-C6PlannerTest (($sourceIds -join "`n") -ceq ($carriedIds -join "`n")) "carried batch $index case-list changed"
        $carriedResult = Get-Content -Raw (Join-Path $carriedBatch 'batch-result.json') | ConvertFrom-Json
        Assert-C6PlannerTest ([string]$carriedResult.status -ceq 'passed') "carried batch $index is not passed"
        Assert-C6PlannerTest ([bool]$carriedResult.caseSummaryComplete) "carried batch $index is incomplete"
    }
    Assert-C6PlannerTest (-not (Test-Path -LiteralPath (Join-Path $resumeRoot 'batch-016') -PathType Container)) 'remainder dry-run started a workload batch'

    $failedBatch = Join-Path $sourceRoot 'batch-016'
    $failedResult = Get-Content -Raw (Join-Path $failedBatch 'batch-result.json') | ConvertFrom-Json
    Assert-C6PlannerTest ([string]$failedResult.status -ceq 'failed_or_invalid') 'original batch-016 is not recorded failed_or_invalid'
    Assert-C6PlannerTest ([bool]$failedResult.durationFallbackRequired) 'original batch-016 duration fallback marker disappeared'
    Assert-C6PlannerTest ([double]$failedResult.durationSafetySeconds -gt 280) 'original batch-016 near-hard-limit duration is not preserved'

    $failedPrefixArguments = @('-NoProfile') + @(
        '-File', $plannerPath,
        '-DeviceId', 'emulator-5556',
        '-Seed', '9132051',
        # 本檔驗的是 batching/resume 契約，與 lane 無關；批次幾何
        # （batch 16/17、batchCount 231）來自 279-case 的 acceptance 形狀，
        # 因此明確釘住 lane，不隨預設值改變而漂移。
        '-Lane', 'acceptance',
        '-ManifestHostPath', $manifestPath,
        '-ReportRoot', (Join-Path $testRoot 'failed-prefix-attempt'),
        '-StartBatchIndex', '17',
        '-ResumeFromReportRoot', $sourceRoot,
        '-AllowCompatiblePrefixResume',
        '-RemainderFromBatchIndex', '17',
        '-MaxCasesPerBatch', '4',
        '-MaxEstimatedOperationsPerBatch', '36',
        '-RemainderMaxCasesPerBatch', '1',
        '-RemainderMaxEstimatedOperationsPerBatch', '36',
        '-DryRun'
    )
    $failedPrefixRun = Invoke-C6Planner -Arguments $failedPrefixArguments
    Assert-C6PlannerTest ($failedPrefixRun.exitCode -ne 0) 'duration-triggering batch-016 was accepted as a prefix'
    Assert-C6PlannerTest ($failedPrefixRun.output -match '不是完整 passed result|duration fallback|duration') 'failed-prefix rejection did not identify the fail-closed reason'

    Copy-Item -LiteralPath $failedBatch -Destination $brokenBatchRoot -Recurse -Force
    $brokenCase = Get-ChildItem -LiteralPath $brokenBatchRoot -Directory -Filter 'C-*' | Select-Object -First 1
    Assert-C6PlannerTest ($null -ne $brokenCase) 'broken evidence fixture has no case bundle'
    Remove-Item -LiteralPath (Join-Path $brokenCase.FullName 'operation-trace.jsonl') -Force
    Import-Module -Name $evidenceModulePath -Force
    $brokenCaseList = Get-Content -Raw (Join-Path $brokenBatchRoot 'case-list.json') | ConvertFrom-Json
    $brokenDrain = Test-C6EvidenceDrain `
        -Directory $brokenBatchRoot `
        -ExpectedCaseIds @($brokenCaseList.cases | ForEach-Object { [string]$_.caseId }) `
        -RequireRootProvenance
    Assert-C6PlannerTest (-not [bool]$brokenDrain.complete) 'missing required evidence was accepted'
    Assert-C6PlannerTest ((@($brokenDrain.errors) -match 'operation-trace.jsonl').Count -gt 0) 'missing evidence rejection did not name operation-trace.jsonl'

    # 預設 lane 也必須能規劃出有界批次。smoke 是現在的 C6 gate，
    # 不能只驗歷史 acceptance 幾何。
    $smokeRoot = Join-Path $testRoot 'smoke-plan'
    $smokeArguments = @('-NoProfile') + @(
        '-File', $plannerPath,
        '-DeviceId', 'emulator-5556',
        '-Seed', '9132051',
        '-ManifestHostPath', $manifestPath,
        '-ReportRoot', $smokeRoot,
        '-MaxCasesPerBatch', '20',
        '-MaxEstimatedOperationsPerBatch', '20',
        '-DryRun'
    )
    $smokeRun = Invoke-C6Planner -Arguments $smokeArguments
    Assert-C6PlannerTest ($smokeRun.exitCode -eq 0) (
        "smoke lane dry-run exited $($smokeRun.exitCode): " +
        $smokeRun.output.Substring([Math]::Max(0, $smokeRun.output.Length - 2000))
    )
    $smokeSubsetPath = Join-Path $smokeRoot 'subset-seed-9132051-smoke.json'
    Assert-C6PlannerTest (Test-Path -LiteralPath $smokeSubsetPath -PathType Leaf) 'smoke lane subset was not written under the default lane'
    $smokeSubset = Get-Content -Raw -LiteralPath $smokeSubsetPath | ConvertFrom-Json
    Assert-C6PlannerTest (@($smokeSubset.cases).Count -eq 58) "smoke lane case count is $(@($smokeSubset.cases).Count), expected 58"
    $smokePlan = Get-Content -Raw -LiteralPath (Join-Path $smokeRoot 'batch-plan.json') | ConvertFrom-Json
    Assert-C6PlannerTest ([int]$smokePlan.batchCount -gt 0) 'smoke lane produced no batches'
    Assert-C6PlannerTest ([int]$smokePlan.batchCount -lt 20) "smoke lane batch count $([int]$smokePlan.batchCount) is not materially smaller than the 46-batch acceptance plan"
    $smokeOffset = 0
    foreach ($batch in @($smokePlan.batches)) {
        $smokeCount = [int]$batch.caseCount
        Assert-C6PlannerTest ($smokeCount -gt 0) "smoke batch $($batch.index) is empty"
        Assert-C6PlannerTest ([int]$batch.estimatedOperations -le 20) "smoke batch $($batch.index) exceeds the runner operation estimate"
        Assert-C6PlannerTest ([string]$batch.firstCaseId -ceq [string]$smokeSubset.cases[$smokeOffset].caseId) "smoke batch $($batch.index) first case reordered"
        $smokeOffset += $smokeCount
    }
    Assert-C6PlannerTest ($smokeOffset -eq @($smokeSubset.cases).Count) 'smoke lane plan does not cover every subset case exactly once'

    Write-Output 'C6 batch planner contract tests passed: deterministic remainder, exact prefix carry, failed/duration exclusion, evidence fail-closed, and bounded smoke-lane planning.'
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
