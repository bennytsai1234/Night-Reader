Set-StrictMode -Version Latest

$script:C6EvidenceBundleSchemaVersion = 2
$script:C6HookProvenance = 'c6-correctness-integration-hook-on'
$script:C6HookMode = 'correctness-hook-on'
$script:C6HookSource = 'integration_test/reader_correctness_android_subset_test.dart'
$script:C6OperationTraceSource = 'C6-ReaderTestHarness.operation-trace.v2'
$script:C6RuntimeTraceSource = 'C6-HybridFrameInvariantRecord.runtime-frame.v2'

function Get-C6SafeCaseName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaseId
    )

    if ([string]::IsNullOrWhiteSpace($CaseId)) {
        throw 'C6 case id 不可為空。'
    }

    # A sanitised prefix alone is not injective: punctuation such as ':' and
    # '?' both become '_'.  Always append a digest so the app writer, adb
    # transport and host exporter have one stable, collision-resistant name.
    $normalized = [regex]::Replace($CaseId, '[^A-Za-z0-9._-]+', '_').Trim(' ', '.')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        $normalized = 'case'
    }
    $prefix = if ($normalized.Length -gt 48) {
        $normalized.Substring(0, 48)
    }
    else {
        $normalized
    }

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($CaseId)
        $digest = [System.BitConverter]::ToString(
            $sha1.ComputeHash($bytes)
        ).Replace('-', '').ToLowerInvariant().Substring(0, 12)
    }
    finally {
        $sha1.Dispose()
    }
    return '{0}-{1}' -f $prefix, $digest
}

function Convert-C6ScalarInt {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) { return 0 }
    try { return [int]$Value }
    catch { return 0 }
}

function Get-C6PropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    # Preserve array-valued JSON properties, including one-element arrays.
    # PowerShell otherwise enumerates the function output and collapses a
    # single-element array to a scalar at the assignment site.
    return ,$property.Value
}

function Get-C6MarkerCaseIds {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Log
    )

    # Android logcat may truncate a long JSON marker line before its closing
    # braces. The case id is emitted near the beginning of the app-owned
    # result/failure marker, so extract that field without requiring a
    # complete JSON object. The case bundle and drain validators still require
    # the complete app-written files; this helper only identifies which case
    # marker was emitted by the app.
    $caseIds = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($Log)) { return @($caseIds) }
    $matches = [regex]::Matches(
        $Log,
        'READER_C6_CASE_(?:FAILURE|RESULT)\s+\{[^\r\n]*?"caseId"\s*:\s*"([^"\r\n]*)"'
    )
    foreach ($match in $matches) {
        $caseId = [string]$match.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($caseId) -and
            -not $caseIds.Contains($caseId)) {
            $caseIds.Add($caseId)
        }
    }
    return @($caseIds)
}

function Convert-C6StringArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @([string]$Value) }
    return @($Value | ForEach-Object { [string]$_ })
}

function Test-C6StringSetEqual {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]]$Left,
        [AllowNull()]
        [string[]]$Right
    )

    $leftValues = @($Left)
    $rightValues = @($Right)
    $leftSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $rightSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($value in $leftValues) { [void]$leftSet.Add([string]$value) }
    foreach ($value in $rightValues) { [void]$rightSet.Add([string]$value) }
    return $leftValues.Count -eq $leftSet.Count -and
        $rightValues.Count -eq $rightSet.Count -and
        $leftSet.Count -eq $rightSet.Count -and
        $leftSet.IsSubsetOf($rightSet)
}

function Resolve-C6ContainedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseDirectory,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'relative path is empty'
    }

    # Device paths are normally POSIX paths, but the value is later converted
    # into a Windows path.  Normalize both separators before checking segments
    # so a crafted `..\escape` cannot bypass a slash-only check.
    $normalized = $RelativePath.Replace('\', '/')
    if ([IO.Path]::IsPathRooted($RelativePath) -or
        $normalized.StartsWith('/', [StringComparison]::Ordinal) -or
        $normalized -match '^[A-Za-z]:' ) {
        throw "relative path is rooted: $RelativePath"
    }
    $segments = @($normalized -split '/')
    if ($segments.Count -eq 0 -or
        @($segments | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0 -or
        @($segments | Where-Object { $_ -match ':' }).Count -gt 0) {
        throw "relative path contains an unsafe segment: $RelativePath"
    }

    $baseFull = [IO.Path]::GetFullPath($BaseDirectory)
    $relativeLocal = $normalized.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $resolved = [IO.Path]::GetFullPath(
        [IO.Path]::Combine($baseFull, $relativeLocal)
    )
    $basePrefix = $baseFull.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($basePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "resolved path escapes the local case directory: $RelativePath"
    }
    return $resolved
}

function Get-C6PngUInt32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,
        [Parameter(Mandatory = $true)]
        [int]$Offset
    )

    if ($Offset -lt 0 -or $Offset + 4 -gt $Bytes.Length) {
        throw 'PNG uint32 extends beyond file bounds'
    }
    return ([uint64]$Bytes[$Offset] * 16777216) +
        ([uint64]$Bytes[$Offset + 1] * 65536) +
        ([uint64]$Bytes[$Offset + 2] * 256) +
        [uint64]$Bytes[$Offset + 3]
}

function Get-C6PngCrc32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    # Keep this dependency-free for the bundled PowerShell 7 runtime.  The
    # value is held as uint64 and masked after every operation because the
    # PNG polynomial's high bit does not fit a signed PowerShell integer.
    [uint64]$crc = 4294967295
    [uint64]$polynomial = 3988292384
    foreach ($byte in $Bytes) {
        $crc = ($crc -bxor [uint64]$byte) -band 4294967295
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 1) -ne 0) {
                $crc = (($crc -shr 1) -bxor $polynomial) -band 4294967295
            }
            else {
                $crc = ($crc -shr 1) -band 4294967295
            }
        }
    }
    return ($crc -bxor 4294967295) -band 4294967295
}

function Test-C6PngIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $width = $null
    $height = $null
    $chunkCount = 0
    $crcCheckedChunks = 0
    $sawIhdr = $false
    $sawIdat = $false
    $sawIend = $false
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw 'PNG file is missing'
        }
        $bytes = [IO.File]::ReadAllBytes($Path)
        $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
        if ($bytes.Length -lt $signature.Length) {
            throw 'PNG is shorter than its signature'
        }
        for ($index = 0; $index -lt $signature.Length; $index++) {
            if ($bytes[$index] -ne $signature[$index]) {
                throw 'PNG signature is invalid'
            }
        }

        $offset = $signature.Length
        while ($offset -lt $bytes.Length) {
            if ($bytes.Length - $offset -lt 12) {
                throw 'PNG chunk header or trailer is truncated'
            }
            $length = Get-C6PngUInt32 -Bytes $bytes -Offset $offset
            if ($length -gt [int]::MaxValue - 12 -or
                $offset + 12 + [int]$length -gt $bytes.Length) {
                throw 'PNG chunk length exceeds file bounds'
            }
            $lengthInt = [int]$length
            $type = [Text.Encoding]::ASCII.GetString($bytes, $offset + 4, 4)
            $dataOffset = $offset + 8
            $crcOffset = $dataOffset + $lengthInt
            $crcInput = New-Object byte[] (4 + $lengthInt)
            [Array]::Copy($bytes, $offset + 4, $crcInput, 0, $crcInput.Length)
            $expectedCrc = Get-C6PngCrc32 -Bytes $crcInput
            $actualCrc = Get-C6PngUInt32 -Bytes $bytes -Offset $crcOffset
            if ($expectedCrc -ne $actualCrc) {
                throw "PNG CRC mismatch in $type chunk"
            }
            $crcCheckedChunks++
            $chunkCount++

            if (-not $sawIhdr -and $type -cne 'IHDR') {
                throw 'PNG first chunk is not IHDR'
            }
            switch ($type) {
                'IHDR' {
                    if ($sawIhdr -or $lengthInt -ne 13) {
                        throw 'PNG IHDR is missing, duplicated, or has an invalid length'
                    }
                    $width = Get-C6PngUInt32 -Bytes $bytes -Offset $dataOffset
                    $height = Get-C6PngUInt32 -Bytes $bytes -Offset ($dataOffset + 4)
                    if ($width -lt 1 -or $height -lt 1 -or
                        $width -gt 65535 -or $height -gt 65535) {
                        throw "PNG dimensions are invalid or unreasonably large: ${width}x${height}"
                    }
                    $bitDepth = $bytes[$dataOffset + 8]
                    $colorType = $bytes[$dataOffset + 9]
                    $compression = $bytes[$dataOffset + 10]
                    $filter = $bytes[$dataOffset + 11]
                    $interlace = $bytes[$dataOffset + 12]
                    $validBitDepth = switch ($colorType) {
                        0 { $bitDepth -in @(1, 2, 4, 8, 16) }
                        2 { $bitDepth -in @(8, 16) }
                        3 { $bitDepth -in @(1, 2, 4, 8) }
                        4 { $bitDepth -in @(8, 16) }
                        6 { $bitDepth -in @(8, 16) }
                        default { $false }
                    }
                    if (-not $validBitDepth) {
                        throw "PNG bit-depth/color-type combination is invalid: $bitDepth/$colorType"
                    }
                    if ($compression -ne 0 -or $filter -ne 0 -or $interlace -gt 1) {
                        throw 'PNG IHDR compression/filter/interlace fields are invalid'
                    }
                    $sawIhdr = $true
                }
                'IDAT' {
                    if ($lengthInt -gt 0) { $sawIdat = $true }
                }
                'IEND' {
                    if ($lengthInt -ne 0) { throw 'PNG IEND must have zero length' }
                    if (-not $sawIhdr -or -not $sawIdat) {
                        throw 'PNG is missing IHDR or non-empty IDAT data'
                    }
                    $sawIend = $true
                    if ($offset + 12 -ne $bytes.Length) {
                        throw 'PNG contains trailing bytes after IEND'
                    }
                }
            }
            $offset = $crcOffset + 4
            if ($sawIend) { break }
        }
        if (-not $sawIend) { throw 'PNG is missing final IEND chunk' }
    }
    catch {
        $errors.Add($_.Exception.Message)
    }
    return [pscustomobject]@{
        valid = $errors.Count -eq 0
        path = $Path
        width = $width
        height = $height
        chunkCount = $chunkCount
        crcCheckedChunks = $crcCheckedChunks
        decodeMode = 'PNG structure + chunk CRC; pixel decompression not performed by PowerShell validator'
        errors = @($errors)
    }
}

