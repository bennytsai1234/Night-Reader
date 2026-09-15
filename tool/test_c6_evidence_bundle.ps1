[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'c6_evidence_bundle.psm1'
Import-Module -Name $modulePath -Force

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function Write-TestText([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Set-Content -LiteralPath $Path -Value $Content -Encoding utf8
}

function Write-TestPng([string]$Path) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $pngBytes = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
    [IO.File]::WriteAllBytes($Path, $pngBytes)
}

function Write-BaseCase([string]$Directory, [string]$CaseId, [string]$Status = 'passed', [string]$FailureKind = '') {
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $effectiveFailureKind = if (-not [string]::IsNullOrWhiteSpace($FailureKind)) {
        $FailureKind
    }
    elseif ($Status -eq 'passed') {
        'passed'
    }
    else {
        'unclassified-failure'
    }
    $failureMarker = switch ($effectiveFailureKind) {
        'passed' { 'C6_CASE_PASSED' }
        'semantic-settle-timeout' { 'C6_SEMANTIC_SETTLE_TIMEOUT' }
        'invariant-violation' { 'C6_INVARIANT_VIOLATION' }
        'visual-violation' { 'C6_VISUAL_VIOLATION' }
        default { 'C6_UNCLASSIFIED_FAILURE' }
    }
    $startedAt = '2026-09-15T00:00:00.0000000+08:00'
    $endedAt = '2026-09-15T00:00:00.0010000+08:00'
    $operationRecord = [ordered]@{
        index = 0
        operation = 'probe'
        startedAt = $startedAt
        endedAt = $endedAt
        before = [ordered]@{ phase = 'ready'; pumpQueueDepth = 0 }
        expectedTransition = 'probe'
        after = [ordered]@{ phase = 'ready'; pumpQueueDepth = 0 }
        durationMillis = 1
    }
    $runtimeRecord = [ordered]@{
        timestampMicros = 1000
        phase = 'ready'
        scrollOffset = 0
        viewportHeight = 800
        dragging = $false
        isScrolling = $false
        restoreLocked = $false
        initialRestoreCompleted = $true
        epoch = 1
        layoutGeneration = 1
        documentIndexRevision = 1
        resetGeneration = 1
        indexBindingResetGeneration = 1
        indexCenter = [ordered]@{ chapterIndex = 0; blockIndex = 0 }
        visibleKeyCount = 2
        visibleKeyRange = [ordered]@{
            first = [ordered]@{ chapterIndex = 0; blockIndex = 0 }
            last = [ordered]@{ chapterIndex = 0; blockIndex = 1 }
        }
        visibleKeys = @(
            [ordered]@{ chapterIndex = 0; blockIndex = 0 }
            [ordered]@{ chapterIndex = 0; blockIndex = 1 }
        )
        visibleChapters = @(0, 1)
        missingParagraphCount = 0
        unloadedChapterCount = 0
        dominantVisibleChapter = 0
        anchorVisibleChapter = 0
        displayedProgressChapter = 0
        pendingChapterJumpTarget = $null
        pumpQueueDepth = 0
        scrollPixels = 0
        minScrollExtent = 0
        maxScrollExtent = 1000
        scrollActivity = 'idle'
        scrollVelocity = 0
        operationTokenId = 1
        operationIsCurrent = $true
        chapterCount = 1
        errorPresent = $false
    }
    $operationEnvelope = [ordered]@{
        schemaVersion = 2
        source = 'C6-ReaderTestHarness.operation-trace.v2'
        record = $operationRecord
    }
    $runtimeEnvelope = [ordered]@{
        schemaVersion = 2
        source = 'C6-HybridFrameInvariantRecord.runtime-frame.v2'
        record = $runtimeRecord
    }
    $summary = [ordered]@{
        schemaVersion = 2
        bundleType = 'c6-case'
        caseId = $CaseId
        status = $Status
        failureKind = $effectiveFailureKind
        failureMarker = $failureMarker
        invariantHookEnabled = $true
        visualOracleEnabled = $true
        hookProvenance = 'c6-correctness-integration-hook-on'
        hookMode = 'correctness-hook-on'
        hookSource = 'integration_test/reader_correctness_android_subset_test.dart'
        runtimeViolations = 0
        temporalViolations = 0
        visualViolations = 0
        crossOracleViolations = 0
        error = if ($Status -eq 'failed') { 'C6_SEMANTIC_SETTLE_TIMEOUT' } else { $null }
        scenario = 'test'
        documentPosition = 'test'
        target = 'test'
        runtimeState = 'ready'
        visualObservation = 'test'
        firstBadFrame = $null
        firstBadFrameSource = if ($effectiveFailureKind -eq 'semantic-settle-timeout') {
            'not-applicable'
        }
        else { $null }
    }
    if ($effectiveFailureKind -eq 'semantic-settle-timeout') {
        $summary.failureEvidence = [ordered]@{
            schemaVersion = 2
            bundleType = 'c6-case'
            caseId = $CaseId
            status = 'failed'
            failureKind = $effectiveFailureKind
            failureMarker = $failureMarker
            invariantHookEnabled = $true
            visualOracleEnabled = $true
            hookProvenance = 'c6-correctness-integration-hook-on'
            hookMode = 'correctness-hook-on'
            hookSource = 'integration_test/reader_correctness_android_subset_test.dart'
            error = 'C6_SEMANTIC_SETTLE_TIMEOUT'
            firstBadFrame = $null
            firstBadFrameSource = 'not-applicable'
            firstBadFrameArtifact = $null
            screenshotEvidence = [ordered]@{
                source = 'not-applicable'
                frameCount = 0
                firstBadFrameSource = 'not-applicable'
                firstBadFrameArtifact = $null
                windowCompleteness = 'not-applicable'
                missingSlots = @()
                notApplicableSlots = @('before', 'violation', 'after')
                frames = [ordered]@{}
            }
        }
    }
    $metadata = [ordered]@{
        schemaVersion = 2
        bundleType = 'c6-case'
        caseId = $CaseId
        status = $Status
        failureKind = $effectiveFailureKind
        failureMarker = $failureMarker
        invariantHookEnabled = $true
        visualOracleEnabled = $true
        hookProvenance = 'c6-correctness-integration-hook-on'
        hookMode = 'correctness-hook-on'
        hookSource = 'integration_test/reader_correctness_android_subset_test.dart'
        firstBadFrame = $null
        firstBadFrameSource = if ($effectiveFailureKind -eq 'semantic-settle-timeout') {
            'not-applicable'
        }
        else { $null }
        error = if ($Status -eq 'failed') { 'C6_SEMANTIC_SETTLE_TIMEOUT' } else { $null }
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Directory 'summary.json') -Encoding utf8
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Directory 'metadata.json') -Encoding utf8
    Write-TestText (Join-Path $Directory 'operation-trace.jsonl') ($operationEnvelope | ConvertTo-Json -Compress -Depth 12)
    Write-TestText (Join-Path $Directory 'runtime-frame-trace.jsonl') ($runtimeEnvelope | ConvertTo-Json -Compress -Depth 12)
    New-Item -ItemType File -Path (Join-Path $Directory 'invariant-violations.jsonl') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $Directory 'visual-violations.jsonl') -Force | Out-Null
    Write-TestText (Join-Path $Directory 'summary.md') @"
