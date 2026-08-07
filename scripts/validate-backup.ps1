#Requires -Version 5.1
<#
.SYNOPSIS
    Validates backup SQL dump files (roles.sql, schema.sql, data.sql).
.DESCRIPTION
    Checks: existence, size, encoding (BOM / CRLF / UTF-8), COPY block breakdown,
    column/TAB alignment, terminator, SHA-256.
    exit 0 on all PASS; exit 1 on any FAIL.
    Never outputs SQL content, PIN, secrets, or record values.
.PARAMETER BackupDir
    Folder containing roles.sql, schema.sql, and data.sql.
.EXAMPLE
    .\scripts\validate-backup.ps1 -BackupDir .\backups\20260806-120000
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupDir,

    # Optional: path for machine-readable JSON result file.
    # When specified, validate-backup.ps1 writes results after all checks complete.
    # When omitted, the script runs exactly as before (standalone mode).
    [Parameter(Mandatory = $false)]
    [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# check counters and failure list
$totalChecks = 0
$passChecks  = 0
$failures    = [System.Collections.Generic.List[string]]::new()

# SHA-256 results (populated in section 13; initialized here so result file
# always has these keys even if the script exits before section 13)
$shaRoles = ''; $shaSchema = ''; $shaData = ''

function Invoke-Check {
    param([string]$Label, [bool]$Pass, [string]$Detail = '')
    $script:totalChecks++
    if ($Pass) { $script:passChecks++ } else { $script:failures.Add($Label) }
    $mark = if ($Pass) { 'PASS' } else { 'FAIL' }
    $msg  = "  [$mark] $Label"
    if ($Detail) { $msg += " : $Detail" }
    Write-Host $msg
    # no return value - callers must not rely on pipeline output from this function
}

Write-Host '=== validate-backup ==='
Write-Host "  BackupDir : $BackupDir"
Write-Host ''

# ===========================================================
# 1. file existence
# ===========================================================
Write-Host '[1] file existence'

$rolesPath  = Join-Path $BackupDir 'roles.sql'
$schemaPath = Join-Path $BackupDir 'schema.sql'
$dataPath   = Join-Path $BackupDir 'data.sql'

$rolesOk  = Test-Path $rolesPath
$schemaOk = Test-Path $schemaPath
$dataOk   = Test-Path $dataPath
Invoke-Check 'roles.sql: exists'  $rolesOk
Invoke-Check 'schema.sql: exists' $schemaOk
Invoke-Check 'data.sql: exists'   $dataOk

if (-not ($rolesOk -and $schemaOk -and $dataOk)) {
    Write-Host ''
    Write-Host 'ABORT: required file(s) missing - skipping remaining checks'
    Write-Host ''
    Write-Host "=== result: FAIL ($passChecks / $totalChecks PASS) ==="
    exit 1
}

# ===========================================================
# 2. file size (must be > 0 bytes)
# ===========================================================
Write-Host ''
Write-Host '[2] file size'

$rolesSz  = (Get-Item $rolesPath ).Length
$schemaSz = (Get-Item $schemaPath).Length
$dataSz   = (Get-Item $dataPath  ).Length

Invoke-Check 'roles.sql > 0 byte'  ($rolesSz  -gt 0) "${rolesSz} bytes"
Invoke-Check 'schema.sql > 0 byte' ($schemaSz -gt 0) "${schemaSz} bytes"
Invoke-Check 'data.sql > 0 byte'   ($dataSz   -gt 0) "${dataSz} bytes"

# ===========================================================
# 3. UTF-8 BOM detection (no BOM = PASS)
# ===========================================================
Write-Host ''
Write-Host '[3] UTF-8 BOM detection (no BOM = PASS)'

function Test-NoBom ([string]$Path) {
    $buf = New-Object byte[] 3
    $fs  = [System.IO.File]::OpenRead($Path)
    try   { $read = $fs.Read($buf, 0, 3) }
    finally { $fs.Close() }
    if ($read -lt 3) { return $true }
    return -not ($buf[0] -eq 0xEF -and $buf[1] -eq 0xBB -and $buf[2] -eq 0xBF)
}

Invoke-Check 'roles.sql: no BOM'  (Test-NoBom $rolesPath)
Invoke-Check 'schema.sql: no BOM' (Test-NoBom $schemaPath)
Invoke-Check 'data.sql: no BOM'   (Test-NoBom $dataPath)

# ===========================================================
# 4. CRLF detection (data.sql only, no CRLF = PASS)
# ===========================================================
Write-Host ''
Write-Host '[4] CRLF detection (data.sql)'

$crCount = 0
$fsCrlf  = [System.IO.File]::OpenRead($dataPath)
try {
    $chunk = New-Object byte[] 65536
    $read  = 0
    while (($read = $fsCrlf.Read($chunk, 0, $chunk.Length)) -gt 0) {
        for ($i = 0; $i -lt $read; $i++) {
            if ($chunk[$i] -eq 0x0D) { $crCount++ }
        }
    }
} finally {
    $fsCrlf.Close()
}
Invoke-Check 'data.sql: no CRLF' ($crCount -eq 0) "CR bytes: ${crCount}"

# ===========================================================
# 5. UTF-8 strict decode + COPY block analysis (data.sql)
# Streaming via StreamReader - no full-file memory load.
# ===========================================================
Write-Host ''
Write-Host '[5] UTF-8 strict decode (data.sql)'

$strictUtf8    = [System.Text.UTF8Encoding]::new($false, $true)  # throwOnInvalidBytes
$utf8Ok        = $false
$utf8LineCount = 0
$utf8ErrMsg    = ''

$copyTotal     = 0
$copyPublic    = 0
$copyPrivate   = 0
$copyAuth      = 0
$copyStorage   = 0
$copyOther     = 0
$colMismatch   = 0
$copyUnclosed  = $false
$badCopyHeader = 0
$mismatchNotes = [System.Text.StringBuilder]::new()

$copyRx     = [regex]'^COPY\s+"?([A-Za-z_]\w*)"?\."?([A-Za-z_]\w*)"?\s*\((.+)\)\s+FROM\s+stdin;$'
$copyLikeRx = [regex]'^COPY\s+'

$inCopy     = $false
$expectCols = 0
$curSchema  = ''
$curTable   = ''
$rowIdx     = 0

try {
    $sr = [System.IO.StreamReader]::new($dataPath, $strictUtf8)
    try {
        $ln = $null
        while ($null -ne ($ln = $sr.ReadLine())) {
            $utf8LineCount++

            if (-not $inCopy) {
                $m = $copyRx.Match($ln)
                if ($m.Success) {
                    $copyTotal++
                    $curSchema  = $m.Groups[1].Value
                    $curTable   = $m.Groups[2].Value
                    $expectCols = ($m.Groups[3].Value -split ',').Count
                    switch ($curSchema) {
                        'public'  { $copyPublic++  }
                        'private' { $copyPrivate++ }
                        'auth'    { $copyAuth++    }
                        'storage' { $copyStorage++ }
                        default   { $copyOther++   }
                    }
                    $inCopy = $true
                    $rowIdx  = 0
                } elseif ($copyLikeRx.IsMatch($ln)) {
                    # looks like COPY but does not match full pattern (bad header)
                    $badCopyHeader++
                }
            } else {
                if ($ln -eq '\.') {
                    $inCopy = $false
                } else {
                    $rowIdx++
                    # verify TAB count = col count - 1 (no SQL content is output)
                    $tabs = $ln.Split("`t").Count - 1
                    if ($tabs -ne ($expectCols - 1)) {
                        $colMismatch++
                        if ($colMismatch -le 5) {
                            $null = $mismatchNotes.AppendLine(
                                "    ${curSchema}.${curTable} row${rowIdx}: expected_TAB=$($expectCols - 1) actual=$tabs")
                        }
                    }
                }
            }
        }
        # check for unclosed COPY block at EOF
        if ($inCopy) { $copyUnclosed = $true }
        $utf8Ok = $true
    } finally {
        $sr.Close()
    }
} catch {
    $utf8ErrMsg = $_.Exception.Message
}

if ($utf8Ok) { $decodeDetail = "${utf8LineCount} lines" } else { $decodeDetail = $utf8ErrMsg }
Invoke-Check 'data.sql: UTF-8 strict decode' $utf8Ok $decodeDetail

# ===========================================================
# 6-12. COPY block analysis results
# All COPY checks fail when UTF-8 decode failed (results unreliable).
# ===========================================================
Write-Host ''
Write-Host '[6-12] COPY block analysis (data.sql)'

if ($utf8Ok) {
    $copyNotPP = $copyAuth + $copyStorage + $copyOther

    Invoke-Check 'COPY block count > 0'            ($copyTotal -gt 0) "COPY blocks: ${copyTotal}"
    Invoke-Check 'auth COPY = 0'                   ($copyAuth    -eq 0) "auth COPY blocks: ${copyAuth}"
    Invoke-Check 'storage COPY = 0'                ($copyStorage -eq 0) "storage COPY blocks: ${copyStorage}"
    Invoke-Check 'COPY outside public/private = 0' ($copyNotPP -eq 0) "non-public/private COPY blocks: ${copyNotPP}"

    if ($colMismatch -gt 0) {
        Write-Host $mismatchNotes.ToString().TrimEnd()
    }
    Invoke-Check 'COPY column alignment (TAB = cols-1)' ($colMismatch -eq 0) "mismatched rows: ${colMismatch}"
    if ($copyUnclosed) { $termDetail = "unclosed COPY block detected (last: ${curSchema}.${curTable})" } else { $termDetail = 'OK' }
    Invoke-Check 'COPY terminator present (no unclosed block)' (-not $copyUnclosed) $termDetail
    Invoke-Check 'COPY unparseable header lines = 0' ($badCopyHeader -eq 0) "unparseable COPY headers: ${badCopyHeader}"
} else {
    $skipMsg = 'skipped: UTF-8 decode failed'
    Invoke-Check 'COPY block count > 0'                         $false $skipMsg
    Invoke-Check 'auth COPY = 0'                                $false $skipMsg
    Invoke-Check 'storage COPY = 0'                             $false $skipMsg
    Invoke-Check 'COPY outside public/private = 0'              $false $skipMsg
    Invoke-Check 'COPY column alignment (TAB = cols-1)'         $false $skipMsg
    Invoke-Check 'COPY terminator present (no unclosed block)'  $false $skipMsg
    Invoke-Check 'COPY unparseable header lines = 0'            $false $skipMsg
}

# ===========================================================
# 13. SHA-256 (FAIL on exception)
# ===========================================================
Write-Host ''
Write-Host '[13] SHA-256'

# SHA-256 values are stored in $shaRoles/$shaSchema/$shaData for the result file.
# They are NOT displayed in stdout (detail shows 'OK' only).
$ok = $false; $detail = ''
try { $shaRoles  = (Get-FileHash $rolesPath  -Algorithm SHA256).Hash; $ok = $true; $detail = 'OK' }
catch { $detail = $_.Exception.Message }
Invoke-Check 'roles.sql SHA-256'  $ok $detail

$ok = $false; $detail = ''
try { $shaSchema = (Get-FileHash $schemaPath -Algorithm SHA256).Hash; $ok = $true; $detail = 'OK' }
catch { $detail = $_.Exception.Message }
Invoke-Check 'schema.sql SHA-256' $ok $detail

$ok = $false; $detail = ''
try { $shaData   = (Get-FileHash $dataPath   -Algorithm SHA256).Hash; $ok = $true; $detail = 'OK' }
catch { $detail = $_.Exception.Message }
Invoke-Check 'data.sql SHA-256'   $ok $detail

# ===========================================================
# summary output
# ===========================================================
Write-Host ''
Write-Host '=== COPY summary ==='
Write-Host "  copy_total   : $copyTotal"
Write-Host "  copy_public  : $copyPublic"
Write-Host "  copy_private : $copyPrivate"
Write-Host "  copy_auth    : $copyAuth"
Write-Host "  copy_storage : $copyStorage"
Write-Host "  copy_other   : $copyOther"

Write-Host ''
$failCount = $totalChecks - $passChecks

# Write machine-readable result file when -ResultPath is specified.
# Written before exit so both PASS and FAIL cases produce the file.
# SQL content, record values, PIN, and connection strings are never included.
if ($ResultPath) {
    $validStatus = if ($failCount -eq 0) { 'PASSED' } else { 'FAILED' }
    $resultData  = [ordered]@{
        validation    = $validStatus
        checks_total  = $totalChecks
        checks_passed = $passChecks
        checks_failed = $failCount
        sha256_roles  = if ($shaRoles)  { $shaRoles  } else { '' }
        sha256_schema = if ($shaSchema) { $shaSchema } else { '' }
        sha256_data   = if ($shaData)   { $shaData   } else { '' }
        copy_total    = $copyTotal
        copy_public   = $copyPublic
        copy_private  = $copyPrivate
        copy_auth     = $copyAuth
        copy_storage  = $copyStorage
        copy_other    = $copyOther
    }
    $json      = $resultData | ConvertTo-Json
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($ResultPath, $json, $utf8NoBom)
}

if ($failCount -eq 0) {
    Write-Host "=== result: PASS ($passChecks / $totalChecks) ==="
    exit 0
} else {
    Write-Host "=== result: FAIL ($passChecks / $totalChecks PASS, $failCount FAIL) ==="
    Write-Host 'FAIL items:'
    foreach ($f in $failures) { Write-Host "  - $f" }
    exit 1
}
