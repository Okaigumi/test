#Requires -Version 5.1
<#
.SYNOPSIS
    Takes a local backup of the Supabase production DB.
.DESCRIPTION
    Reads SUPABASE_DB_URL from .env.backup.local, dumps roles / schema / data,
    validates via validate-backup.ps1, writes backup-info.txt, then zips.
    ZIP is only created when validation passes (exit 0).
    SUPABASE_DB_URL is never displayed on screen.
.NOTES
    Requires: Node.js / npx, Docker Desktop (running).
              validate-backup.ps1 must exist in the same scripts/ folder.
    Requires absolute -EnvFile, -BackupRoot and -TempRoot outside the repository and cloud sync.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EnvFile,
    [Parameter(Mandatory=$true)][string]$BackupRoot,
    [Parameter(Mandatory=$true)][string]$TempRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'private-asset-paths.ps1')
$EnvFile = Resolve-PrivateAssetPath -Path $EnvFile -Kind File
$backupBase = Resolve-PrivateAssetPath -Path $BackupRoot
$TempRoot = Resolve-PrivateAssetPath -Path $TempRoot
$resultFile = $null
$previousDbUrl = $env:SUPABASE_DB_URL
try {

# --- 1. Check npx ---
Write-Host "[1/7] Checking npx..."
try {
    $null = Get-Command npx -ErrorAction Stop
} catch {
    Write-Error "npx not found. Install Node.js."
    exit 1
}

# --- 2. Check Supabase CLI ---
Write-Host "[2/7] Checking Supabase CLI (npx)..."
try {
    $supabaseVersion = npx --yes supabase --version 2>&1
    Write-Host "  Supabase CLI: $supabaseVersion"
} catch {
    Write-Error "npx --yes supabase --version failed. Check Node.js / network."
    exit 1
}

# --- 3. Load .env.backup.local ---
Write-Host "[3/7] Loading .env.backup.local..."

# EnvFile was validated before any CLI or secret access.
if (-not (Test-Path $envFile)) {
    throw ".env.backup.local not found. Create it from .env.backup.local.example."
}

$line = Get-Content -LiteralPath $EnvFile | Where-Object { $_ -match '^\s*SUPABASE_DB_URL\s*=' } | Select-Object -First 1
if (-not $line) {
    throw ".env.backup.local does not contain SUPABASE_DB_URL."
}

$value = $line -replace '^\s*SUPABASE_DB_URL\s*=\s*', ''
$value = $value.Trim()
$value = $value.Trim('"')

if ([string]::IsNullOrWhiteSpace($value)) {
    throw "SUPABASE_DB_URL is empty."
}

$env:SUPABASE_DB_URL = $value
Write-Host "  SUPABASE_DB_URL: loaded (value not displayed)"

# --- 4. Create backup folder ---
$timestamp  = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$backupBase = Resolve-PrivateAssetPath -Path $backupBase
$backupDir  = Join-Path $TempRoot ('db-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $backupBase, $TempRoot | Out-Null
New-Item -ItemType Directory -Path $backupDir | Out-Null
Write-Host "[4/7] Backup folder: $backupDir"

# --- 5. Dump ---
Write-Host "[5/7] Dumping..."

Write-Host "  roles.sql ..."
npx --yes supabase db dump --db-url "$env:SUPABASE_DB_URL" -f "$backupDir\roles.sql" --role-only
if ($LASTEXITCODE -ne 0) {
    Write-Error "roles.sql dump failed."
    exit 1
}

Write-Host "  schema.sql ..."
npx --yes supabase db dump --db-url "$env:SUPABASE_DB_URL" -f "$backupDir\schema.sql"
if ($LASTEXITCODE -ne 0) {
    Write-Error "schema.sql dump failed."
    exit 1
}

Write-Host "  data.sql ..."
npx --yes supabase db dump --db-url "$env:SUPABASE_DB_URL" -f "$backupDir\data.sql" --use-copy --data-only --schema public,private
if ($LASTEXITCODE -ne 0) {
    Write-Error "data.sql dump failed."
    exit 1
}

# --- 6. Validate + write backup-info.txt ---
Write-Host "[6/7] Validating..."

$validateScript = Join-Path $PSScriptRoot 'validate-backup.ps1'
if (-not (Test-Path $validateScript)) {
    Write-Error "validate-backup.ps1 not found: $validateScript"
    exit 1
}

# A unique current-run result file, outside backupDir and therefore outside the ZIP.
$resultFile = Join-Path $TempRoot ('vb-result-' + [guid]::NewGuid().ToString('N') + '.json')

# Run validate-backup.ps1. Write-Host output goes directly to the console.
# SHA-256 and COPY counts are read from the machine-readable result file only.
$global:LASTEXITCODE = $null
& $validateScript -BackupDir $backupDir -ResultPath $resultFile
$validateExitCode = $LASTEXITCODE

# Read and parse the result file.
$vResult       = $null
$resultReadOk  = $false
$utf8NoBom     = [System.Text.UTF8Encoding]::new($false)

if (Test-Path $resultFile) {
    try {
        $jsonText = [System.IO.File]::ReadAllText($resultFile, $utf8NoBom)
        # ConvertFrom-Json can unwrap a single-item array; reject non-object roots first.
        if (-not $jsonText.TrimStart().StartsWith('{')) { throw 'Validation result must be a JSON object.' }
        $vResult  = $jsonText | ConvertFrom-Json

        if ($null -eq $vResult -or $vResult -isnot [System.Management.Automation.PSCustomObject]) {
            throw 'Validation result must be one JSON object.'
        }

        # Verify all required fields are present.
        $required = @('validation','checks_total','checks_passed','checks_failed',
                      'sha256_roles','sha256_schema','sha256_data',
                      'copy_total','copy_public','copy_private',
                      'copy_auth','copy_storage','copy_other')
        $missing = @()
        foreach ($f in $required) {
            if ($null -eq $vResult.PSObject.Properties[$f] -or $null -eq $vResult.$f) { $missing += $f }
        }
        if ($missing.Count -eq 0) {
            # Validate the result envelope; the validator owns the 21 data checks.
            if ($vResult.validation -isnot [string] -or $vResult.validation -cnotin @('PASSED','FAILED')) { throw 'Invalid validation status.' }
            foreach ($f in @('checks_total','checks_passed','checks_failed','copy_total','copy_public','copy_private','copy_auth','copy_storage','copy_other')) {
                $count = $vResult.$f
                if (($count -isnot [int] -and $count -isnot [long]) -or $count -lt 0) { throw 'Invalid validation count.' }
            }
            if ($vResult.checks_total -le 0 -or
                [decimal]$vResult.checks_passed + [decimal]$vResult.checks_failed -ne [decimal]$vResult.checks_total -or
                ($vResult.validation -ceq 'PASSED' -and $vResult.checks_failed -ne 0) -or
                ($vResult.validation -ceq 'FAILED' -and $vResult.checks_failed -eq 0)) { throw 'Inconsistent validation counts.' }
            foreach ($f in @('sha256_roles','sha256_schema','sha256_data')) {
                # A valid FAIL can have empty hashes for files that could not be read.
                if ($vResult.$f -isnot [string] -or
                    ($vResult.validation -ceq 'PASSED' -and [string]::IsNullOrWhiteSpace($vResult.$f))) { throw 'Invalid validation hash field.' }
            }
            $resultReadOk = $true
        } else {
            Write-Host "  [ERROR] Result file missing fields: $($missing -join ', ')"
            $validateExitCode = 1
        }
    } catch {
        Write-Host '  [ERROR] Validation result JSON is invalid or incomplete.'
        $validateExitCode = 1
    }
} else {
    Write-Host "  [ERROR] Result file not found: $resultFile"
    $validateExitCode = 1
}

# Delete the temp result file before ZIP creation.
if (Test-Path $resultFile) { Remove-Item -Force $resultFile -ErrorAction SilentlyContinue }

if (-not $resultReadOk -or $null -eq $validateExitCode) {
    throw "Validation result unavailable. No summary or ZIP created for this run. Dump retained: $backupDir"
}
# Both the process outcome and the valid JSON must permit success.
if ($vResult.validation -ceq 'FAILED') { $validateExitCode = 1 }

# Write backup-info.txt once, after validation result is known.
# SHA-256 and COPY counts come exclusively from the parsed result file.
$validationResult = if ($validateExitCode -eq 0 -and $resultReadOk) { 'PASSED' } else { 'FAILED' }

$shaRolesOut   = $vResult.sha256_roles
$shaSchemaOut  = $vResult.sha256_schema
$shaDataOut    = $vResult.sha256_data
$copyTotalOut  = $vResult.copy_total
$copyPublicOut = $vResult.copy_public
$copyPrivOut   = $vResult.copy_private
$copyAuthOut   = $vResult.copy_auth
$copyStorOut   = $vResult.copy_storage
$copyOtherOut  = $vResult.copy_other

$infoLines = @(
    "backup_timestamp       : $timestamp",
    "supabase_cli           : $supabaseVersion",
    "dump_scope_data        : public, private",
    "dump_flags_data        : --use-copy --data-only --schema public,private",
    "files                  : roles.sql, schema.sql, data.sql",
    "sha256_roles           : $shaRolesOut",
    "sha256_schema          : $shaSchemaOut",
    "sha256_data            : $shaDataOut",
    "copy_total             : $copyTotalOut",
    "copy_public            : $copyPublicOut",
    "copy_private           : $copyPrivOut",
    "copy_auth              : $copyAuthOut",
    "copy_storage           : $copyStorOut",
    "copy_other             : $copyOtherOut",
    "validation             : $validationResult",
    "classification         : CONFIDENTIAL",
    "contains_plaintext_pin : YES",
    "github_allowed         : NO"
)

$infoFile = Join-Path $backupDir 'backup-info.txt'
[System.IO.File]::WriteAllLines($infoFile, $infoLines, $utf8NoBom)
Write-Host "  backup-info.txt written (validation=$validationResult)"

if ($validateExitCode -ne 0) {
    Write-Error "Validation FAILED. ZIP not created. Inspect: $backupDir"
    exit 1
}

# --- 7. Zip (only on PASS) ---
Write-Host "[7/7] Creating zip..."
$zipPath = Join-Path $backupBase "$timestamp.sql.zip"
Compress-Archive -Path "$backupDir\*" -DestinationPath $zipPath
Remove-PrivateTempDirectory -Path $backupDir -TempRoot $TempRoot

Write-Host ""
Write-Host "Done: $zipPath"
Write-Host "Note: Do not push this file to GitHub."

} finally {
    $env:SUPABASE_DB_URL = $previousDbUrl
    if ($resultFile -and (Test-Path -LiteralPath $resultFile)) { Remove-Item -LiteralPath $resultFile -Force }
}
