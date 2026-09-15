[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedDir,

    [Parameter(Mandatory = $true)]
    [string]$ActualDir,

    [Parameter(Mandatory = $true)]
    [string]$ReportPath,

    [int]$ChannelTolerance = 8,

    [double]$MaxBadRatio = 0.001,

    [switch]$ProbeMicroShift
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'C6 golden comparator must run under PowerShell 7: use pwsh -NoProfile.'
}
$repoRoot = Split-Path -Parent $PSScriptRoot
$python = Get-Command python -ErrorAction Stop
$arguments = @(
    (Join-Path $repoRoot 'tool/compare_reader_golden.py'),
    '--expected', (Resolve-Path -LiteralPath $ExpectedDir).Path,
    '--actual', (Resolve-Path -LiteralPath $ActualDir).Path,
    '--report', ([System.IO.Path]::GetFullPath($ReportPath)),
    '--channel-tolerance', $ChannelTolerance,
    '--max-bad-ratio', $MaxBadRatio
)
if ($ProbeMicroShift) { $arguments += '--probe-micro-shift' }
& $python.Source @arguments
exit $LASTEXITCODE