# C6 case summary

- caseId: $CaseId
- status: $Status
- scenario: test
- documentPosition: test
- target: test
- failureKind: $effectiveFailureKind
- runtimeState: ready
- visualObservation: test
- firstBadFrame: not-applicable
"@
    if ($Status -eq 'failed') {
        Write-TestText (Join-Path $Directory 'logcat.txt') 'failure log'
        [byte[]]$video = 1..4
        [IO.File]::WriteAllBytes((Join-Path $Directory 'failure-video.mp4'), $video)
    }
}

function Write-TestDrain([string]$Root, [string]$CaseId) {
    $rootMetadata = [ordered]@{
        schemaVersion = 2
        scenario = 'correctness-subset'
        status = 'passed'
        invariantHookEnabled = $true
        visualOracleEnabled = $true
        hookProvenance = 'c6-correctness-integration-hook-on'
        hookMode = 'correctness-hook-on'
        hookSource = 'integration_test/reader_correctness_android_subset_test.dart'
    }
    $rootMetadata | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $Root 'metadata.json') -Encoding utf8
    $safeCaseName = Get-C6SafeCaseName $CaseId
    $bundle = Join-Path $Root $safeCaseName
    $validation = Test-C6BundleDirectory -Directory $bundle -ExpectedCaseId $CaseId
    $drainFiles = @($validation.files | ForEach-Object {
            [ordered]@{
                name = $_.name
                required = $_.required
                allowEmpty = $_.allowEmpty
                source = $_.source
                reason = $_.reason
                path = $_.path
                exists = $_.exists
                pathIsDirectory = $_.pathIsDirectory
                sizeBytes = $_.sizeBytes
                nonEmpty = $_.nonEmpty
                state = $_.state
                valid = $_.valid
                pullErrors = @()
            }
        })
    $caseReport = [ordered]@{
        caseId = $CaseId
        safeCaseDirectory = $safeCaseName
        remoteDirectory = "/sdcard/c6-evidence/$safeCaseName"
        localDirectory = Join-Path $Root $safeCaseName
        appEvidenceStatus = if ($validation.complete) { 'complete' } else { 'incomplete' }
        appFiles = @()
        bundleStatus = $validation.status
        bundleComplete = $validation.complete
        bundleFailureKind = $validation.failureKind
        firstBadFrameSource = $validation.firstBadFrameSource
        requiredFiles = $drainFiles
        missingRequiredFiles = @($validation.missingRequiredFiles)
        errors = @($validation.errors)
        pullErrors = @()
    }
    [ordered]@{
        schemaVersion = 2
        mode = 'bounded-post-result-drain'
        expectedCaseCount = 1
        expectedCaseIds = @($CaseId)
        markerCaseCount = 1
        markerCaseIds = @($CaseId)
        markerMismatch = $false
        missingMarkerCaseIds = @()
        unexpectedMarkerCaseIds = @()
        drainCaseCount = 1
        appEvidenceCompleteCaseCount = if ($validation.complete) { 1 } else { 0 }
        appEvidenceIncompleteCaseIds = if ($validation.complete) { @() } else { @($CaseId) }
        completeCaseCount = if ($validation.complete) { 1 } else { 0 }
        incompleteCaseIds = if ($validation.complete) { @() } else { @($CaseId) }
        status = if ($validation.complete) { 'complete' } else { 'incomplete' }
        pullErrors = @()
        cases = @($caseReport)
    } | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath (Join-Path $Root 'evidence-drain.json') -Encoding utf8
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('night-reader-c6-evidence-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $runnerSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'run_android_reader_workload.ps1')
    $subsetSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'run_reader_correctness_android_subset.ps1')
    $readerSupportSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\integration_test\reader_test_support.dart')
    Assert-True ($runnerSource.Contains('Copy-C6RemoteFileViaStaging')) 'runner must centralize adb file transport in the staging helper'
    Assert-True ($runnerSource.Contains("'pull', `$RemoteFile, `$stagingDirectory")) 'runner staging helper must pull into a unique staging directory'
    Assert-True (-not $runnerSource.Contains("'pull', `$remoteFile, `$localFile")) 'runner must not pull directly into a case file path'
    Assert-True ($runnerSource.Contains('[System.IO.Path]::GetTempPath()')) 'case evidence staging must use a short system temp root'
    Assert-True ($runnerSource.Contains("'failure-video.mp4'")) 'runner must copy the bounded video into failed bundles'
    Assert-True ($runnerSource.Contains("'night-reader-c6-pull-{0}' -f [Guid]::NewGuid().ToString('N')")) 'every file pull must use a fresh isolated staging root'
    Assert-True ($runnerSource.Contains('Remove-Item -LiteralPath $stagingRoot -Recurse -Force')) 'every isolated staging root must be cleaned in finally'
    Assert-True ($runnerSource.Contains('foreach ($remoteFile in $remoteFiles)')) 'multiple evidence files must be pulled through the serialized helper loop'
    $syntheticTempRoot = 'C:\Users\benny\AppData\Local\Temp'
    $syntheticPullId = 'night-reader-c6-pull-' + ('a' * 32)
    $syntheticGoldenPath = Join-Path (
        Join-Path $syntheticTempRoot $syntheticPullId
    ) 'payload\c6-golden-seed-9132051-penultimateChapterTail.png'
    $syntheticLegacyGoldenPath = Join-Path (
        Join-Path (Join-Path ('C:\r\' + ('r' * 175)) 't') $syntheticPullId
    ) 'c6-golden-seed-9132051-penultimateChapterTail.png'
    Assert-True ($syntheticGoldenPath.Length -lt 260) 'representative temp-staged golden path must remain below the Windows path limit'
    Assert-True ($syntheticLegacyGoldenPath.Length -ge 260) 'the regression probe must cover the previously failing long staging shape'
    $logcatFallbackPattern = [regex]::Escape('$logcatSource = Join-Path $reportDir') + '.*workload-logcat\.txt'
    Assert-True (-not ($runnerSource -match $logcatFallbackPattern)) 'failure logcat must not silently fall back to filtered workload log'
    Assert-True ($runnerSource.Contains("phase = 'final-refresh'")) 'stale final evidence must be reported as final-refresh'
    Assert-True ($runnerSource.Contains('Remove-Item -LiteralPath $stalePath')) 'runner must clear stale final evidence before assembly'
    Assert-True ($runnerSource.Contains('local-case-directory-collision')) 'runner must report a case-directory collision'
    Assert-True ($runnerSource.Contains('transport-refresh')) 'runner must reject stale copies when a later poll refresh fails'
    Assert-True ($runnerSource.Contains('independent-host-recheck')) 'runner must independently recheck the written evidence-drain'
    Assert-True ($runnerSource.Contains('Resolve-C6ContainedPath')) 'runner must canonicalize and contain remote relative paths'
    $directPullPattern = "Invoke-Adb[^\r\n]*'pull'[^\r\n]*" + [regex]::Escape('$reportDir')
    Assert-True (-not ($runnerSource -match $directPullPattern)) 'supplemental failure capture must not pull directly into reportDir'
    Assert-True ($runnerSource.Contains('final root/evidence validation incomplete')) 'runner must preserve a final fail-closed root validation result'
    Assert-True ($runnerSource.Contains('finalRootValidation')) 'runner must persist the final root validation on evidence-drain'
    Assert-True ($runnerSource.Contains('finalEvidenceDrainErrors')) 'runner metadata must retain final evidence-drain errors'
    $exportFunction = [regex]::Match(
        $runnerSource,
        '(?s)function Export-C6EvidenceBundles.*?(?=\r?\nfunction )'
    ).Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($exportFunction)) 'runner export function must remain discoverable'
    Assert-True ($exportFunction -notmatch '\-Failure:\$isFailure') `
        'runner-level testError must not override the app-owned case failure contract'
    Assert-True ($exportFunction -notmatch '\$null -ne \$testError') `
        'runner export must not infer case failure from root testError'
    Assert-True ($runnerSource.Contains('structured hook marker fields did not prove both C6 hooks were enabled')) 'root hook provenance must validate structured marker fields'
    Assert-True ($readerSupportSource.Contains('_waitForMountedHybridScrollView')) 'C6 paced drag must wait for the actual scrollable child after restore'
    Assert-True ($readerSupportSource.Contains('C6_HARNESS_SCROLLABLE_NOT_READY')) 'missing C6 scroll target must remain an explicit harness failure'
    Assert-True ($readerSupportSource.Contains('readyFrameStreak >= 2')) 'C6 scroll target readiness must span two consecutive frames'
    Assert-True ($readerSupportSource.Contains('final targets = find.byType(HybridScrollView);')) 'C6 paced drag must target the actual scrollable child without an unchecked first/last finder'
    Assert-True ($readerSupportSource.Contains('String Function()? reasonBuilder')) 'pumpUntil must support a deferred timeout reason for live diagnostics'
    Assert-True ($readerSupportSource.Contains('requireUserDrag: true')) 'C6 drag operations must require observed user-scroll ownership'
    Assert-True ($readerSupportSource.Contains('C6_HARNESS_NO_USER_DRAG')) 'a C6 no-op gesture must fail closed instead of passing settle'
    $dartSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\integration_test\reader_correctness_android_subset_test.dart')
    Assert-True ($dartSource.Contains('reasonBuilder: () =>')) 'C6 settle timeout must render the latest polled snapshot, not an eager null'
    Assert-True ($dartSource.Contains('READER_C6_EVIDENCE_WRITE_FAILURE')) 'Dart writer failure must be observable without replacing the original failure'
    Assert-True ($dartSource.Contains('C6_SEMANTIC_SETTLE_TIMEOUT')) 'Dart must use an explicit semantic timeout marker'
    Assert-True ($dartSource.Contains("'source': 'not-applicable'")) 'semantic timeout must record screenshot N/A rather than fabricate a frame'
    Assert-True ($subsetSource.Contains('-EnableInvariantHook')) 'C6 batch runner must request hook-on route explicitly'
    Assert-True ($subsetSource.Contains('-RequireRootProvenance')) 'C6 batch runner must validate root hook provenance'
    Assert-True ($subsetSource.Contains('carried batch evidence-drain recheck')) 'resume must revalidate copied evidence with the same validator'
    Assert-True ($subsetSource.Contains('Test-C6EvidenceDrain')) 'batch runner must validate evidence-drain before acceptance'
    Assert-True ($subsetSource.Contains('evidenceDrainComplete')) 'batch result must persist evidence-drain acceptance state'

    $safeOne = Get-C6SafeCaseName 'same:case'
    $safeTwo = Get-C6SafeCaseName 'same?case'
    Assert-True ($safeOne -eq (Get-C6SafeCaseName 'same:case')) 'safe names must be stable'
    Assert-True ($safeOne -ne $safeTwo) 'sanitisation must not collide'
    Assert-True ($safeOne.Length -le 64 -and $safeOne -match '^[A-Za-z0-9._-]+$') 'safe name must be Windows legal'

    $truncatedMarkerCaseId = 'C-single_operation-truncated-marker-case'
    $truncatedMarkerLog =
        'I/flutter (1234): READER_C6_CASE_RESULT ' +
        '{"schemaVersion":2,"bundleType":"c6-case","caseId":"' +
        $truncatedMarkerCaseId +
        '","status":"passed","operationIds":['
    $truncatedMarkerIds = @(Get-C6MarkerCaseIds -Log $truncatedMarkerLog)
    Assert-True ($truncatedMarkerIds.Count -eq 1 -and
        $truncatedMarkerIds[0] -ceq $truncatedMarkerCaseId) `
        'truncated Android result marker must still expose its app-emitted case id'

    $singleVisibleChapter = Join-Path $tempRoot 'single-visible-chapter'
    Write-BaseCase $singleVisibleChapter 'single-visible-chapter-case'
    $singleVisibleChapterRuntimePath = Join-Path $singleVisibleChapter 'runtime-frame-trace.jsonl'
    $singleVisibleChapterRuntime = Get-Content -Raw -LiteralPath $singleVisibleChapterRuntimePath
    $singleVisibleChapterRuntime = $singleVisibleChapterRuntime.Replace(
        '"visibleChapters":[0,1]',
        '"visibleChapters":[0]'
    )
    Write-TestText $singleVisibleChapterRuntimePath $singleVisibleChapterRuntime
    $singleVisibleChapterResult = Test-C6BundleDirectory `
        -Directory $singleVisibleChapter `
        -ExpectedCaseId 'single-visible-chapter-case'
    Assert-True $singleVisibleChapterResult.complete `
        'a JSON array with one visible chapter must remain an array in PowerShell validation'

    $containedBase = Join-Path $tempRoot 'contained-path'
    New-Item -ItemType Directory -Path $containedBase -Force | Out-Null
    $backslashEscapeRejected = $false
    try {
        Resolve-C6ContainedPath `
            -BaseDirectory $containedBase `
            -RelativePath '..\escape.jsonl' | Out-Null
    }
    catch {
        $backslashEscapeRejected = $true
    }
    Assert-True $backslashEscapeRejected 'backslash traversal must be rejected before Join-Path'
    $slashEscapeRejected = $false
    try {
        Resolve-C6ContainedPath `
            -BaseDirectory $containedBase `
            -RelativePath '../escape.jsonl' | Out-Null
    }
    catch {
        $slashEscapeRejected = $true
    }
    Assert-True $slashEscapeRejected 'slash traversal must be rejected'
    $containedPath = Resolve-C6ContainedPath `
        -BaseDirectory $containedBase `
        -RelativePath 'nested\evidence.jsonl'
    Assert-True ($containedPath.StartsWith((Resolve-Path $containedBase).Path, [StringComparison]::OrdinalIgnoreCase)) 'safe path must remain under canonical case directory'

    $genericQueueKind = Get-C6FailureKind `
        -Metadata ([pscustomobject]@{ status = 'failed'; error = 'LayoutPump queue invariant mismatch' }) `
        -Summary ([pscustomobject]@{ status = 'failed'; error = 'LayoutPump queue invariant mismatch' })
    $genericSettlingKind = Get-C6FailureKind `
        -Metadata ([pscustomobject]@{ status = 'failed'; error = 'settling message was emitted by the driver' }) `
        -Summary ([pscustomobject]@{ status = 'failed'; error = 'settling message was emitted by the driver' })
    Assert-True ($genericQueueKind -eq 'unclassified-failure') 'generic queue text must not infer semantic timeout'
    Assert-True ($genericSettlingKind -eq 'unclassified-failure') 'generic settling text must not infer semantic timeout'

    $passedWithErrors = Join-Path $tempRoot 'passed-with-errors'
    Write-BaseCase $passedWithErrors 'passed-with-errors-case'
    foreach ($errorField in @('testError', 'restoreError')) {
        foreach ($path in @(
                (Join-Path $passedWithErrors 'metadata.json'),
                (Join-Path $passedWithErrors 'summary.json')
            )) {
            $object = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
            $object | Add-Member -Force -MemberType NoteProperty -Name $errorField -Value "unexpected $errorField"
            $object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
        }
    }
    $passedWithErrorsResult = Test-C6BundleDirectory `
        -Directory $passedWithErrors `
        -ExpectedCaseId 'passed-with-errors-case'
    Assert-True (-not $passedWithErrorsResult.complete) 'passed case with error metadata must fail closed'
    Assert-True (@($passedWithErrorsResult.errors | Where-Object { $_ -match 'passed .* (testError|restoreError)' }).Count -ge 2) 'passed error metadata must be reported'

    $success = Join-Path $tempRoot 'success'
    Write-BaseCase $success 'success-case'
    $successResult = Test-C6BundleDirectory -Directory $success -ExpectedCaseId 'success-case'
    Assert-True $successResult.complete ("success bundle should be complete: " + (@($successResult.errors) -join '; '))
    Assert-True ($successResult.status -eq 'complete') 'success status should be complete'
    $successManifestPath = Write-C6BundleManifest -Directory $success -Validation $successResult
    $successManifest = Get-Content -Raw -LiteralPath $successManifestPath | ConvertFrom-Json
    Assert-True ($successManifest.status -eq 'complete') 'manifest must carry final validation status'
    Assert-True ($successManifest.transportStatus -eq 'host-validated') 'manifest must identify host validation'
    Assert-True ($successManifest.validationMode -eq 'fail-closed') 'manifest must identify fail-closed validation'
    Assert-True ($successResult.hookProvenance -eq 'c6-correctness-integration-hook-on') 'case validation must retain hook provenance'

    $invalidOperationSchema = Join-Path $tempRoot 'invalid-operation-schema'
    Write-BaseCase $invalidOperationSchema 'invalid-operation-schema-case'
    $invalidOperationPath = Join-Path $invalidOperationSchema 'operation-trace.jsonl'
    $invalidOperationEnvelope = Get-Content -Raw -LiteralPath $invalidOperationPath | ConvertFrom-Json
    $invalidOperationEnvelope.source = 'not-the-reader-writer'
    $invalidOperationEnvelope | ConvertTo-Json -Compress -Depth 12 |
        Set-Content -LiteralPath $invalidOperationPath -Encoding utf8
    $invalidOperationResult = Test-C6BundleDirectory `
        -Directory $invalidOperationSchema `
        -ExpectedCaseId 'invalid-operation-schema-case'
    Assert-True (-not $invalidOperationResult.complete) 'operation trace with wrong source must fail closed'
    Assert-True (@($invalidOperationResult.errors | Where-Object { $_ -match 'operation-trace.jsonl.*source' }).Count -gt 0) 'operation trace provenance error must be reported'

    $invalidRuntimeSchema = Join-Path $tempRoot 'invalid-runtime-schema'
    Write-BaseCase $invalidRuntimeSchema 'invalid-runtime-schema-case'
    $invalidRuntimePath = Join-Path $invalidRuntimeSchema 'runtime-frame-trace.jsonl'
    $invalidRuntimeEnvelope = Get-Content -Raw -LiteralPath $invalidRuntimePath | ConvertFrom-Json
    $invalidRuntimeEnvelope.record.phase = ''
    $invalidRuntimeEnvelope | ConvertTo-Json -Compress -Depth 12 |
        Set-Content -LiteralPath $invalidRuntimePath -Encoding utf8
    $invalidRuntimeResult = Test-C6BundleDirectory `
        -Directory $invalidRuntimeSchema `
        -ExpectedCaseId 'invalid-runtime-schema-case'
    Assert-True (-not $invalidRuntimeResult.complete) 'runtime trace with invalid required field must fail closed'
    Assert-True (@($invalidRuntimeResult.errors | Where-Object { $_ -match 'runtime-frame-trace.jsonl.*phase' }).Count -gt 0) 'runtime trace schema error must be reported'

    $invalidRuntimeShape = Join-Path $tempRoot 'invalid-runtime-shape'
    Write-BaseCase $invalidRuntimeShape 'invalid-runtime-shape-case'
    $invalidRuntimeShapePath = Join-Path $invalidRuntimeShape 'runtime-frame-trace.jsonl'
    $invalidRuntimeShapeEnvelope = Get-Content -Raw -LiteralPath $invalidRuntimeShapePath | ConvertFrom-Json
    $invalidRuntimeShapeEnvelope.record.PSObject.Properties.Remove('visibleKeyRange')
    $invalidRuntimeShapeEnvelope.record.visibleKeys = @('0:0')
    $invalidRuntimeShapeEnvelope | ConvertTo-Json -Compress -Depth 12 |
        Set-Content -LiteralPath $invalidRuntimeShapePath -Encoding utf8
    $invalidRuntimeShapeResult = Test-C6BundleDirectory `
        -Directory $invalidRuntimeShape `
        -ExpectedCaseId 'invalid-runtime-shape-case'
    Assert-True (-not $invalidRuntimeShapeResult.complete) 'runtime trace missing writer schema fields must fail closed'
    Assert-True (@($invalidRuntimeShapeResult.errors | Where-Object { $_ -match 'visibleKeyRange|visibleKeys' }).Count -ge 2) 'runtime trace shape errors must be reported'

    $semantic = Join-Path $tempRoot 'semantic'
    Write-BaseCase $semantic 'semantic-case' 'failed' 'semantic-settle-timeout'
    $semanticResult = Test-C6BundleDirectory -Directory $semantic -ExpectedCaseId 'semantic-case' -Failure
    Assert-True $semanticResult.complete 'semantic timeout without visual frame should be complete'
    $semanticShot = @($semanticResult.files | Where-Object { $_.name -eq 'screenshot-violation.png' })[0]
    Assert-True ($semanticShot.required -eq $false -and $semanticShot.state -eq 'not-applicable') 'semantic screenshots must be N/A'
    Assert-True ($semanticResult.firstBadFrameSource -eq 'not-applicable') 'semantic first bad frame must be N/A'
    $semanticSummaryPath = Join-Path $semantic 'summary.json'
    $semanticMetadataPath = Join-Path $semantic 'metadata.json'
    $semanticSummary = Get-Content -Raw -LiteralPath $semanticSummaryPath | ConvertFrom-Json
    $semanticMetadata = Get-Content -Raw -LiteralPath $semanticMetadataPath | ConvertFrom-Json
    $semanticSummary.firstBadFrameSource = $null
    $semanticMetadata.firstBadFrameSource = $null
    $semanticSummary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $semanticSummaryPath -Encoding utf8
    $semanticMetadata | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $semanticMetadataPath -Encoding utf8
    $semanticMissingNaaResult = Test-C6BundleDirectory `
        -Directory $semantic `
        -ExpectedCaseId 'semantic-case' `
        -Failure
    Assert-True (-not $semanticMissingNaaResult.complete) 'semantic missing explicit N/A must fail closed'
    Assert-True (@($semanticMissingNaaResult.errors | Where-Object { $_ -match 'explicitly be not-applicable' }).Count -ge 2) 'semantic missing N/A must be reported for both case metadata and summary'
    $semanticSummary.firstBadFrameSource = 'not-applicable'
    $semanticMetadata.firstBadFrameSource = 'not-applicable'
    $semanticSummary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $semanticSummaryPath -Encoding utf8
    $semanticMetadata | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $semanticMetadataPath -Encoding utf8
    Write-TestPng (Join-Path $semantic 'screenshot-violation.png')
    $semanticWithScreenshotResult = Test-C6BundleDirectory `
        -Directory $semantic `
        -ExpectedCaseId 'semantic-case' `
        -Failure
    Assert-True (-not $semanticWithScreenshotResult.complete) 'semantic post-detection screenshot must not satisfy N/A contract'
    Assert-True (@($semanticWithScreenshotResult.errors | Where-Object { $_ -match 'N/A/not generated' }).Count -gt 0) 'semantic screenshot presence must be reported'

    $visual = Join-Path $tempRoot 'visual-missing-shot'
    Write-BaseCase $visual 'visual-case' 'failed' 'visual-violation'
    $visualResult = Test-C6BundleDirectory -Directory $visual -ExpectedCaseId 'visual-case' -Failure
    Assert-True (-not $visualResult.complete) 'visual failure without screenshots must fail closed'
    Assert-True (@($visualResult.missingRequiredFiles | Where-Object { $_ -like 'screenshot-*.png' }).Count -eq 3) 'all first-bad screenshots must be required'
    Assert-True (@($visualResult.errors | Where-Object { $_ -match 'visual-violations.jsonl' }).Count -gt 0) 'visual violation evidence cannot be empty'

    $visualComplete = Join-Path $tempRoot 'visual-complete'
    Write-BaseCase $visualComplete 'visual-complete-case' 'failed' 'visual-violation'
    Write-TestText (Join-Path $visualComplete 'visual-violations.jsonl') '{"invariant":"V1"}'
    $visualCompleteSummary = Get-Content -Raw -LiteralPath (Join-Path $visualComplete 'summary.json') | ConvertFrom-Json
    $visualCompleteSummary | Add-Member -Force -MemberType NoteProperty -Name firstBadFrameSource -Value 'C4-retained-raw-frame-window-middle'
    $visualCompleteSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $visualComplete 'summary.json') -Encoding utf8
    foreach ($screenshotName in @('screenshot-before.png', 'screenshot-violation.png', 'screenshot-after.png')) {
        Write-TestPng (Join-Path $visualComplete $screenshotName)
    }
    $visualCompleteResult = Test-C6BundleDirectory -Directory $visualComplete -ExpectedCaseId 'visual-complete-case' -Failure
    Assert-True $visualCompleteResult.complete ("visual failure with all C4 evidence should be complete: " + (@($visualCompleteResult.errors) -join '; '))

    $invariantComplete = Join-Path $tempRoot 'invariant-complete'
    Write-BaseCase $invariantComplete 'invariant-complete-case' 'failed' 'invariant-violation'
    Write-TestText (Join-Path $invariantComplete 'invariant-violations.jsonl') '{"invariant":"I1"}'
    $invariantCompleteSummary = Get-Content -Raw -LiteralPath (Join-Path $invariantComplete 'summary.json') | ConvertFrom-Json
    $invariantCompleteSummary | Add-Member -Force -MemberType NoteProperty -Name firstBadFrameSource -Value 'C4-retained-raw-frame-window-middle'
    $invariantCompleteSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $invariantComplete 'summary.json') -Encoding utf8
    foreach ($screenshotName in @('screenshot-before.png', 'screenshot-violation.png', 'screenshot-after.png')) {
        Write-TestPng (Join-Path $invariantComplete $screenshotName)
    }
    $invariantCompleteResult = Test-C6BundleDirectory -Directory $invariantComplete -ExpectedCaseId 'invariant-complete-case' -Failure
    Assert-True $invariantCompleteResult.complete ("invariant failure with all C4 evidence should be complete: " + (@($invariantCompleteResult.errors) -join '; '))
    Assert-True ($invariantCompleteResult.firstBadFrameSource -eq 'C4-retained-raw-frame-window-middle') 'invariant failure must retain the C4 first-bad frame source'

    $pngBytes = [IO.File]::ReadAllBytes((Join-Path $visualComplete 'screenshot-before.png'))
    $pngBytes[29] = [byte]($pngBytes[29] -bxor 1)
    [IO.File]::WriteAllBytes((Join-Path $visualComplete 'screenshot-before.png'), $pngBytes)
    $crcTamperedResult = Test-C6BundleDirectory `
        -Directory $visualComplete `
        -ExpectedCaseId 'visual-complete-case' `
        -Failure
    Assert-True (-not $crcTamperedResult.complete) 'PNG chunk CRC tampering must fail closed'
    Assert-True (@($crcTamperedResult.errors | Where-Object { $_ -match 'screenshot-before\.png.*CRC' }).Count -gt 0) 'PNG CRC error must be reported'

    $invalidSource = Join-Path $tempRoot 'invalid-first-bad-source'
    Write-BaseCase $invalidSource 'invalid-source-case' 'failed' 'visual-violation'
    Write-TestText (Join-Path $invalidSource 'visual-violations.jsonl') '{"invariant":"V1"}'
    $invalidSourceSummary = Get-Content -Raw -LiteralPath (Join-Path $invalidSource 'summary.json') | ConvertFrom-Json
    $invalidSourceSummary | Add-Member -Force -MemberType NoteProperty -Name firstBadFrameSource -Value 'post-detection'
    $invalidSourceSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $invalidSource 'summary.json') -Encoding utf8
    foreach ($screenshotName in @('screenshot-before.png', 'screenshot-violation.png', 'screenshot-after.png')) {
        Write-TestPng (Join-Path $invalidSource $screenshotName)
    }
    $invalidSourceResult = Test-C6BundleDirectory -Directory $invalidSource -ExpectedCaseId 'invalid-source-case' -Failure
    Assert-True (-not $invalidSourceResult.complete) 'post-detection source must not satisfy visual screenshot contract'
    Assert-True (@($invalidSourceResult.errors | Where-Object { $_ -match 'C4 firstBadFrameSource' }).Count -gt 0) 'invalid screenshot source must be reported'

    $invalidPng = Join-Path $tempRoot 'invalid-png'
    Write-BaseCase $invalidPng 'invalid-png-case' 'failed' 'visual-violation'
    Write-TestText (Join-Path $invalidPng 'visual-violations.jsonl') '{"invariant":"V1"}'
    $invalidPngSummaryPath = Join-Path $invalidPng 'summary.json'
    $invalidPngSummary = Get-Content -Raw -LiteralPath $invalidPngSummaryPath | ConvertFrom-Json
    $invalidPngSummary | Add-Member -Force -MemberType NoteProperty -Name firstBadFrameSource -Value 'C4-retained-raw-frame-window-middle'
    $invalidPngSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidPngSummaryPath -Encoding utf8
    foreach ($screenshotName in @('screenshot-before.png', 'screenshot-violation.png', 'screenshot-after.png')) {
        Write-TestText (Join-Path $invalidPng $screenshotName) 'not a PNG'
    }
    $invalidPngResult = Test-C6BundleDirectory -Directory $invalidPng -ExpectedCaseId 'invalid-png-case' -Failure
    Assert-True (-not $invalidPngResult.complete) 'non-PNG screenshot bytes must fail closed'
    Assert-True (@($invalidPngResult.errors | Where-Object { $_ -match 'invalid-png' }).Count -eq 3) 'all invalid screenshots must be reported'

    $collision = Join-Path $tempRoot 'collision'
    Write-BaseCase $collision 'collision-case'
    Remove-Item -LiteralPath (Join-Path $collision 'operation-trace.jsonl') -Force
    New-Item -ItemType Directory -Path (Join-Path $collision 'operation-trace.jsonl') -Force | Out-Null
    $collisionResult = Test-C6BundleDirectory -Directory $collision -ExpectedCaseId 'collision-case'
    Assert-True (-not $collisionResult.complete) 'directory/file collision must fail closed'
    Assert-True (@($collisionResult.errors | Where-Object { $_ -match 'operation-trace.jsonl' }).Count -gt 0) 'collision error must name the file'

    $fallback = Join-Path $tempRoot 'fallback'
    New-Item -ItemType Directory -Path $fallback -Force | Out-Null
    Write-TestText (Join-Path $fallback 'operation-trace.jsonl') ''
    Write-TestText (Join-Path $fallback 'runtime-frame-trace.jsonl') ''
    $fallbackResult = Test-C6BundleDirectory -Directory $fallback -ExpectedCaseId 'fallback-case' -Failure
    Assert-True (-not $fallbackResult.complete) 'missing fallback metadata must fail closed'
    Assert-True (@($fallbackResult.errors | Where-Object { $_ -match 'metadata.json missing' }).Count -gt 0) 'fallback must not fabricate metadata'

    $malformedTrace = Join-Path $tempRoot 'malformed-trace'
    Write-BaseCase $malformedTrace 'malformed-trace-case'
    Write-TestText (Join-Path $malformedTrace 'runtime-frame-trace.jsonl') 'not-json'
    $malformedTraceResult = Test-C6BundleDirectory -Directory $malformedTrace -ExpectedCaseId 'malformed-trace-case'
    Assert-True (-not $malformedTraceResult.complete) 'malformed JSONL must fail closed'
    Assert-True (@($malformedTraceResult.errors | Where-Object { $_ -match 'runtime-frame-trace.jsonl' }).Count -gt 0) ("malformed JSONL/schema must be reported: " + (@($malformedTraceResult.errors) -join '; '))

    $shortSummary = Join-Path $tempRoot 'short-summary'
    Write-BaseCase $shortSummary 'short-summary-case'
    Write-TestText (Join-Path $shortSummary 'summary.md') "# C6 case summary`n`n- caseId: short-summary-case"
    $shortSummaryResult = Test-C6BundleDirectory -Directory $shortSummary -ExpectedCaseId 'short-summary-case'
    Assert-True (-not $shortSummaryResult.complete) 'summary missing contract fields must fail closed'
    Assert-True (@($shortSummaryResult.errors | Where-Object { $_ -match 'summary\.md: missing required scenario field' }).Count -gt 0) 'summary field omission must be reported'

    $unknown = Join-Path $tempRoot 'unknown-kind'
    Write-BaseCase $unknown 'unknown-kind-case' 'failed' 'made-up-kind'
    $unknownResult = Test-C6BundleDirectory -Directory $unknown -ExpectedCaseId 'unknown-kind-case' -Failure
    Assert-True (-not $unknownResult.complete) 'unknown failure kind must fail closed'
    Assert-True (@($unknownResult.errors | Where-Object { $_ -match 'unclassified' }).Count -gt 0) 'unknown kind must be reported as unclassified'

    $genericTimeout = Join-Path $tempRoot 'generic-timeout'
    Write-BaseCase $genericTimeout 'generic-timeout-case' 'failed'
    $genericTimeoutSummaryPath = Join-Path $genericTimeout 'summary.json'
    $genericTimeoutSummary = Get-Content -Raw -LiteralPath $genericTimeoutSummaryPath | ConvertFrom-Json
    $genericTimeoutSummary.error = 'device command timeout'
    $genericTimeoutSummary | Add-Member -Force -MemberType NoteProperty -Name failureKind -Value $null
    $genericTimeoutSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $genericTimeoutSummaryPath -Encoding utf8
    $genericTimeoutResult = Test-C6BundleDirectory -Directory $genericTimeout -ExpectedCaseId 'generic-timeout-case' -Failure
    Assert-True (-not $genericTimeoutResult.complete) 'generic timeout must not be accepted as semantic settle evidence'
    Assert-True ($genericTimeoutResult.failureKind -eq 'unclassified-failure') 'generic timeout must remain unclassified'

    $conflict = Join-Path $tempRoot 'conflicting-kind'
    Write-BaseCase $conflict 'conflicting-kind-case' 'failed' 'semantic-settle-timeout'
    $conflictMetadataPath = Join-Path $conflict 'metadata.json'
    $conflictMetadata = Get-Content -Raw -LiteralPath $conflictMetadataPath | ConvertFrom-Json
    $conflictMetadata | Add-Member -Force -MemberType NoteProperty -Name failureKind -Value 'visual-violation'
    $conflictMetadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $conflictMetadataPath -Encoding utf8
    $conflictResult = Test-C6BundleDirectory -Directory $conflict -ExpectedCaseId 'conflicting-kind-case' -Failure
    Assert-True (-not $conflictResult.complete) 'conflicting metadata/summary kind must fail closed'
    Assert-True (@($conflictResult.errors | Where-Object { $_ -match 'failureKind' }).Count -gt 0) 'kind conflict must be reported'

    $passedWithViolation = Join-Path $tempRoot 'passed-with-violation'
    Write-BaseCase $passedWithViolation 'passed-with-violation-case'
    $passedSummaryPath = Join-Path $passedWithViolation 'summary.json'
    $passedSummary = Get-Content -Raw -LiteralPath $passedSummaryPath | ConvertFrom-Json
    $passedSummary.runtimeViolations = 1
    $passedSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $passedSummaryPath -Encoding utf8
    $passedResult = Test-C6BundleDirectory -Directory $passedWithViolation -ExpectedCaseId 'passed-with-violation-case'
    Assert-True (-not $passedResult.complete) 'passed summary with violations must fail closed'
    Assert-True (@($passedResult.errors | Where-Object { $_ -match 'violation counters' }).Count -gt 0) 'passed violation counters must be reported'

    $drainSuccess = Join-Path $tempRoot 'drain-success'
    $drainSuccessCase = Join-Path $drainSuccess (Get-C6SafeCaseName 'drain-success-case')
    Write-BaseCase $drainSuccessCase 'drain-success-case'
    Write-TestDrain $drainSuccess 'drain-success-case'
    $drainSuccessResult = Test-C6EvidenceDrain `
        -Directory $drainSuccess `
        -ExpectedCaseIds @('drain-success-case')
    Assert-True $drainSuccessResult.complete ("complete evidence-drain should be accepted: " + (@($drainSuccessResult.errors) -join '; '))
    $drainSuccessProvenanceResult = Test-C6EvidenceDrain `
        -Directory $drainSuccess `
        -ExpectedCaseIds @('drain-success-case') `
        -RequireRootProvenance
    Assert-True $drainSuccessProvenanceResult.complete ("root hook provenance should be accepted: " + (@($drainSuccessProvenanceResult.errors) -join '; '))

    $passedCaseWithRunnerError = Join-Path $tempRoot 'passed-case-with-runner-error'
    $passedCaseWithRunnerErrorCase = Join-Path $passedCaseWithRunnerError (Get-C6SafeCaseName 'passed-case-with-runner-error-case')
    Write-BaseCase $passedCaseWithRunnerErrorCase 'passed-case-with-runner-error-case'
    # Simulate the catch-path's runner diagnostics being available even though
    # the app-owned C6 case itself passed. These files may be retained as
    # optional context, but must not alter the app-owned required contract.
    Write-TestText (Join-Path $passedCaseWithRunnerErrorCase 'logcat.txt') 'runner-level diagnostic'
    [byte[]]$runnerDiagnosticVideo = 1..4
    [IO.File]::WriteAllBytes(
        (Join-Path $passedCaseWithRunnerErrorCase 'failure-video.mp4'),
        $runnerDiagnosticVideo
    )
    $passedCaseValidation = Test-C6BundleDirectory `
        -Directory $passedCaseWithRunnerErrorCase `
        -ExpectedCaseId 'passed-case-with-runner-error-case'
    $passedCaseRequiredNames = @(
        $passedCaseValidation.files |
            Where-Object { [bool]$_.required } |
            ForEach-Object { [string]$_.name }
    )
    Assert-True $passedCaseValidation.complete `
        'a passed app case remains valid when the runner has a separate root error'
    Assert-True ('logcat.txt' -notin $passedCaseRequiredNames -and
        'failure-video.mp4' -notin $passedCaseRequiredNames) `
        'runner-level error must not add failure-only files to a passed case contract'
    Write-TestDrain $passedCaseWithRunnerError 'passed-case-with-runner-error-case'
    Write-TestText (Join-Path $passedCaseWithRunnerError 'metadata.json') @'
{
  "schemaVersion": 2,
  "scenario": "correctness-subset",
  "status": "failed",
  "invariantHookEnabled": true,
  "visualOracleEnabled": true,
  "hookProvenance": "c6-correctness-integration-hook-on",
  "hookMode": "correctness-hook-on",
  "hookSource": "integration_test/reader_correctness_android_subset_test.dart",
  "testError": "runner-level failure after the app case passed"
}
'@
    $passedCaseDrain = Test-C6EvidenceDrain `
        -Directory $passedCaseWithRunnerError `
        -ExpectedCaseIds @('passed-case-with-runner-error-case') `
        -RequireRootProvenance
    Assert-True $passedCaseDrain.complete `
        ("passed case drain must remain complete despite root runner error: " + (@($passedCaseDrain.errors) -join '; '))

    $drainMarkerMismatch = Join-Path $tempRoot 'drain-marker-mismatch'
    $drainMarkerMismatchCase = Join-Path $drainMarkerMismatch (Get-C6SafeCaseName 'drain-marker-case')
    Write-BaseCase $drainMarkerMismatchCase 'drain-marker-case'
    Write-TestDrain $drainMarkerMismatch 'drain-marker-case'
    $markerTamperedDrainPath = Join-Path $drainMarkerMismatch 'evidence-drain.json'
    $markerTamperedDrain = Get-Content -Raw -LiteralPath $markerTamperedDrainPath | ConvertFrom-Json
    $markerTamperedDrain.markerCaseCount = 0
    $markerTamperedDrain.markerCaseIds = @()
    $markerTamperedDrain.missingMarkerCaseIds = @()
    $markerTamperedDrain.unexpectedMarkerCaseIds = @()
    $markerTamperedDrain.markerMismatch = $false
    $markerTamperedDrain | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $markerTamperedDrainPath -Encoding utf8
    $markerMismatchResult = Test-C6EvidenceDrain `
        -Directory $drainMarkerMismatch `
        -ExpectedCaseIds @('drain-marker-case')
    Assert-True (-not $markerMismatchResult.complete) 'marker count/array mismatch must fail closed'
    Assert-True (@($markerMismatchResult.errors | Where-Object { $_ -match 'markerCaseCount|missingMarkerCaseIds|markerMismatch' }).Count -ge 2) 'marker mismatch details must be reported'

    $drainUnexpectedMarker = Join-Path $tempRoot 'drain-unexpected-marker'
    $drainUnexpectedMarkerCase = Join-Path $drainUnexpectedMarker (Get-C6SafeCaseName 'drain-unexpected-case')
    Write-BaseCase $drainUnexpectedMarkerCase 'drain-unexpected-case'
    Write-TestDrain $drainUnexpectedMarker 'drain-unexpected-case'
    $unexpectedMarkerDrainPath = Join-Path $drainUnexpectedMarker 'evidence-drain.json'
    $unexpectedMarkerDrain = Get-Content -Raw -LiteralPath $unexpectedMarkerDrainPath | ConvertFrom-Json
    $unexpectedMarkerDrain.markerCaseCount = 2
    $unexpectedMarkerDrain.markerCaseIds = @('drain-unexpected-case', 'not-requested-case')
    $unexpectedMarkerDrain.missingMarkerCaseIds = @()
    $unexpectedMarkerDrain.unexpectedMarkerCaseIds = @()
    $unexpectedMarkerDrain.markerMismatch = $false
    $unexpectedMarkerDrain | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $unexpectedMarkerDrainPath -Encoding utf8
    $unexpectedMarkerResult = Test-C6EvidenceDrain `
        -Directory $drainUnexpectedMarker `
        -ExpectedCaseIds @('drain-unexpected-case')
    Assert-True (-not $unexpectedMarkerResult.complete) 'unexpected marker id must fail closed'
    Assert-True (@($unexpectedMarkerResult.errors | Where-Object { $_ -match 'unexpectedMarkerCaseIds|markerMismatch|marker arrays' }).Count -gt 0) 'unexpected marker details must be reported'

    $rootHookMismatch = Join-Path $tempRoot 'root-hook-mismatch'
    $rootHookMismatchCase = Join-Path $rootHookMismatch (Get-C6SafeCaseName 'root-hook-case')
    Write-BaseCase $rootHookMismatchCase 'root-hook-case'
    Write-TestDrain $rootHookMismatch 'root-hook-case'
    $rootHookPath = Join-Path $rootHookMismatch 'metadata.json'
    $rootHook = Get-Content -Raw -LiteralPath $rootHookPath | ConvertFrom-Json
    $rootHook.invariantHookEnabled = $false
    $rootHook | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $rootHookPath -Encoding utf8
    $rootHookMismatchResult = Test-C6EvidenceDrain `
        -Directory $rootHookMismatch `
        -ExpectedCaseIds @('root-hook-case') `
        -RequireRootProvenance
    Assert-True (-not $rootHookMismatchResult.complete) 'root hook provenance mismatch must fail closed'
    Assert-True (@($rootHookMismatchResult.errors | Where-Object { $_ -match 'root metadata.*invariantHookEnabled' }).Count -gt 0) 'root hook mismatch must be reported'

    $caseHookMismatch = Join-Path $tempRoot 'case-hook-mismatch'
    Write-BaseCase $caseHookMismatch 'case-hook-mismatch'
    $caseHookMetadataPath = Join-Path $caseHookMismatch 'metadata.json'
    $caseHookMetadata = Get-Content -Raw -LiteralPath $caseHookMetadataPath | ConvertFrom-Json
    $caseHookMetadata.visualOracleEnabled = $false
    $caseHookMetadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $caseHookMetadataPath -Encoding utf8
    $caseHookMismatchResult = Test-C6BundleDirectory `
        -Directory $caseHookMismatch `
        -ExpectedCaseId 'case-hook-mismatch'
    Assert-True (-not $caseHookMismatchResult.complete) 'case hook provenance mismatch must fail closed'
    Assert-True (@($caseHookMismatchResult.errors | Where-Object { $_ -match 'visualOracleEnabled' }).Count -gt 0) 'case hook mismatch must be reported'

    $tamperedDrain = Get-Content -Raw -LiteralPath (Join-Path $drainSuccess 'evidence-drain.json') | ConvertFrom-Json
    $tamperedDrain.cases[0].requiredFiles[0].sizeBytes = [int]$tamperedDrain.cases[0].requiredFiles[0].sizeBytes + 1
    $tamperedDrain | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $drainSuccess 'evidence-drain.json') -Encoding utf8
    $tamperedDrainResult = Test-C6EvidenceDrain `
        -Directory $drainSuccess `
        -ExpectedCaseIds @('drain-success-case')
    Assert-True (-not $tamperedDrainResult.complete) 'tampered drain file size must fail closed'
    Assert-True (@($tamperedDrainResult.errors | Where-Object { $_ -match 'sizeBytes' }).Count -gt 0) 'tampered drain size must be reported'

    $drainSemantic = Join-Path $tempRoot 'drain-semantic'
    $drainSemanticCase = Join-Path $drainSemantic (Get-C6SafeCaseName 'drain-semantic-case')
    Write-BaseCase $drainSemanticCase 'drain-semantic-case' 'failed' 'semantic-settle-timeout'
    Write-TestDrain $drainSemantic 'drain-semantic-case'
    $drainSemanticResult = Test-C6EvidenceDrain `
        -Directory $drainSemantic `
        -ExpectedCaseIds @('drain-semantic-case')
    Assert-True $drainSemanticResult.complete 'semantic timeout without visual first-bad frame should drain successfully'

    $drainVisualMissing = Join-Path $tempRoot 'drain-visual-missing'
    $drainVisualMissingCase = Join-Path $drainVisualMissing (Get-C6SafeCaseName 'drain-visual-missing-case')
    Write-BaseCase $drainVisualMissingCase 'drain-visual-missing-case' 'failed' 'visual-violation'
    Write-TestText (Join-Path $drainVisualMissingCase 'visual-violations.jsonl') '{"invariant":"V1"}'
    $drainVisualSummaryPath = Join-Path $drainVisualMissingCase 'summary.json'
    $drainVisualSummary = Get-Content -Raw -LiteralPath $drainVisualSummaryPath | ConvertFrom-Json
    $drainVisualSummary | Add-Member -Force -MemberType NoteProperty -Name firstBadFrameSource -Value 'C4-retained-raw-frame-window-middle'
    $drainVisualSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $drainVisualSummaryPath -Encoding utf8
    Write-TestDrain $drainVisualMissing 'drain-visual-missing-case'
    $drainVisualResult = Test-C6EvidenceDrain `
        -Directory $drainVisualMissing `
        -ExpectedCaseIds @('drain-visual-missing-case')
    Assert-True (-not $drainVisualResult.complete) 'visual drain without retained screenshots must fail closed'

    $drainCollision = Join-Path $tempRoot 'drain-collision'
    $drainCollisionCase = Join-Path $drainCollision (Get-C6SafeCaseName 'drain-collision-case')
    Write-BaseCase $drainCollisionCase 'drain-collision-case'
    Remove-Item -LiteralPath (Join-Path $drainCollisionCase 'operation-trace.jsonl') -Force
    New-Item -ItemType Directory -Path (Join-Path $drainCollisionCase 'operation-trace.jsonl') -Force | Out-Null
    Write-TestDrain $drainCollision 'drain-collision-case'
    $drainCollisionResult = Test-C6EvidenceDrain `
        -Directory $drainCollision `
        -ExpectedCaseIds @('drain-collision-case')
    Assert-True (-not $drainCollisionResult.complete) 'transport directory collision must fail drain acceptance'

    $drainEmpty = Join-Path $tempRoot 'drain-empty'
    $drainEmptyCase = Join-Path $drainEmpty (Get-C6SafeCaseName 'drain-empty-case')
    Write-BaseCase $drainEmptyCase 'drain-empty-case'
    Write-TestText (Join-Path $drainEmptyCase 'runtime-frame-trace.jsonl') ''
    Write-TestDrain $drainEmpty 'drain-empty-case'
    $drainEmptyResult = Test-C6EvidenceDrain `
        -Directory $drainEmpty `
        -ExpectedCaseIds @('drain-empty-case')
    Assert-True (-not $drainEmptyResult.complete) 'empty runtime trace must fail drain acceptance'

    $drainFallback = Join-Path $tempRoot 'drain-fallback'
    $drainFallbackCase = Join-Path $drainFallback (Get-C6SafeCaseName 'drain-fallback-case')
    New-Item -ItemType Directory -Path $drainFallbackCase -Force | Out-Null
    Write-TestText (Join-Path $drainFallbackCase 'operation-trace.jsonl') ''
    Write-TestText (Join-Path $drainFallbackCase 'runtime-frame-trace.jsonl') ''
    Write-TestDrain $drainFallback 'drain-fallback-case'
    $drainFallbackResult = Test-C6EvidenceDrain `
        -Directory $drainFallback `
        -ExpectedCaseIds @('drain-fallback-case')
    Assert-True (-not $drainFallbackResult.complete) 'fabricated fallback files must fail drain acceptance'

    Write-Host 'C6 evidence bundle tests passed.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
