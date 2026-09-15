[CmdletBinding()]
param(
    [string]$DeviceId = 'emulator-5556'
)

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "ASSERT FAILED: $Message"
    }
}

function Invoke-AdbBounded([string[]]$Arguments, [int]$TimeoutSeconds = 30) {
    $output = & adb @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb $($Arguments -join ' ') failed with exit code ${LASTEXITCODE}: $($output -join [Environment]::NewLine)"
    }
    return @($output)
}

$modulePath = Join-Path $PSScriptRoot 'c6_evidence_bundle.psm1'
Import-Module -Name $modulePath -Force

$runnerPath = Join-Path $PSScriptRoot 'run_android_reader_workload.ps1'
$runnerSource = Get-Content -Raw -LiteralPath $runnerPath
$parseErrors = $null
$tokens = $null
$runnerAst = [System.Management.Automation.Language.Parser]::ParseInput(
    $runnerSource,
    [ref]$tokens,
    [ref]$parseErrors
)
Assert-True (@($parseErrors).Count -eq 0) 'runner must parse before extracting the transport helper'
$copyFunctionAst = $runnerAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Copy-C6RemoteFileViaStaging'
    }, $true)
Assert-True ($null -ne $copyFunctionAst) 'Copy-C6RemoteFileViaStaging must remain available in the runner'
. ([scriptblock]::Create($copyFunctionAst.Extent.Text))

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'night-reader-c6-transport-test-{0}' -f [Guid]::NewGuid().ToString('N')
)
$remotePng = '/sdcard/NightReader-c6-transport-regression.png'
$sourcePng = Join-Path $testRoot 'source.png'
$destination = Join-Path $testRoot (
    ('report-' + ('x' * 70) + '\batch-001\c6-evidence-pulled\cases\' +
        ('case-' + ('y' * 45)) + '\golden\c6-golden-seed-9132051-penultimateChapterTail.png')
)

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $pngBytes = [Convert]::FromBase64String(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
    )
    [System.IO.File]::WriteAllBytes($sourcePng, $pngBytes)

    $state = ((Invoke-AdbBounded @('-s', $DeviceId, 'get-state')) -join '').Trim()
    Assert-True ($state -eq 'device') "ADB device must be ready; observed '$state'"
    Invoke-AdbBounded @('-s', $DeviceId, 'push', $sourcePng, $remotePng) | Out-Null

    # The intentionally long final destination matches the failed report-root
    # shape.  The helper must keep adb's staging destination short and
    # GUID-isolated, then still write the final PNG.
    $script:DeviceId = $DeviceId
    $copiedPath = Copy-C6RemoteFileViaStaging `
        -RemoteFile $remotePng `
        -DestinationPath $destination `
        -TimeoutSeconds 5

    Assert-True (Test-Path -LiteralPath $copiedPath -PathType Leaf) 'pulled PNG must exist at the final destination'
    $pngValidation = Test-C6PngIntegrity -Path $copiedPath
    Assert-True ([bool]$pngValidation.valid) (
        'pulled PNG must pass C6 PNG validation: ' + (@($pngValidation.errors) -join '; ')
    )
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePng).Hash -eq
        (Get-FileHash -Algorithm SHA256 -LiteralPath $copiedPath).Hash) 'pulled PNG bytes must be preserved'

    Write-Host (
        'C6 transport staging regression passed: unique temp staging pulled a valid PNG to a long destination ({0} chars).' -f
        $destination.Length
    )
}
finally {
    try { Invoke-AdbBounded @('-s', $DeviceId, 'shell', 'rm', '-f', $remotePng) | Out-Null } catch { }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
