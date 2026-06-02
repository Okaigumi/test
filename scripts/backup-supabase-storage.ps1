#Requires -Version 5.1
<#
.SYNOPSIS
    Supabase Storage photos backup using reports.photo_urls from data.sql
.DESCRIPTION
    Parses photo_urls from data.sql (pg_dump COPY format), downloads each Public URL
    via Invoke-WebRequest, and saves to backups/YYYYMMDD-HHMMSS-storage/.

    No service role key.  No Storage List API.
    Target: photos recorded in reports.photo_urls only.
    Orphaned Storage files (upload succeeded but DB update failed) are NOT covered.
.PARAMETER SqlZipPath
    Path to an existing .sql.zip produced by backup-supabase.ps1.
    The zip is expanded to a temp folder; temp folder is deleted after data.sql is read.
.PARAMETER DataSqlPath
    Direct path to a data.sql file.
.EXAMPLE
    .\scripts\backup-supabase-storage.ps1 -SqlZipPath .\backups\20260601-154102.sql.zip
.EXAMPLE
    .\scripts\backup-supabase-storage.ps1 -DataSqlPath .\path\to\data.sql
.NOTES
    Run backup-supabase.ps1 first to obtain a fresh data.sql before using -SqlZipPath.
#>

[CmdletBinding()]
param(
    [Parameter(ParameterSetName = 'Zip', Mandatory = $true)]
    [string]$SqlZipPath,

    [Parameter(ParameterSetName = 'Sql', Mandatory = $true)]
    [string]$DataSqlPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ===========================================================
# Helper functions
# ===========================================================

# Parse a PostgreSQL COPY text-format array value into string[].
# Input examples: {"url1","url2"}  /  {}  /  \N
# Returns @() for NULL, empty array, or unrecognised format.
function Parse-PgArray([string]$raw) {
    if ($raw -eq '\N' -or [string]::IsNullOrEmpty($raw)) { return @() }
    if (-not ($raw.StartsWith('{') -and $raw.EndsWith('}'))) { return @() }

    $inner = $raw.Substring(1, $raw.Length - 2)
    if ([string]::IsNullOrEmpty($inner)) { return @() }

    $results = [System.Collections.Generic.List[string]]::new()
    $i = 0
    $n = $inner.Length

    while ($i -lt $n) {
        if ($inner[$i] -eq '"') {
            # Quoted element: read until unescaped closing quote
            $i++
            $sb = [System.Text.StringBuilder]::new()
            while ($i -lt $n -and $inner[$i] -ne '"') {
                if ($inner[$i] -eq '\' -and ($i + 1) -lt $n) {
                    $i++                                       # skip backslash
                    $sb.Append($inner[$i]) | Out-Null
                } else {
                    $sb.Append($inner[$i]) | Out-Null
                }
                $i++
            }
            $i++                                               # skip closing quote
            $results.Add($sb.ToString())
        } else {
            # Unquoted element (integer, NULL keyword, etc.)
            $start = $i
            while ($i -lt $n -and $inner[$i] -ne ',') { $i++ }
            $elem = $inner.Substring($start, $i - $start)
            if ($elem -ne 'NULL' -and $elem -ne '\N') { $results.Add($elem) }
        }
        if ($i -lt $n -and $inner[$i] -eq ',') { $i++ }      # skip comma separator
    }

    return @($results)
}

# Extract the relative path under photos/ from a Supabase Public URL.
# Expected URL segment: /storage/v1/object/public/photos/{relPath}
# Returns $null if the URL does not contain the expected segment.
function Get-PhotoRelPath([string]$url) {
    $marker = '/storage/v1/object/public/photos/'
    $idx    = $url.IndexOf($marker)
    if ($idx -lt 0) { return $null }
    $rel = $url.Substring($idx + $marker.Length)
    if ([string]::IsNullOrEmpty($rel)) { return $null }
    # Convert URL forward-slashes to OS path separator
    return $rel.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

# Download a URL to OutFile with up to MaxRetry attempts.
# Returns $true on success, $false after all retries exhausted.
function Invoke-Download([string]$Url, [string]$OutFile, [int]$MaxRetry = 3) {
    for ($attempt = 1; $attempt -le $MaxRetry; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 30
            return $true
        } catch {
            if ($attempt -lt $MaxRetry) { Start-Sleep -Seconds 2 }
        }
    }
    return $false
}

# ===========================================================
# Step 1: Resolve data.sql
# ===========================================================
Write-Host "[1/6] Resolving data.sql..."

$tempDir             = $null
$resolvedDataSqlPath = $null
$inputLabel          = ''

if ($PSCmdlet.ParameterSetName -eq 'Zip') {
    if (-not (Test-Path $SqlZipPath)) {
        Write-Error "SqlZipPath not found: $SqlZipPath"
        exit 1
    }
    $inputLabel = (Resolve-Path $SqlZipPath).Path

    $tempDir = Join-Path $env:TEMP ('supabase-storage-' + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    Write-Host "  Expanding zip to temp folder: $tempDir"
    Expand-Archive -Path $inputLabel -DestinationPath $tempDir -Force

    $found = Get-ChildItem -Path $tempDir -Filter 'data.sql' -Recurse -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if (-not $found) {
        Remove-Item -Recurse -Force $tempDir
        Write-Error "data.sql not found inside zip: $SqlZipPath"
        exit 1
    }
    $resolvedDataSqlPath = $found.FullName
    Write-Host "  data.sql: $resolvedDataSqlPath"
} else {
    if (-not (Test-Path $DataSqlPath)) {
        Write-Error "DataSqlPath not found: $DataSqlPath"
        exit 1
    }
    $resolvedDataSqlPath = (Resolve-Path $DataSqlPath).Path
    $inputLabel          = $resolvedDataSqlPath
    Write-Host "  data.sql: $resolvedDataSqlPath"
}

# ===========================================================
# Step 2: Parse data.sql for public.reports COPY block
# ===========================================================
Write-Host "[2/6] Parsing data.sql for reports.photo_urls..."

# Column indices resolved dynamically from the COPY header
$colMap = @{ id = -1; report_date = -1; photo_urls = -1; photo_count = -1 }
$inCopy    = $false
$photoRows = [System.Collections.Generic.List[hashtable]]::new()

$reader = [System.IO.StreamReader]::new($resolvedDataSqlPath, [System.Text.Encoding]::UTF8)
try {
    while ($null -ne ($line = $reader.ReadLine())) {

        if (-not $inCopy) {
            # Detect COPY header for public.reports.
            # supabase db dump quotes identifiers: COPY "public"."reports" ("col", ...) FROM stdin;
            # Accept both quoted and unquoted forms.
            if ($line -match '^COPY "?public"?\."?reports"?\s*\((.+)\)\s*FROM stdin;') {
                # Strip surrounding double-quotes from each column name
                $cols = ($Matches[1] -split ',') | ForEach-Object { $_.Trim().Trim('"') }
                for ($c = 0; $c -lt $cols.Count; $c++) {
                    if ($colMap.ContainsKey($cols[$c])) { $colMap[$cols[$c]] = $c }
                }
                # All four columns must be present
                foreach ($key in @('id', 'report_date', 'photo_urls', 'photo_count')) {
                    if ($colMap[$key] -eq -1) {
                        $reader.Close()
                        if ($tempDir -and (Test-Path $tempDir)) { Remove-Item -Recurse -Force $tempDir }
                        Write-Error "Required column '$key' not found in COPY header of public.reports."
                        exit 1
                    }
                }
                $inCopy = $true
                continue
            }
        } else {
            # End-of-copy marker
            if ($line -eq '\.') { $inCopy = $false; break }

            # Tab-separated columns
            $f = $line.Split("`t")

            # Filter: photo_count must be a positive integer
            $pcRaw = $f[$colMap.photo_count]
            if ($pcRaw -eq '\N') { continue }
            $pc = 0
            if (-not [int]::TryParse($pcRaw, [ref]$pc) -or $pc -le 0) { continue }

            # Filter: photo_urls must not be NULL or empty array
            $puRaw = $f[$colMap.photo_urls]
            if ($puRaw -eq '\N' -or $puRaw -eq '{}' -or [string]::IsNullOrEmpty($puRaw)) { continue }

            # @() ensures array even when PowerShell unwraps a single-element return value
            $urls = @(Parse-PgArray $puRaw)
            if ($urls.Count -eq 0) { continue }

            $photoRows.Add(@{
                id          = $f[$colMap.id]
                report_date = $f[$colMap.report_date]
                urls        = $urls
            })
        }
    }
} finally {
    $reader.Close()
}

# Temp dir no longer needed after data.sql is fully read
if ($tempDir -and (Test-Path $tempDir)) {
    Remove-Item -Recurse -Force $tempDir
    $tempDir = $null
    Write-Host "  Temp folder removed."
}

$totalUrls = 0
foreach ($r in $photoRows) { $totalUrls += $r.urls.Count }
Write-Host "  Reports with photos : $($photoRows.Count)"
Write-Host "  Total photo URLs    : $totalUrls"

if ($photoRows.Count -eq 0) {
    Write-Host ""
    Write-Host "No photos found in reports. Nothing to download."
    exit 0
}

# ===========================================================
# Step 3: Prepare output directory
# ===========================================================
Write-Host "[3/6] Preparing output directory..."

$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupBase = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\backups'))
$outDir     = Join-Path $backupBase "$timestamp-storage"
$photosDir  = Join-Path $outDir 'photos'
New-Item -ItemType Directory -Force -Path $photosDir | Out-Null
Write-Host "  Output: $outDir"

# ===========================================================
# Step 4: Download photos
# ===========================================================
Write-Host "[4/6] Downloading $totalUrls photo(s)..."

$manifest   = [System.Collections.Generic.List[hashtable]]::new()
$okCount    = 0
$skipCount  = 0
$errorCount = 0

foreach ($row in $photoRows) {
    foreach ($url in $row.urls) {

        $relPath = Get-PhotoRelPath $url

        # Unexpected URL: no /storage/v1/object/public/photos/ segment
        if ($null -eq $relPath) {
            $manifest.Add(@{
                report_date     = $row.report_date
                report_id       = $row.id
                photo_url       = $url
                local_path      = ''
                status          = 'ERROR'
                file_size_bytes = 0
                error_message   = 'Unexpected URL format: /storage/v1/object/public/photos/ not found'
            })
            $errorCount++
            Write-Host "  ERR (bad URL) : $url"
            continue
        }

        $absPath  = Join-Path $photosDir $relPath
        $localRec = 'photos\' + $relPath        # recorded in manifest

        # File already exists: SKIPPED (idempotent re-run support)
        if (Test-Path $absPath) {
            $sz = (Get-Item $absPath).Length
            $manifest.Add(@{
                report_date     = $row.report_date
                report_id       = $row.id
                photo_url       = $url
                local_path      = $localRec
                status          = 'SKIPPED'
                file_size_bytes = $sz
                error_message   = ''
            })
            $skipCount++
            continue
        }

        # Ensure parent directory exists
        $parentDir = Split-Path $absPath -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
        }

        # Download to .tmp; rename to final name only on success
        $tmpPath = $absPath + '.tmp'
        $ok      = Invoke-Download -Url $url -OutFile $tmpPath -MaxRetry 3

        if ($ok -and (Test-Path $tmpPath)) {
            $sz = (Get-Item $tmpPath).Length
            Rename-Item -Path $tmpPath -NewName ([System.IO.Path]::GetFileName($absPath))
            $manifest.Add(@{
                report_date     = $row.report_date
                report_id       = $row.id
                photo_url       = $url
                local_path      = $localRec
                status          = 'OK'
                file_size_bytes = $sz
                error_message   = ''
            })
            $okCount++
            Write-Host "  OK  : $url"
        } else {
            if (Test-Path $tmpPath) { Remove-Item -Force $tmpPath }
            $manifest.Add(@{
                report_date     = $row.report_date
                report_id       = $row.id
                photo_url       = $url
                local_path      = $localRec
                status          = 'ERROR'
                file_size_bytes = 0
                error_message   = 'Download failed after 3 retries'
            })
            $errorCount++
            Write-Host "  ERR : $url"
        }
    }
}

Write-Host "  Result: OK=$okCount  SKIPPED=$skipCount  ERROR=$errorCount"

# ===========================================================
# Step 5: Write storage-backup-manifest.csv and backup-info.txt
# ===========================================================
Write-Host "[5/6] Writing manifest and backup-info..."

$utf8 = [System.Text.Encoding]::UTF8

# storage-backup-manifest.csv
# Fields with free-text content are double-quoted; embedded quotes are doubled (RFC 4180).
$csvLines = [System.Collections.Generic.List[string]]::new()
$csvLines.Add('report_date,report_id,photo_url,local_path,status,file_size_bytes,error_message')
foreach ($m in $manifest) {
    $csvLine = (
        $m.report_date,
        $m.report_id,
        ('"' + $m.photo_url.Replace('"', '""')     + '"'),
        ('"' + $m.local_path.Replace('"', '""')    + '"'),
        $m.status,
        $m.file_size_bytes,
        ('"' + $m.error_message.Replace('"', '""') + '"')
    ) -join ','
    $csvLines.Add($csvLine)
}
$csvPath = Join-Path $outDir 'storage-backup-manifest.csv'
[System.IO.File]::WriteAllLines($csvPath, $csvLines.ToArray(), $utf8)
Write-Host "  Manifest : $csvPath"

# backup-info.txt
$infoLines = @(
    "backup_timestamp : $timestamp",
    "input_source     : $inputLabel",
    "total_urls       : $totalUrls",
    "ok_count         : $okCount",
    "skipped_count    : $skipCount",
    "error_count      : $errorCount",
    '',
    'note: This backup covers only photos recorded in reports.photo_urls.',
    '      Orphaned Storage files (upload OK but DB update failed) are NOT included.'
)
$infoPath = Join-Path $outDir 'backup-info.txt'
[System.IO.File]::WriteAllLines($infoPath, $infoLines, $utf8)
Write-Host "  Info     : $infoPath"

# ===========================================================
# Step 6: Zip (only when ERROR count is zero)
# ===========================================================
if ($errorCount -eq 0) {
    Write-Host "[6/6] Creating zip..."
    $zipPath = Join-Path $backupBase "$timestamp-storage.zip"
    Compress-Archive -Path "$outDir\*" -DestinationPath $zipPath -Force
    Remove-Item -Recurse -Force $outDir
    Write-Host ""
    Write-Host "Complete : $zipPath"
    Write-Host "Note     : Do not push this file to GitHub."
} else {
    Write-Host "[6/6] Skipping zip ($errorCount error(s) found)."
    Write-Host ""
    Write-Host "Incomplete : $outDir  (folder kept for review)"
    Write-Host "Check storage-backup-manifest.csv for ERROR rows, then re-run."
    exit 1
}