function Get-C6HookProvenanceErrors {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Source,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Source) {
        $errors.Add("${Label}: hook provenance source is missing")
        return @($errors)
    }
    $boolFields = @('invariantHookEnabled', 'visualOracleEnabled')
    foreach ($field in $boolFields) {
        $property = $Source.PSObject.Properties[$field]
        if ($null -eq $property) {
            $errors.Add("$Label.$field is missing")
        }
        elseif ($property.Value -isnot [bool] -or -not [bool]$property.Value) {
            $errors.Add("$Label.$field must be boolean true for C6 correctness")
        }
    }
    foreach ($entry in @(
            @{ Name = 'hookProvenance'; Value = $script:C6HookProvenance },
            @{ Name = 'hookMode'; Value = $script:C6HookMode },
            @{ Name = 'hookSource'; Value = $script:C6HookSource }
        )) {
        $actual = Get-C6PropertyValue $Source $entry.Name
        if ([string]$actual -cne [string]$entry.Value) {
            $errors.Add("$Label.$($entry.Name) is not $($entry.Value)")
        }
    }
    return @($errors)
}

function Test-C6IsoTimestamp {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value,
        [Parameter(Mandatory = $true)]
        [string]$FieldName
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return "$FieldName is missing"
    }
    try {
        [void][DateTimeOffset]::Parse([string]$Value)
        return $null
    }
    catch {
        return "$FieldName is not an ISO timestamp"
    }
}

function Get-C6SemanticScreenshotEvidenceErrors {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Metadata,
        [AllowNull()]
        $Summary
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @(
            @{ Name = 'metadata'; Source = $Metadata },
            @{ Name = 'summary'; Source = $Summary }
        )) {
        $source = $entry.Source
        if ($null -eq $source) { continue }
        $firstBadFrameSource = Get-C6PropertyValue $source 'firstBadFrameSource'
        if ([string]$firstBadFrameSource -cne 'not-applicable') {
            $errors.Add(
                "semantic $($entry.Name).firstBadFrameSource must explicitly be not-applicable"
            )
        }
        $firstBadFrame = Get-C6PropertyValue $source 'firstBadFrame'
        if ($null -ne $firstBadFrame -and
            -not [string]::IsNullOrWhiteSpace([string]$firstBadFrame)) {
            $errors.Add("semantic $($entry.Name).firstBadFrame must be null")
        }
    }

    # The case writer carries the semantic N/A declaration inside the machine
    # readable failure evidence. Requiring this shape prevents a summary-only
    # bundle from passing merely because the three PNG files happen to be absent.
    $failureEvidence = Get-C6PropertyValue $Summary 'failureEvidence'
    if ($null -eq $failureEvidence) {
        $errors.Add('semantic summary.failureEvidence is missing')
        return @($errors)
    }
    $screenshotEvidence = Get-C6PropertyValue $failureEvidence 'screenshotEvidence'
    if ($null -eq $screenshotEvidence -or
        $screenshotEvidence -is [ValueType] -or
        $screenshotEvidence -is [string]) {
        $errors.Add('semantic failureEvidence.screenshotEvidence is missing or not an object')
        return @($errors)
    }
    foreach ($field in @(
            'source',
            'firstBadFrameSource',
            'windowCompleteness',
            'missingSlots',
            'notApplicableSlots',
            'frames'
        )) {
        if ($null -eq $screenshotEvidence.PSObject.Properties[$field]) {
            $errors.Add("semantic screenshotEvidence missing $field")
        }
    }
    if ([string](Get-C6PropertyValue $screenshotEvidence 'source') -cne
        'not-applicable') {
        $errors.Add('semantic screenshotEvidence.source must be not-applicable')
    }
    if ([string](Get-C6PropertyValue $screenshotEvidence 'firstBadFrameSource') -cne
        'not-applicable') {
        $errors.Add('semantic screenshotEvidence.firstBadFrameSource must be not-applicable')
    }
    if ([string](Get-C6PropertyValue $screenshotEvidence 'windowCompleteness') -cne
        'not-applicable') {
        $errors.Add('semantic screenshotEvidence.windowCompleteness must be not-applicable')
    }
    $missingSlots = @(Convert-C6StringArray (
        Get-C6PropertyValue $screenshotEvidence 'missingSlots'
    ))
    if ($missingSlots.Count -ne 0) {
        $errors.Add('semantic screenshotEvidence.missingSlots must be empty')
    }
    $notApplicableSlots = @(Convert-C6StringArray (
        Get-C6PropertyValue $screenshotEvidence 'notApplicableSlots'
    ))
    if (-not (Test-C6StringSetEqual `
            -Left $notApplicableSlots `
            -Right @('before', 'violation', 'after'))) {
        $errors.Add(
            'semantic screenshotEvidence.notApplicableSlots must exactly cover before/violation/after'
        )
    }
    $frames = Get-C6PropertyValue $screenshotEvidence 'frames'
    if ($null -eq $frames -or $frames -is [ValueType] -or $frames -is [string]) {
        $errors.Add('semantic screenshotEvidence.frames must be an object')
    }
    elseif (@($frames.PSObject.Properties).Count -ne 0) {
        $errors.Add('semantic screenshotEvidence.frames must be empty')
    }
    $firstBadFrameArtifact = Get-C6PropertyValue $screenshotEvidence 'firstBadFrameArtifact'
    if ($null -ne $firstBadFrameArtifact -and
        -not [string]::IsNullOrWhiteSpace([string]$firstBadFrameArtifact)) {
        $errors.Add('semantic screenshotEvidence.firstBadFrameArtifact must be null')
    }
    return @($errors)
}

function Get-C6NumberValidationErrors {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value,
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [switch]$Integer,
        [switch]$Required
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Value) {
        if ($Required) { $errors.Add("$Label is missing") }
        return @($errors)
    }
    if ($Value -is [bool] -or $Value -isnot [ValueType]) {
        $errors.Add("$Label is not numeric")
        return @($errors)
    }
    try {
        $number = [double]$Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
            $errors.Add("$Label is not finite")
        }
        elseif ($Integer -and $number -ne [Math]::Truncate($number)) {
            $errors.Add("$Label is not an integer")
        }
    }
    catch {
        $errors.Add("$Label is not numeric")
    }
    return @($errors)
}

function Get-C6BlockKeyValidationErrors {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Value -or $Value -is [ValueType] -or $Value -is [string]) {
        $errors.Add("$Label is not a block-key object")
        return @($errors)
    }
    foreach ($field in @('chapterIndex', 'blockIndex')) {
        $property = $Value.PSObject.Properties[$field]
        if ($null -eq $property) {
            $errors.Add("$Label.$field is missing")
            continue
        }
        foreach ($numberError in @(Get-C6NumberValidationErrors `
                -Value $property.Value `
                -Label "$Label.$field" `
                -Integer `
                -Required)) {
            $errors.Add($numberError)
        }
        try {
            if ([double]$property.Value -lt 0) {
                $errors.Add("$Label.$field is negative")
            }
        }
        catch { }
    }
    return @($errors)
}

function Get-C6LocationValidationErrors {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Value) { return @($errors) }
    if ($Value -is [ValueType] -or $Value -is [string]) {
        $errors.Add("$Label is not a location object")
        return @($errors)
    }
    foreach ($field in @('chapterIndex', 'charOffset')) {
        $property = $Value.PSObject.Properties[$field]
        if ($null -eq $property) {
            $errors.Add("$Label.$field is missing")
            continue
        }
        foreach ($numberError in @(Get-C6NumberValidationErrors `
                -Value $property.Value `
                -Label "$Label.$field" `
                -Integer `
                -Required)) {
            $errors.Add($numberError)
        }
        try {
            if ([double]$property.Value -lt 0) {
                $errors.Add("$Label.$field is negative")
            }
        }
        catch { }
    }
    $visualProperty = $Value.PSObject.Properties['visualOffsetPx']
    if ($null -eq $visualProperty) {
        $errors.Add("$Label.visualOffsetPx is missing")
    }
    else {
        foreach ($numberError in @(Get-C6NumberValidationErrors `
                -Value $visualProperty.Value `
                -Label "$Label.visualOffsetPx" `
                -Required)) {
            $errors.Add($numberError)
        }
    }
    return @($errors)
}

function Test-C6OperationTraceFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [bool]$RequireCompletedOperations
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $records = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $errors.Add('operation trace file is missing')
        return [pscustomobject]@{ valid = $false; records = @(); errors = @($errors) }
    }
    $lines = @(Get-Content -LiteralPath $Path |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    foreach ($line in $lines) {
        try {
            $envelope = [string]$line | ConvertFrom-Json -NoEnumerate
        }
        catch {
            $errors.Add("invalid JSONL record: $($_.Exception.Message)")
            continue
        }
        if ($null -eq $envelope -or
            [int](Convert-C6ScalarInt (Get-C6PropertyValue $envelope 'schemaVersion')) -ne 2 -or
            [string](Get-C6PropertyValue $envelope 'source') -cne $script:C6OperationTraceSource) {
            $errors.Add('operation trace record has invalid schemaVersion or source')
            continue
        }
        $record = Get-C6PropertyValue $envelope 'record'
        if ($null -eq $record) {
            $errors.Add('operation trace record has no record object')
            continue
        }
        $records.Add($record)
        foreach ($field in @('index', 'operation', 'startedAt', 'before', 'expectedTransition')) {
            if ($null -eq $record.PSObject.Properties[$field]) {
                $errors.Add("operation trace record missing $field")
            }
        }
        foreach ($numberError in @(Get-C6NumberValidationErrors `
                -Value (Get-C6PropertyValue $record 'index') `
                -Label 'operation trace index' `
                -Integer `
                -Required)) {
            $errors.Add($numberError)
        }
        try {
            if ([double](Get-C6PropertyValue $record 'index') -lt 0) {
                $errors.Add('operation trace index is negative')
            }
        }
        catch { }
        if ([string]::IsNullOrWhiteSpace([string](Get-C6PropertyValue $record 'expectedTransition'))) {
            $errors.Add('operation trace expectedTransition is empty')
        }
        if ([string]::IsNullOrWhiteSpace([string](Get-C6PropertyValue $record 'operation'))) {
            $errors.Add('operation trace operation is empty')
        }
        foreach ($timestampField in @('startedAt', 'endedAt')) {
            $timestampError = Test-C6IsoTimestamp `
                -Value (Get-C6PropertyValue $record $timestampField) `
                -FieldName "operation trace $timestampField"
            if ($null -ne $timestampError) { $errors.Add($timestampError) }
        }
        $before = Get-C6PropertyValue $record 'before'
        if ($null -eq $before -or $before -is [ValueType]) {
            $errors.Add('operation trace before snapshot is missing or not an object')
        }
        $afterProperty = $record.PSObject.Properties['after']
        if ($null -eq $afterProperty) {
            $errors.Add('operation trace after field is missing')
        }
        elseif ($RequireCompletedOperations -and
            ($null -eq $afterProperty.Value -or $afterProperty.Value -is [ValueType])) {
            $errors.Add('passed operation trace after snapshot is missing or not an object')
        }
        foreach ($numberError in @(Get-C6NumberValidationErrors `
                -Value (Get-C6PropertyValue $record 'durationMillis') `
                -Label 'operation trace durationMillis' `
                -Required)) {
            $errors.Add($numberError)
        }
        try {
            if ([double](Get-C6PropertyValue $record 'durationMillis') -lt 0) {
                $errors.Add('operation trace durationMillis is negative')
            }
        }
        catch { }
    }
    if ($records.Count -eq 0) { $errors.Add('operation trace contains no records') }
    return [pscustomobject]@{
        valid = $errors.Count -eq 0
        records = @($records)
        errors = @($errors)
    }
}

function Test-C6RuntimeTraceFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $records = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $errors.Add('runtime trace file is missing')
        return [pscustomobject]@{ valid = $false; records = @(); errors = @($errors) }
    }
    $lines = @(Get-Content -LiteralPath $Path |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    foreach ($line in $lines) {
        try {
            $envelope = [string]$line | ConvertFrom-Json -NoEnumerate
        }
        catch {
            $errors.Add("invalid JSONL record: $($_.Exception.Message)")
            continue
        }
        if ($null -eq $envelope -or
            [int](Convert-C6ScalarInt (Get-C6PropertyValue $envelope 'schemaVersion')) -ne 2 -or
            [string](Get-C6PropertyValue $envelope 'source') -cne $script:C6RuntimeTraceSource) {
            $errors.Add('runtime trace record has invalid schemaVersion or source')
            continue
        }
        $record = Get-C6PropertyValue $envelope 'record'
        if ($null -eq $record) {
            $errors.Add('runtime trace record has no record object')
            continue
        }
        $records.Add($record)
        $requiredFields = @(
            'timestampMicros', 'phase', 'scrollOffset', 'viewportHeight',
            'dragging', 'isScrolling', 'restoreLocked',
            'initialRestoreCompleted', 'epoch', 'layoutGeneration',
            'documentIndexRevision', 'resetGeneration',
            'indexBindingResetGeneration', 'indexCenter',
            'visibleKeyCount', 'visibleKeyRange', 'visibleKeys',
            'visibleChapters', 'missingParagraphCount',
            'unloadedChapterCount', 'dominantVisibleChapter',
            'anchorVisibleChapter', 'displayedProgressChapter',
            'pendingChapterJumpTarget', 'pumpQueueDepth', 'scrollPixels',
            'minScrollExtent', 'maxScrollExtent', 'scrollActivity',
            'scrollVelocity', 'operationTokenId', 'operationIsCurrent',
            'chapterCount', 'errorPresent'
        )
        foreach ($field in $requiredFields) {
            if ($null -eq $record.PSObject.Properties[$field]) {
                $errors.Add("runtime trace record missing $field")
            }
        }
        foreach ($field in @(
                'timestampMicros', 'epoch', 'layoutGeneration',
                'documentIndexRevision', 'resetGeneration',
                'indexBindingResetGeneration', 'visibleKeyCount',
                'missingParagraphCount', 'unloadedChapterCount',
                'pumpQueueDepth', 'chapterCount'
            )) {
            foreach ($numberError in @(Get-C6NumberValidationErrors `
                    -Value (Get-C6PropertyValue $record $field) `
                    -Label "runtime trace $field" `
                    -Integer `
                    -Required)) {
                $errors.Add($numberError)
            }
        }
        foreach ($field in @(
                'scrollOffset', 'viewportHeight', 'scrollPixels',
                'minScrollExtent', 'maxScrollExtent', 'scrollVelocity',
                'operationTokenId', 'dominantVisibleChapter',
                'anchorVisibleChapter', 'displayedProgressChapter'
            )) {
            $integerField = $field -in @(
                'operationTokenId',
                'dominantVisibleChapter',
                'anchorVisibleChapter',
                'displayedProgressChapter'
            )
            foreach ($numberError in @(Get-C6NumberValidationErrors `
                    -Value (Get-C6PropertyValue $record $field) `
                    -Label "runtime trace $field" `
                    -Integer:$integerField)) {
                $errors.Add($numberError)
            }
        }
        foreach ($field in @(
                'dragging', 'isScrolling', 'restoreLocked',
                'initialRestoreCompleted', 'operationIsCurrent', 'errorPresent'
            )) {
            $property = $record.PSObject.Properties[$field]
            if ($null -eq $property -or $property.Value -isnot [bool]) {
                $errors.Add("runtime trace $field is not boolean")
            }
        }
        if ([string]::IsNullOrWhiteSpace([string](Get-C6PropertyValue $record 'phase')) -or
            [string]::IsNullOrWhiteSpace([string](Get-C6PropertyValue $record 'scrollActivity'))) {
            $errors.Add('runtime trace phase or scrollActivity is empty')
        }
        foreach ($keyError in @(Get-C6BlockKeyValidationErrors `
                -Value (Get-C6PropertyValue $record 'indexCenter') `
                -Label 'runtime trace indexCenter')) {
            $errors.Add($keyError)
        }
        $pendingLocation = Get-C6PropertyValue $record 'pendingChapterJumpTarget'
        foreach ($locationError in @(Get-C6LocationValidationErrors `
                -Value $pendingLocation `
                -Label 'runtime trace pendingChapterJumpTarget')) {
            $errors.Add($locationError)
        }
        $visibleKeyRange = Get-C6PropertyValue $record 'visibleKeyRange'
        if ($null -ne $visibleKeyRange) {
            foreach ($keyError in @(Get-C6BlockKeyValidationErrors `
                    -Value (Get-C6PropertyValue $visibleKeyRange 'first') `
                    -Label 'runtime trace visibleKeyRange.first')) {
                $errors.Add($keyError)
            }
            foreach ($keyError in @(Get-C6BlockKeyValidationErrors `
                    -Value (Get-C6PropertyValue $visibleKeyRange 'last') `
                    -Label 'runtime trace visibleKeyRange.last')) {
                $errors.Add($keyError)
            }
        }
        foreach ($field in @('visibleKeys', 'visibleChapters')) {
            $value = Get-C6PropertyValue $record $field
            if ($null -eq $value -or $value -isnot [array]) {
                $errors.Add("runtime trace $field is not an array")
            }
            elseif ($field -eq 'visibleKeys') {
                $arrayValue = @($value)
                for ($keyIndex = 0; $keyIndex -lt $arrayValue.Count; $keyIndex++) {
                    foreach ($keyError in @(Get-C6BlockKeyValidationErrors `
                            -Value $arrayValue[$keyIndex] `
                            -Label "runtime trace visibleKeys[$keyIndex]")) {
                        $errors.Add($keyError)
                    }
                }
            }
            else {
                $arrayValue = @($value)
                for ($chapterIndex = 0; $chapterIndex -lt $arrayValue.Count; $chapterIndex++) {
                    foreach ($numberError in @(Get-C6NumberValidationErrors `
                            -Value $arrayValue[$chapterIndex] `
                            -Label "runtime trace visibleChapters[$chapterIndex]" `
                            -Integer `
                            -Required)) {
                        $errors.Add($numberError)
                    }
                }
            }
        }
        $visibleKeys = @(
            $visibleKeysValue = Get-C6PropertyValue $record 'visibleKeys'
            if ($null -ne $visibleKeysValue) { $visibleKeysValue }
        )
        $visibleKeyCount = Get-C6PropertyValue $record 'visibleKeyCount'
        try {
            if ([int]$visibleKeyCount -ne $visibleKeys.Count) {
                $errors.Add('runtime trace visibleKeyCount disagrees with visibleKeys length')
            }
        }
        catch { }
        $visibleChapters = @(
            $visibleChaptersValue = Get-C6PropertyValue $record 'visibleChapters'
            if ($null -ne $visibleChaptersValue) { $visibleChaptersValue }
        )
        if ($visibleChapters.Count -gt 0) {
            $distinctChapters = @($visibleChapters | Select-Object -Unique)
            if ($distinctChapters.Count -ne $visibleChapters.Count) {
                $errors.Add('runtime trace visibleChapters contains duplicate values')
            }
        }
        foreach ($field in @('missingParagraphCount', 'unloadedChapterCount', 'pumpQueueDepth', 'chapterCount')) {
            try {
                if ([double](Get-C6PropertyValue $record $field) -lt 0) {
                    $errors.Add("runtime trace $field is negative")
                }
            }
            catch { }
        }
    }
    if ($records.Count -eq 0) { $errors.Add('runtime trace contains no records') }
    return [pscustomobject]@{
        valid = $errors.Count -eq 0
        records = @($records)
        errors = @($errors)
    }
}

function Get-C6FailureKind {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Metadata,
        [AllowNull()]
        $Summary
    )

    $explicitUnknown = $false
    $knownFailureKinds = @(
        'passed',
        'semantic-settle-timeout',
        'invariant-violation',
        'visual-violation',
        'unclassified-failure'
    )
    $knownFailureMarkers = @{
        'C6_CASE_PASSED' = 'passed'
        'C6_SEMANTIC_SETTLE_TIMEOUT' = 'semantic-settle-timeout'
        'C6_INVARIANT_VIOLATION' = 'invariant-violation'
        'C6_VISUAL_VIOLATION' = 'visual-violation'
        'C6_UNCLASSIFIED_FAILURE' = 'unclassified-failure'
    }
    foreach ($source in @($Summary, $Metadata)) {
        if ($null -eq $source) { continue }
        foreach ($propertyName in @('failureKind', 'failureType')) {
            $property = $source.PSObject.Properties[$propertyName]
            if ($null -ne $property -and
                -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $value = [string]$property.Value
                if ($knownFailureKinds -contains $value) {
                    return $value
                }
                # An explicit but unknown classification is malformed input.
                # Do not silently replace it with an inferred kind from an
                # error string or a partial counter set.
                $explicitUnknown = $true
            }
        }
        foreach ($propertyName in @('failureMarker', 'failureCode')) {
            $property = $source.PSObject.Properties[$propertyName]
            if ($null -ne $property -and
                -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $marker = [string]$property.Value
                if ($knownFailureMarkers.ContainsKey($marker)) {
                    if ($knownFailureMarkers[$marker] -eq 'unclassified-failure') {
                        $explicitUnknown = $true
                    }
                    else {
                        return $knownFailureMarkers[$marker]
                    }
                }
                else {
                    $explicitUnknown = $true
                }
            }
        }
        $failureEvidence = $source.PSObject.Properties['failureEvidence']
        if ($null -ne $failureEvidence -and $null -ne $failureEvidence.Value) {
            foreach ($propertyName in @('failureKind', 'failureType')) {
                $nested = $failureEvidence.Value.PSObject.Properties[$propertyName]
                if ($null -ne $nested -and
                    -not [string]::IsNullOrWhiteSpace([string]$nested.Value)) {
                    $value = [string]$nested.Value
                    if ($knownFailureKinds -contains $value) {
                        return $value
                    }
                    $explicitUnknown = $true
                }
            }
            foreach ($propertyName in @('failureMarker', 'failureCode')) {
                $nested = $failureEvidence.Value.PSObject.Properties[$propertyName]
                if ($null -ne $nested -and
                    -not [string]::IsNullOrWhiteSpace([string]$nested.Value)) {
                    $marker = [string]$nested.Value
                    if ($knownFailureMarkers.ContainsKey($marker)) {
                        if ($knownFailureMarkers[$marker] -eq 'unclassified-failure') {
                            $explicitUnknown = $true
                        }
                        else {
                            return $knownFailureMarkers[$marker]
                        }
                    }
                    else {
                        $explicitUnknown = $true
                    }
                }
            }
        }
    }

    if ($explicitUnknown) { return 'unclassified-failure' }

    $visualViolations = 0
    $crossOracleViolations = 0
    $runtimeViolations = 0
    $temporalViolations = 0
    if ($null -ne $Summary) {
        $visualViolations = Convert-C6ScalarInt (Get-C6PropertyValue $Summary 'visualViolations')
        $crossOracleViolations = Convert-C6ScalarInt (Get-C6PropertyValue $Summary 'crossOracleViolations')
        $runtimeViolations = Convert-C6ScalarInt (Get-C6PropertyValue $Summary 'runtimeViolations')
        $temporalViolations = Convert-C6ScalarInt (Get-C6PropertyValue $Summary 'temporalViolations')
    }
    if ($visualViolations -gt 0 -or $crossOracleViolations -gt 0) {
        return 'visual-violation'
    }
    if ($runtimeViolations -gt 0 -or $temporalViolations -gt 0) {
        return 'invariant-violation'
    }

    if ($null -ne $Summary -and [string](Get-C6PropertyValue $Summary 'status') -eq 'passed') {
        return 'passed'
    }
    return 'unclassified-failure'
}

function Get-C6BundleFileContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FailureKind,
        [Parameter(Mandatory = $true)]
        [bool]$IsFailure,
        [bool]$RequireInvariantEvidence = $false,
        [bool]$RequireVisualEvidence = $false
    )

    $needsFirstBadScreenshots = $FailureKind -in @(
        'visual-violation',
        'invariant-violation'
    )
    $screenshotsReason = if ($needsFirstBadScreenshots) {
        'visual-or-invariant failure requires C4 retained before/violation/after frames'
    }
    elseif ($FailureKind -eq 'semantic-settle-timeout') {
        'semantic settle/queue timeout has no visual first-bad frame; screenshots are not-applicable'
    }
    else {
        'unclassified failure cannot be accepted without explicit visual classification'
    }

    return @(
        [ordered]@{
            name = 'metadata.json'
            required = $true
            allowEmpty = $false
            source = 'app'
            reason = 'case identity and execution metadata'
        },
        [ordered]@{
            name = 'operation-trace.jsonl'
            required = $true
            allowEmpty = $false
            source = 'app'
            reason = 'operation boundary evidence'
        },
        [ordered]@{
            name = 'runtime-frame-trace.jsonl'
            required = $true
            allowEmpty = $false
            source = 'app'
            reason = 'bounded runtime frame evidence'
        },
        [ordered]@{
            name = 'invariant-violations.jsonl'
            required = $true
            allowEmpty = -not $RequireInvariantEvidence
            source = 'app'
            reason = if ($RequireInvariantEvidence) {
                'runtime/temporal violation was observed; invariant evidence must be non-empty'
            }
            else {
                'empty is valid because no runtime/temporal violation was observed'
            }
        },
        [ordered]@{
            name = 'visual-violations.jsonl'
            required = $true
            allowEmpty = -not $RequireVisualEvidence
            source = 'app'
            reason = if ($RequireVisualEvidence) {
                'visual/cross-oracle violation was observed; visual evidence must be non-empty'
            }
            else {
                'empty is valid because no visual/cross-oracle violation was observed'
            }
        },
        [ordered]@{
            name = 'logcat.txt'
            required = $IsFailure
            allowEmpty = $false
            source = 'runner'
            reason = 'failure-time device log'
        },
        [ordered]@{
            name = 'summary.json'
            required = $true
            allowEmpty = $false
            source = 'app'
            reason = 'machine-readable case outcome'
        },
        [ordered]@{
            name = 'summary.md'
            required = $true
            allowEmpty = $false
            source = 'app'
            reason = 'human-readable case outcome'
        },
        [ordered]@{
            name = 'failure-video.mp4'
            required = $IsFailure
            allowEmpty = $false
            source = 'runner'
            reason = 'bounded post-detection context; not a first-bad-frame oracle'
        },
        [ordered]@{
            name = 'screenshot-before.png'
            required = $needsFirstBadScreenshots
            allowEmpty = $false
            source = 'app-c4-retained-window'
            reason = $screenshotsReason
        },
        [ordered]@{
            name = 'screenshot-violation.png'
            required = $needsFirstBadScreenshots
            allowEmpty = $false
            source = 'app-c4-retained-window'
            reason = $screenshotsReason
        },
        [ordered]@{
            name = 'screenshot-after.png'
            required = $needsFirstBadScreenshots
            allowEmpty = $false
            source = 'app-c4-retained-window'
            reason = $screenshotsReason
        }
    )
}

function Get-C6OptionalEvidenceFileNames {
    return @(
        'invariant-action-observations.jsonl',
        'visual-action-observations.jsonl',
        'bundle-manifest.json'
    )
}

function Get-C6JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $raw = Get-Content -Raw -LiteralPath $Path
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return $raw | ConvertFrom-Json -NoEnumerate
    }
    catch {
        return $null
    }
}

function Get-C6BundleFileStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        $Contract
    )

    $path = Join-Path $Directory ([string]$Contract.name)
    $existsAsFile = Test-Path -LiteralPath $path -PathType Leaf
    $existsAsDirectory = Test-Path -LiteralPath $path -PathType Container
    $size = if ($existsAsFile) { (Get-Item -LiteralPath $path).Length } else { 0 }
    $nonEmpty = $existsAsFile -and $size -gt 0
    $valid = if (-not [bool]$Contract.required) {
        $true
    }
    elseif (-not $existsAsFile -or $existsAsDirectory) {
        $false
    }
    else {
        [bool]$Contract.allowEmpty -or $nonEmpty
    }
    $state = if ($existsAsDirectory) {
        'path-collision-directory'
    }
    elseif (-not $existsAsFile) {
        if ([bool]$Contract.required) { 'missing-required' } else { 'not-applicable' }
    }
    elseif (-not $nonEmpty -and -not [bool]$Contract.allowEmpty) {
        'empty-required'
    }
    elseif (-not $nonEmpty) {
        'present-empty-allowed'
    }
    else {
        'present'
    }

    return [ordered]@{
        name = [string]$Contract.name
        required = [bool]$Contract.required
        allowEmpty = [bool]$Contract.allowEmpty
        source = [string]$Contract.source
        reason = [string]$Contract.reason
        path = $path
        exists = $existsAsFile
        pathIsDirectory = $existsAsDirectory
        sizeBytes = [long]$size
        nonEmpty = $nonEmpty
        state = $state
        valid = $valid
    }
}

function Test-C6BundleDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [string]$ExpectedCaseId = '',
        [switch]$Failure
    )

    $metadataPath = Join-Path $Directory 'metadata.json'
    $summaryPath = Join-Path $Directory 'summary.json'
    $metadata = Get-C6JsonFile $metadataPath
    $summary = Get-C6JsonFile $summaryPath
    $caseId = ''
    foreach ($source in @($summary, $metadata)) {
        if ($null -ne $source -and
            $null -ne $source.PSObject.Properties['caseId'] -and
            -not [string]::IsNullOrWhiteSpace([string]$source.caseId)) {
            $caseId = [string]$source.caseId
            break
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCaseId)) {
        $caseId = $ExpectedCaseId
    }

    $summaryStatus = [string](Get-C6PropertyValue $summary 'status')
    $metadataStatus = [string](Get-C6PropertyValue $metadata 'status')
    $isFailure = [bool]$Failure
    if (-not $isFailure -and
        ($summaryStatus -eq 'failed' -or $metadataStatus -eq 'failed')) {
        $isFailure = $true
    }
    $failureKind = Get-C6FailureKind -Metadata $metadata -Summary $summary
    $runtimeViolations = Convert-C6ScalarInt (Get-C6PropertyValue $summary 'runtimeViolations')
    $temporalViolations = Convert-C6ScalarInt (Get-C6PropertyValue $summary 'temporalViolations')
    $visualViolations = Convert-C6ScalarInt (Get-C6PropertyValue $summary 'visualViolations')
    $crossOracleViolations = Convert-C6ScalarInt (Get-C6PropertyValue $summary 'crossOracleViolations')
    $requireInvariantEvidence =
        $failureKind -eq 'invariant-violation' -or
        $runtimeViolations -gt 0 -or
        $temporalViolations -gt 0
    $requireVisualEvidence =
        $failureKind -eq 'visual-violation' -or
        $visualViolations -gt 0 -or
        $crossOracleViolations -gt 0
    $contracts = @(Get-C6BundleFileContract `
            -FailureKind $failureKind `
            -IsFailure $isFailure `
            -RequireInvariantEvidence $requireInvariantEvidence `
            -RequireVisualEvidence $requireVisualEvidence)
    $files = @($contracts | ForEach-Object {
            Get-C6BundleFileStatus -Directory $Directory -Contract $_
        })
    $errors = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        $errors.Add('bundle directory missing')
    }
    if ($null -eq $metadata) { $errors.Add('metadata.json missing or invalid JSON') }
    if ($null -eq $summary) { $errors.Add('summary.json missing or invalid JSON') }
    $declaredFailureKinds = [System.Collections.Generic.List[string]]::new()
    foreach ($source in @($summary, $metadata)) {
        if ($null -eq $source) { continue }
        foreach ($propertyName in @('failureKind', 'failureType')) {
            $property = $source.PSObject.Properties[$propertyName]
            if ($null -ne $property -and
                -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $declaredFailureKinds.Add([string]$property.Value)
            }
        }
        $failureEvidence = $source.PSObject.Properties['failureEvidence']
        if ($null -ne $failureEvidence -and $null -ne $failureEvidence.Value) {
            $nested = $failureEvidence.Value.PSObject.Properties['failureKind']
            if ($null -ne $nested -and
                -not [string]::IsNullOrWhiteSpace([string]$nested.Value)) {
                $declaredFailureKinds.Add([string]$nested.Value)
            }
        }
    }
    $distinctDeclaredFailureKinds = @(
        $declaredFailureKinds | Select-Object -Unique
    )
    if ($distinctDeclaredFailureKinds.Count -gt 1) {
        $errors.Add('metadata and summary failureKind values do not match')
    }
    elseif ($distinctDeclaredFailureKinds.Count -eq 1 -and
        $distinctDeclaredFailureKinds[0] -cne $failureKind) {
        $errors.Add('declared failureKind does not match validated failure kind')
    }
    $declaredFailureMarkers = [System.Collections.Generic.List[string]]::new()
    foreach ($source in @($summary, $metadata)) {
        if ($null -eq $source) { continue }
        foreach ($propertyName in @('failureMarker', 'failureCode')) {
            $property = $source.PSObject.Properties[$propertyName]
            if ($null -ne $property -and
                -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $declaredFailureMarkers.Add([string]$property.Value)
            }
        }
        $failureEvidence = $source.PSObject.Properties['failureEvidence']
        if ($null -ne $failureEvidence -and $null -ne $failureEvidence.Value) {
            foreach ($propertyName in @('failureMarker', 'failureCode')) {
                $nested = $failureEvidence.Value.PSObject.Properties[$propertyName]
                if ($null -ne $nested -and
                    -not [string]::IsNullOrWhiteSpace([string]$nested.Value)) {
                    $declaredFailureMarkers.Add([string]$nested.Value)
                }
            }
        }
    }
    $distinctDeclaredFailureMarkers = @(
        $declaredFailureMarkers | Select-Object -Unique
    )
    $expectedFailureMarker = switch ($failureKind) {
        'passed' { 'C6_CASE_PASSED' }
        'semantic-settle-timeout' { 'C6_SEMANTIC_SETTLE_TIMEOUT' }
        'invariant-violation' { 'C6_INVARIANT_VIOLATION' }
        'visual-violation' { 'C6_VISUAL_VIOLATION' }
        default { 'C6_UNCLASSIFIED_FAILURE' }
    }
    if ($distinctDeclaredFailureMarkers.Count -ne 1 -or
        $distinctDeclaredFailureMarkers[0] -cne $expectedFailureMarker) {
        $errors.Add("failure marker must be exactly $expectedFailureMarker")
    }
    foreach ($sourceName in @('metadata', 'summary')) {
        $source = if ($sourceName -eq 'metadata') { $metadata } else { $summary }
        foreach ($hookError in @(Get-C6HookProvenanceErrors `
                -Source $source `
                -Label $sourceName)) {
            $errors.Add($hookError)
        }
    }
    if ($null -ne $metadata -and $null -ne $summary) {
        foreach ($field in @(
                'invariantHookEnabled', 'visualOracleEnabled',
                'hookProvenance', 'hookMode', 'hookSource'
            )) {
            if ([string](Get-C6PropertyValue $metadata $field) -cne
                [string](Get-C6PropertyValue $summary $field)) {
                $errors.Add("metadata and summary $field values do not match")
            }
        }
    }
    foreach ($sourceName in @('metadata', 'summary')) {
        $source = if ($sourceName -eq 'metadata') { $metadata } else { $summary }
        if ($null -eq $source) { continue }
        $schemaVersion = Get-C6PropertyValue $source 'schemaVersion'
        if ([int](Convert-C6ScalarInt $schemaVersion) -ne $script:C6EvidenceBundleSchemaVersion) {
            $errors.Add("$sourceName.json: unsupported or missing schemaVersion")
        }
        $bundleType = [string](Get-C6PropertyValue $source 'bundleType')
        if ($bundleType -cne 'c6-case') {
            $errors.Add("$sourceName.json: bundleType is not c6-case")
        }
        $sourceCaseId = [string](Get-C6PropertyValue $source 'caseId')
        if ([string]::IsNullOrWhiteSpace($sourceCaseId)) {
            $errors.Add("$sourceName.json: caseId is missing")
        }
    }
    if ($null -ne $metadata -and $null -ne $summary -and
        -not [string]::IsNullOrWhiteSpace([string](Get-C6PropertyValue $metadata 'caseId')) -and
        -not [string]::IsNullOrWhiteSpace([string](Get-C6PropertyValue $summary 'caseId')) -and
        [string](Get-C6PropertyValue $metadata 'caseId') -cne
        [string](Get-C6PropertyValue $summary 'caseId')) {
        $errors.Add('metadata and summary caseId values do not match')
    }
    if ($null -ne $summary -and
        $summaryStatus -notin @('passed', 'failed')) {
        $errors.Add('summary status is missing or invalid')
    }
    if ($null -ne $metadata -and
        $metadataStatus -notin @('passed', 'failed')) {
        $errors.Add('metadata status is missing or invalid')
    }
    if ($null -ne $summary -and $null -ne $metadata -and
        $summaryStatus -in @('passed', 'failed') -and
        $metadataStatus -in @('passed', 'failed') -and
        $summaryStatus -cne $metadataStatus) {
        $errors.Add('metadata and summary status values do not match')
    }
    if ($isFailure -and $failureKind -eq 'passed') {
        $errors.Add('failed bundle is classified as passed')
    }
    if ($null -ne $summary -and
        $summaryStatus -eq 'passed' -and
        $failureKind -ne 'passed') {
        $errors.Add('passed summary has a non-passed failure kind')
    }
    $violationCount = $runtimeViolations + $temporalViolations +
        $visualViolations + $crossOracleViolations
    if ($null -ne $summary -and $summaryStatus -eq 'passed' -and
        $violationCount -gt 0) {
        $errors.Add('passed summary contains violation counters')
    }
    if ($null -ne $summary -and $summaryStatus -eq 'passed') {
        foreach ($sourceName in @('metadata', 'summary')) {
            $source = if ($sourceName -eq 'metadata') { $metadata } else { $summary }
            foreach ($field in @(
                    'error', 'testError', 'restoreError', 'failure', 'stackTrace'
                )) {
                $value = Get-C6PropertyValue $source $field
                if ($null -ne $value -and
                    -not [string]::IsNullOrWhiteSpace([string]$value)) {
                    $errors.Add("passed $sourceName contains non-empty $field")
                }
            }
            $failureEvidence = Get-C6PropertyValue $source 'failureEvidence'
            if ($null -ne $failureEvidence) {
                $errors.Add("passed $sourceName contains failureEvidence")
            }
            $firstBadFrame = Get-C6PropertyValue $source 'firstBadFrame'
            if ($null -ne $firstBadFrame -and
                -not [string]::IsNullOrWhiteSpace([string]$firstBadFrame)) {
                $errors.Add("passed $sourceName contains firstBadFrame")
            }
        }
    }
    if ($failureKind -eq 'semantic-settle-timeout' -and
        $violationCount -gt 0) {
        $errors.Add('semantic settle timeout conflicts with violation counters')
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCaseId) -and
        $null -ne $summary -and
        [string]$summary.caseId -cne $ExpectedCaseId) {
        $errors.Add('summary caseId does not match expected case id')
    }
    if ($failureKind -eq 'unclassified-failure') {
        $errors.Add('failure kind is unclassified; refusing acceptance')
    }
    foreach ($file in $files) {
        if ([bool]$file.required -and -not [bool]$file.valid) {
            $errors.Add("$($file.name): $($file.state)")
        }
        if ([bool]$file.required -and
            [bool]$file.nonEmpty -and
            [string]$file.name -eq 'operation-trace.jsonl') {
            $traceValidation = Test-C6OperationTraceFile `
                -Path ([string]$file.path) `
                -RequireCompletedOperations ($summaryStatus -eq 'passed')
            foreach ($traceError in @($traceValidation.errors)) {
                $errors.Add("operation-trace.jsonl: $traceError")
            }
        }
        elseif ([bool]$file.required -and
            [bool]$file.nonEmpty -and
            [string]$file.name -eq 'runtime-frame-trace.jsonl') {
            $traceValidation = Test-C6RuntimeTraceFile -Path ([string]$file.path)
            foreach ($traceError in @($traceValidation.errors)) {
                $errors.Add("runtime-frame-trace.jsonl: $traceError")
            }
        }
        elseif ([bool]$file.required -and
            [bool]$file.nonEmpty -and
            [string]$file.name -like '*.jsonl') {
            try {
                $jsonlLines = @(
                    Get-Content -LiteralPath ([string]$file.path) |
                        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
                )
                if ($jsonlLines.Count -eq 0) {
                    throw 'JSONL contains no non-whitespace records'
                }
                foreach ($jsonlLine in $jsonlLines) {
                    $parsedJsonl = [string]$jsonlLine | ConvertFrom-Json -NoEnumerate
                    if ($null -eq $parsedJsonl) {
                        throw 'JSONL record is null'
                    }
                }
            }
            catch {
                $errors.Add("$($file.name): invalid-jsonl: $($_.Exception.Message)")
            }
        }
        if ([bool]$file.required -and
            [bool]$file.nonEmpty -and
            [string]$file.name -like 'screenshot-*.png') {
            $pngValidation = Test-C6PngIntegrity -Path ([string]$file.path)
            if (-not [bool]$pngValidation.valid) {
                foreach ($pngError in @($pngValidation.errors)) {
                    $errors.Add("$($file.name): invalid-png: $pngError")
                }
            }
        }
    }
    $summaryMarkdownPath = Join-Path $Directory 'summary.md'
    if (Test-Path -LiteralPath $summaryMarkdownPath -PathType Leaf) {
        $summaryMarkdown = Get-Content -Raw -LiteralPath $summaryMarkdownPath
        if ($summaryMarkdown -notmatch '(?m)^# C6 case summary\s*$') {
            $errors.Add('summary.md: missing required C6 case summary heading')
        }
        foreach ($label in @(
            'caseId',
            'scenario',
            'documentPosition',
            'target',
            'failureKind',
            'runtimeState',
            'visualObservation',
            'firstBadFrame'
        )) {
            if ($summaryMarkdown -notmatch "(?m)^- ${label}:\s*") {
                $errors.Add("summary.md: missing required $label field")
            }
        }
    }

    $firstBadFrameSource = $null
    $firstBadFrameSources = [System.Collections.Generic.List[string]]::new()
    foreach ($source in @($summary, $metadata)) {
        if ($null -eq $source) { continue }
        $candidate = $source.PSObject.Properties['firstBadFrameSource']
        if ($null -ne $candidate -and
            -not [string]::IsNullOrWhiteSpace([string]$candidate.Value)) {
            $firstBadFrameSources.Add([string]$candidate.Value)
        }
        $failureEvidence = $source.PSObject.Properties['failureEvidence']
        if ($null -ne $failureEvidence -and $null -ne $failureEvidence.Value) {
            $nested = $failureEvidence.Value.PSObject.Properties['firstBadFrameSource']
            if ($null -ne $nested -and
                -not [string]::IsNullOrWhiteSpace([string]$nested.Value)) {
                $firstBadFrameSources.Add([string]$nested.Value)
            }
        }
    }
    if ($firstBadFrameSources.Count -gt 0) {
        $firstBadFrameSource = $firstBadFrameSources[0]
        $distinctFirstBadFrameSources = @(
            $firstBadFrameSources | Select-Object -Unique
        )
        if ($distinctFirstBadFrameSources.Count -gt 1) {
            $errors.Add('metadata and summary firstBadFrameSource values do not match')
        }
    }
    if ($failureKind -eq 'semantic-settle-timeout') {
        if ([string]::IsNullOrWhiteSpace($firstBadFrameSource)) {
            $errors.Add(
                'semantic settle timeout must explicitly declare firstBadFrameSource=not-applicable'
            )
        }
        elseif ($firstBadFrameSource -cne 'not-applicable') {
            $errors.Add('semantic settle timeout has an invalid firstBadFrameSource')
        }
        foreach ($screenshotError in @(Get-C6SemanticScreenshotEvidenceErrors `
                -Metadata $metadata `
                -Summary $summary)) {
            $errors.Add($screenshotError)
        }
    }
    if ($failureKind -in @('visual-violation', 'invariant-violation') -and
        $firstBadFrameSource -ne 'C4-retained-raw-frame-window-middle') {
        $errors.Add('visual/invariant failure has no usable C4 firstBadFrameSource')
    }
    if ($failureKind -eq 'semantic-settle-timeout') {
        foreach ($screenshotName in @(
                'screenshot-before.png',
                'screenshot-violation.png',
                'screenshot-after.png'
            )) {
            $screenshotPath = Join-Path $Directory $screenshotName
            if (Test-Path -LiteralPath $screenshotPath) {
                $errors.Add(
                    "semantic settle timeout must leave $screenshotName N/A/not generated"
                )
            }
        }
    }

    $metadataHook = Get-C6PropertyValue $metadata 'invariantHookEnabled'
    $summaryHook = Get-C6PropertyValue $summary 'invariantHookEnabled'
    $metadataVisualOracle = Get-C6PropertyValue $metadata 'visualOracleEnabled'
    $summaryVisualOracle = Get-C6PropertyValue $summary 'visualOracleEnabled'

    $complete = $errors.Count -eq 0
    return [ordered]@{
        schemaVersion = $script:C6EvidenceBundleSchemaVersion
        bundleType = 'c6-case'
        caseId = $caseId
        safeCaseDirectory = if ([string]::IsNullOrWhiteSpace($caseId)) { $null } else { Get-C6SafeCaseName $caseId }
        directory = $Directory
        status = if ($complete) { 'complete' } else { 'incomplete' }
        complete = $complete
        isFailure = $isFailure
        failureKind = $failureKind
        firstBadFrameSource = $firstBadFrameSource
        invariantHookEnabled = $metadataHook
        visualOracleEnabled = $metadataVisualOracle
        hookProvenance = Get-C6PropertyValue $metadata 'hookProvenance'
        hookMode = Get-C6PropertyValue $metadata 'hookMode'
        hookSource = Get-C6PropertyValue $metadata 'hookSource'
        missingRequiredFiles = @($files | Where-Object { $_.required -and -not $_.valid } | ForEach-Object { $_.name })
        errors = @($errors)
        files = @($files)
    }
}

function Test-C6EvidenceDrain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedCaseIds,
        [switch]$RequireRootProvenance
    )

    # The case summaries are useful aggregate counters, but they are not the
    # transport proof.  The drain report is the only record that says which
    # files were pulled, their sizes, and whether final bundle validation
    # succeeded.  Keep this check independent from summary discovery so a
    # stale/partial summary cannot make a batch acceptance-eligible.
    $errors = [System.Collections.Generic.List[string]]::new()
    $drainPath = Join-Path $Directory 'evidence-drain.json'
    $drain = Get-C6JsonFile $drainPath
    $rootMetadata = $null
    $rootMetadataPath = Join-Path $Directory 'metadata.json'
    $reportedCaseCount = 0
    if ($null -eq $drain) {
        $errors.Add('evidence-drain.json missing or invalid JSON')
    }
    if ($RequireRootProvenance) {
        $rootMetadata = Get-C6JsonFile $rootMetadataPath
        if ($null -eq $rootMetadata) {
            $errors.Add('root metadata.json missing or invalid JSON')
        }
        else {
            if ([string](Get-C6PropertyValue $rootMetadata 'scenario') -cne
                'correctness-subset') {
                $errors.Add('root metadata.json: scenario is not correctness-subset')
            }
            foreach ($hookError in @(Get-C6HookProvenanceErrors `
                    -Source $rootMetadata `
                    -Label 'root metadata')) {
                $errors.Add($hookError)
            }
        }
    }

    $expectedIds = @($ExpectedCaseIds | ForEach-Object { [string]$_ })
    if ($expectedIds.Count -eq 0) {
        $errors.Add('expected case id set is empty')
    }

    $propertyNames = @(
        'schemaVersion',
        'status',
        'expectedCaseCount',
        'expectedCaseIds',
        'drainCaseCount',
        'appEvidenceCompleteCaseCount',
        'appEvidenceIncompleteCaseIds',
        'completeCaseCount',
        'incompleteCaseIds',
        'markerMismatch',
        'markerCaseCount',
        'markerCaseIds',
        'missingMarkerCaseIds',
        'unexpectedMarkerCaseIds',
        'cases',
        'pullErrors'
    )
    if ($null -ne $drain) {
        foreach ($propertyName in $propertyNames) {
            if ($null -eq $drain.PSObject.Properties[$propertyName]) {
                $errors.Add("evidence-drain.json: missing $propertyName")
            }
        }

        if ((Convert-C6ScalarInt (Get-C6PropertyValue $drain 'schemaVersion')) -ne
            $script:C6EvidenceBundleSchemaVersion) {
            $errors.Add('evidence-drain.json: unsupported or missing schemaVersion')
        }
        if ([string](Get-C6PropertyValue $drain 'status') -cne 'complete') {
            $errors.Add('evidence-drain.json: status is not complete')
        }

        $reportedExpectedIds = @(
            (Get-C6PropertyValue $drain 'expectedCaseIds') |
                ForEach-Object { [string]$_ }
        )
        $reportedCases = @(
            $reportedCasesValue = Get-C6PropertyValue $drain 'cases'
            if ($null -ne $reportedCasesValue) { $reportedCasesValue }
        )
        $reportedCaseCount = $reportedCases.Count
        $reportedCaseIds = @(
            $reportedCases | ForEach-Object {
                [string](Get-C6PropertyValue $_ 'caseId')
            }
        )
        $expectedSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $reportedExpectedSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $reportedCaseSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($caseId in $expectedIds) { [void]$expectedSet.Add($caseId) }
        foreach ($caseId in $reportedExpectedIds) {
            [void]$reportedExpectedSet.Add($caseId)
        }
        foreach ($caseId in $reportedCaseIds) {
            [void]$reportedCaseSet.Add($caseId)
        }
        $expectedIdsMatch =
            $expectedSet.Count -eq $expectedIds.Count -and
            $reportedExpectedSet.Count -eq $reportedExpectedIds.Count -and
            $reportedCaseSet.Count -eq $reportedCaseIds.Count -and
            $expectedSet.Count -eq $reportedExpectedSet.Count -and
            $expectedSet.IsSubsetOf($reportedExpectedSet) -and
            $expectedSet.Count -eq $reportedCaseSet.Count -and
            $expectedSet.IsSubsetOf($reportedCaseSet)
        if (-not $expectedIdsMatch) {
            $errors.Add('evidence-drain.json: expected and reported case ids do not match exactly')
        }

        $expectedCount = $expectedIds.Count
        foreach ($fieldName in @(
            'expectedCaseCount',
            'drainCaseCount',
            'appEvidenceCompleteCaseCount',
            'completeCaseCount'
        )) {
            if ((Convert-C6ScalarInt (Get-C6PropertyValue $drain $fieldName)) -ne
                $expectedCount) {
                $errors.Add("evidence-drain.json: $fieldName does not equal expected case count")
            }
        }
        foreach ($fieldName in @(
            'appEvidenceIncompleteCaseIds',
            'incompleteCaseIds',
            'pullErrors'
        )) {
            $values = @(
                $rawValues = Get-C6PropertyValue $drain $fieldName
                if ($null -ne $rawValues) { $rawValues }
            )
            if ($values.Count -gt 0) {
                $errors.Add("evidence-drain.json: $fieldName is non-empty")
            }
        }
        if ([bool](Get-C6PropertyValue $drain 'markerMismatch')) {
            $errors.Add('evidence-drain.json: markerMismatch is true')
        }

        $markerCaseIds = @(Convert-C6StringArray (
            Get-C6PropertyValue $drain 'markerCaseIds'
        ))
        $reportedMissingMarkerCaseIds = @(Convert-C6StringArray (
            Get-C6PropertyValue $drain 'missingMarkerCaseIds'
        ))
        $reportedUnexpectedMarkerCaseIds = @(Convert-C6StringArray (
            Get-C6PropertyValue $drain 'unexpectedMarkerCaseIds'
        ))
        $markerSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($markerCaseId in $markerCaseIds) {
            if ([string]::IsNullOrWhiteSpace($markerCaseId)) {
                $errors.Add('evidence-drain.json: markerCaseIds contains an empty id')
                continue
            }
            if (-not $markerSet.Add($markerCaseId)) {
                $errors.Add("evidence-drain.json: duplicate marker case id $markerCaseId")
            }
        }
        $computedMissingMarkerCaseIds = @(
            $expectedIds | Where-Object { -not $markerSet.Contains($_) }
        )
        $computedUnexpectedMarkerCaseIds = @(
            $markerCaseIds | Where-Object { -not $expectedSet.Contains($_) }
        )
        $reportedMarkerCount = Convert-C6ScalarInt (
            Get-C6PropertyValue $drain 'markerCaseCount'
        )
        if ($reportedMarkerCount -ne $markerCaseIds.Count) {
            $errors.Add('evidence-drain.json: markerCaseCount does not equal markerCaseIds length')
        }
        if ($reportedMarkerCount -ne $expectedIds.Count) {
            $errors.Add('evidence-drain.json: markerCaseCount does not equal expected case count')
        }
        if (-not (Test-C6StringSetEqual `
                -Left $reportedMissingMarkerCaseIds `
                -Right $computedMissingMarkerCaseIds)) {
            $errors.Add('evidence-drain.json: missingMarkerCaseIds disagrees with markerCaseIds and expected ids')
        }
        if (-not (Test-C6StringSetEqual `
                -Left $reportedUnexpectedMarkerCaseIds `
                -Right $computedUnexpectedMarkerCaseIds)) {
            $errors.Add('evidence-drain.json: unexpectedMarkerCaseIds disagrees with markerCaseIds and expected ids')
        }
        $computedMarkerMismatch =
            $computedMissingMarkerCaseIds.Count -gt 0 -or
            $computedUnexpectedMarkerCaseIds.Count -gt 0
        if ([bool](Get-C6PropertyValue $drain 'markerMismatch') -ne $computedMarkerMismatch) {
            $errors.Add('evidence-drain.json: markerMismatch disagrees with recomputed marker arrays')
        }
        if ($computedMarkerMismatch) {
            $errors.Add('evidence-drain.json: marker arrays do not exactly cover expected case ids')
        }

        $seenCaseIds = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($caseReport in $reportedCases) {
            $caseId = [string](Get-C6PropertyValue $caseReport 'caseId')
            if ([string]::IsNullOrWhiteSpace($caseId)) {
                $errors.Add('evidence-drain.json: case report has no caseId')
                continue
            }
            if (-not $seenCaseIds.Add($caseId)) {
                $errors.Add("evidence-drain.json: duplicate case report $caseId")
            }
            if (-not $expectedSet.Contains($caseId)) {
                $errors.Add("evidence-drain.json: unexpected case report $caseId")
                continue
            }

            $safeCaseName = Get-C6SafeCaseName $caseId
            if ([string](Get-C6PropertyValue $caseReport 'safeCaseDirectory') -cne
                $safeCaseName) {
                $errors.Add("evidence-drain.json: safe case directory mismatch for $caseId")
            }
            if ([string](Get-C6PropertyValue $caseReport 'appEvidenceStatus') -cne 'complete') {
                $errors.Add("evidence-drain.json: app evidence is not complete for $caseId")
            }
            if (-not [bool](Get-C6PropertyValue $caseReport 'bundleComplete') -or
                [string](Get-C6PropertyValue $caseReport 'bundleStatus') -cne 'complete') {
                $errors.Add("evidence-drain.json: final bundle is not complete for $caseId")
            }

            $casePullErrorsProperty = $caseReport.PSObject.Properties['pullErrors']
            if ($null -eq $casePullErrorsProperty) {
                $errors.Add("evidence-drain.json: pullErrors missing for $caseId")
            }
            elseif (@(
                    if ($null -ne $casePullErrorsProperty.Value) {
                        $casePullErrorsProperty.Value
                    }
                ).Count -gt 0) {
                $errors.Add("evidence-drain.json: pullErrors is non-empty for $caseId")
            }

            $requiredFilesProperty = $caseReport.PSObject.Properties['requiredFiles']
            if ($null -eq $requiredFilesProperty) {
                $errors.Add("evidence-drain.json: requiredFiles missing for $caseId")
                continue
            }
            $drainFiles = @(
                if ($null -ne $requiredFilesProperty.Value) {
                    $requiredFilesProperty.Value
                }
            )
            $bundlePath = Join-Path $Directory $safeCaseName
            $bundleValidation = Test-C6BundleDirectory `
                -Directory $bundlePath `
                -ExpectedCaseId $caseId
            $reportedFailureKind = [string](Get-C6PropertyValue $caseReport 'bundleFailureKind')
            if ($reportedFailureKind -cne [string]$bundleValidation.failureKind) {
                $errors.Add("evidence-drain.json: failure kind mismatch for $caseId")
            }
            $reportedFirstBadFrameSource = [string](
                Get-C6PropertyValue $caseReport 'firstBadFrameSource'
            )
            $validatedFirstBadFrameSource = [string]$bundleValidation.firstBadFrameSource
            if ($reportedFirstBadFrameSource -cne $validatedFirstBadFrameSource) {
                $errors.Add("evidence-drain.json: firstBadFrameSource mismatch for $caseId")
            }
            if (-not [bool]$bundleValidation.complete) {
                foreach ($validationError in @($bundleValidation.errors)) {
                    $errors.Add("${caseId}: final bundle $validationError")
                }
            }
            $validationRequiredNames = @(
                $bundleValidation.files |
                    Where-Object { [bool]$_.required } |
                    ForEach-Object { [string]$_.name }
            )
            $drainRequiredNames = @(
                $drainFiles |
                    Where-Object { [bool]$_.required } |
                    ForEach-Object { [string]$_.name }
            )
            $validationRequiredSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )
            $drainRequiredSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )
            foreach ($name in $validationRequiredNames) {
                [void]$validationRequiredSet.Add($name)
            }
            foreach ($name in $drainRequiredNames) {
                [void]$drainRequiredSet.Add($name)
            }
            if ($validationRequiredSet.Count -ne $validationRequiredNames.Count -or
                $drainRequiredSet.Count -ne $drainRequiredNames.Count -or
                $validationRequiredSet.Count -ne $drainRequiredSet.Count -or
                -not $validationRequiredSet.IsSubsetOf($drainRequiredSet)) {
                $errors.Add("evidence-drain.json: required file list mismatch for $caseId")
            }
            foreach ($requiredName in $validationRequiredNames) {
                $records = @(
                    $drainFiles | Where-Object {
                        [string](Get-C6PropertyValue $_ 'name') -ceq $requiredName -and
                        [bool](Get-C6PropertyValue $_ 'required')
                    }
                )
                if ($records.Count -ne 1) {
                    $errors.Add("evidence-drain.json: required file record missing or duplicated for $caseId/$requiredName")
                    continue
                }
                $record = $records[0]
                foreach ($fieldName in @(
                    'sizeBytes',
                    'nonEmpty',
                    'state',
                    'valid',
                    'pullErrors'
                )) {
                    if ($null -eq $record.PSObject.Properties[$fieldName]) {
                        $errors.Add("evidence-drain.json: $caseId/$requiredName missing $fieldName")
                    }
                }
                if (-not [bool](Get-C6PropertyValue $record 'valid')) {
                    $errors.Add("evidence-drain.json: $caseId/$requiredName is not valid")
                }
                if (@(
                        $recordPullErrors = Get-C6PropertyValue $record 'pullErrors'
                        if ($null -ne $recordPullErrors) { $recordPullErrors }
                    ).Count -gt 0) {
                    $errors.Add("evidence-drain.json: $caseId/$requiredName has pull errors")
                }
                $validationFile = @(
                    $bundleValidation.files | Where-Object {
                        [string]$_.name -ceq $requiredName
                    }
                )[0]
                if ($null -ne $validationFile) {
                    foreach ($fieldName in @(
                        'exists',
                        'pathIsDirectory',
                        'sizeBytes',
                        'nonEmpty',
                        'state',
                        'valid'
                    )) {
                        $drainProperty = $record.PSObject.Properties[$fieldName]
                        if ($null -eq $drainProperty) { continue }
                        $drainValue = $drainProperty.Value
                        $validationValue = $validationFile.$fieldName
                        $fieldMatches = if ($fieldName -eq 'sizeBytes') {
                            [long]$drainValue -eq [long]$validationValue
                        }
                        elseif ($fieldName -in @('exists', 'pathIsDirectory', 'nonEmpty', 'valid')) {
                            [bool]$drainValue -eq [bool]$validationValue
                        }
                        else {
                            [string]$drainValue -ceq [string]$validationValue
                        }
                        if (-not $fieldMatches) {
                            $errors.Add("evidence-drain.json: $caseId/$requiredName $fieldName disagrees with final bundle")
                        }
                    }
                }
            }
        }
    }

    return [ordered]@{
        schemaVersion = $script:C6EvidenceBundleSchemaVersion
        path = $drainPath
        exists = Test-Path -LiteralPath $drainPath -PathType Leaf
        status = if ($null -ne $drain) {
            [string](Get-C6PropertyValue $drain 'status')
        }
        else { $null }
        expectedCaseCount = $expectedIds.Count
        reportedCaseCount = $reportedCaseCount
        markerCaseCount = if ($null -ne $drain) {
            Convert-C6ScalarInt (Get-C6PropertyValue $drain 'markerCaseCount')
        }
        else { 0 }
        markerCaseIds = if ($null -ne $drain) {
            Convert-C6StringArray (Get-C6PropertyValue $drain 'markerCaseIds')
        }
        else { @() }
        rootProvenanceRequired = [bool]$RequireRootProvenance
        rootMetadataPresent = $null -ne $rootMetadata
        complete = $errors.Count -eq 0
        errors = @($errors)
    }
}

function Write-C6BundleManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        $Validation
    )

    $path = Join-Path $Directory 'bundle-manifest.json'
    $manifest = [ordered]@{}
    if ($Validation -is [System.Collections.IDictionary]) {
        foreach ($entry in $Validation.GetEnumerator()) {
            $manifest[[string]$entry.Key] = $entry.Value
        }
    }
    else {
        foreach ($property in $Validation.PSObject.Properties) {
            $manifest[$property.Name] = $property.Value
        }
    }
    $manifest['transportStatus'] = 'host-validated'
    $manifest['validationMode'] = 'fail-closed'
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

Export-ModuleMember -Function @(
    'Get-C6SafeCaseName',
    'Get-C6MarkerCaseIds',
    'Get-C6FailureKind',
    'Get-C6BundleFileContract',
    'Get-C6OptionalEvidenceFileNames',
    'Resolve-C6ContainedPath',
    'Test-C6PngIntegrity',
    'Test-C6BundleDirectory',
    'Test-C6EvidenceDrain',
    'Write-C6BundleManifest'
)
