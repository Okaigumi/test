#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$TestRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/private-asset-paths.ps1')
$TestRoot = Resolve-PrivateAssetPath -Path $TestRoot
if (Test-Path -LiteralPath $TestRoot) { throw 'Use a new external dummy TestRoot.' }
New-Item -ItemType Directory -Path $TestRoot | Out-Null
$results = @()
$global:summaryDummyCalls = 0
function global:npx {
    $global:summaryDummyCalls++
    $global:LASTEXITCODE = 0
    if ($args -contains '--version') { 'DUMMY-CLI'; return }
    $index = [array]::IndexOf($args, '-f')
    if ($index -lt 0) { throw 'Unexpected mock CLI command.' }
    [IO.File]::WriteAllText($args[$index + 1], '-- DUMMY SQL ONLY')
}
function Check { param([bool]$Condition,[string]$Message); if (!$Condition) { throw "FAIL: $Message" } }
$previous = $env:SUPABASE_DB_URL
$cases = @('pass','fail','missing-json','bad-json','missing-field','null-field','validator-throws','missing-validator',
           'array-json','single-object-array','array-status','bad-count','bad-status','inconsistent-counts','failed-exit-zero','passed-exit-one','missing-exit')
try {
    foreach ($case in $cases) {
        $root = Join-Path $TestRoot $case
        $scripts = Join-Path $root 'code/scripts'
        $private = Join-Path $root 'private'
        $backup = Join-Path $private 'backups'
        $temp = Join-Path $private 'tmp'
        New-Item -ItemType Directory -Path $scripts,$backup,$temp | Out-Null
        foreach ($name in @('backup-supabase.ps1','private-asset-paths.ps1')) {
            Copy-Item -LiteralPath (Join-Path $repo "scripts/$name") -Destination (Join-Path $scripts $name)
        }
        $inputEnv = Join-Path $private '.env.backup.local'
        'SUPABASE_DB_URL=DUMMY-NOT-A-CONNECTION' | Set-Content -LiteralPath $inputEnv
        $oldZip = Join-Path $backup '20000101-000000-000.sql.zip'
        [IO.File]::WriteAllText($oldZip,'DUMMY OLD BACKUP - MUST NOT CHANGE')
        $oldDir = Join-Path $temp 'old-run'
        New-Item -ItemType Directory -Path $oldDir | Out-Null
        $oldSummary = Join-Path $oldDir 'backup-info.txt'
        [IO.File]::WriteAllText($oldSummary,'validation : PASSED - DUMMY OLD RESULT')
        $oldZipHash = (Get-FileHash -LiteralPath $oldZip).Hash
        $oldSummaryHash = (Get-FileHash -LiteralPath $oldSummary).Hash
        $global:summaryDummyCase = $case
        if ($case -ne 'missing-validator') {
@'
param([string]$BackupDir,[string]$ResultPath)
$global:LASTEXITCODE = 0
$r = [ordered]@{validation='PASSED';checks_total=21;checks_passed=21;checks_failed=0;sha256_roles='DUMMY';sha256_schema='DUMMY';sha256_data='DUMMY';copy_total=1;copy_public=1;copy_private=0;copy_auth=0;copy_storage=0;copy_other=0}
switch ($global:summaryDummyCase) {
    'validator-throws' { [IO.File]::WriteAllText($ResultPath,'DUMMY PARTIAL'); throw 'DUMMY validator exception' }
    'missing-json' { return }
    'bad-json' { [IO.File]::WriteAllText($ResultPath,'{DUMMY INVALID'); return }
    'array-json' { [IO.File]::WriteAllText($ResultPath,'[]'); return }
    'single-object-array' { [IO.File]::WriteAllText($ResultPath,('[' + ($r | ConvertTo-Json) + ']')); return }
    'array-status' { $r.validation = @('PASSED') }
    'missing-field' { $r.Remove('sha256_roles') }
    'null-field' { $r.sha256_roles = $null }
    'bad-count' { $r.checks_total = '21' }
    'bad-status' { $r.validation = 'UNKNOWN' }
    'inconsistent-counts' { $r.checks_passed = 20 }
    'fail' { $r.validation='FAILED';$r.checks_passed=20;$r.checks_failed=1;$r.sha256_roles='';$global:LASTEXITCODE=1 }
    'failed-exit-zero' { $r.validation='FAILED';$r.checks_passed=20;$r.checks_failed=1 }
    'passed-exit-one' { $global:LASTEXITCODE=1 }
    'missing-exit' { $global:LASTEXITCODE=$null }
}
$r | ConvertTo-Json | Set-Content -LiteralPath $ResultPath
'@ | Set-Content -LiteralPath (Join-Path $scripts 'validate-backup.ps1')
        }
        $env:SUPABASE_DB_URL = 'DUMMY-PREVIOUS'
        $beforeCalls = $global:summaryDummyCalls
        $failed = $false
        $output = @()
        try {
            $output = @(& (Join-Path $scripts 'backup-supabase.ps1') -EnvFile $inputEnv -BackupRoot $backup -TempRoot $temp 6>&1)
        } catch { $failed = $true; if ($case -eq 'pass') { throw } }
        $success = $case -eq 'pass'
        $hasFailedSummary = $case -in @('fail','failed-exit-zero','passed-exit-one')
        $newZips = @(Get-ChildItem -LiteralPath $backup -Filter '*.sql.zip' | Where-Object {$_.FullName -ne $oldZip})
        $newDumps = @(Get-ChildItem -LiteralPath $temp -Directory -Filter 'db-*')
        Check ($failed -ne $success) "$case failure status"
        Check ($newZips.Count -eq [int]$success) "$case current-run ZIP count"
        Check ($newDumps.Count -eq [int](!$success)) "$case current-run dump retention"
        if (!$success) {
            $summary = Join-Path $newDumps[0].FullName 'backup-info.txt'
            Check ((Test-Path -LiteralPath $summary) -eq $hasFailedSummary) "$case current-run summary presence"
            if ($hasFailedSummary) {
                $text = Get-Content -LiteralPath $summary -Raw
                Check ($text -match 'validation\s+: FAILED') "$case FAILED summary"
                Check ($text -notmatch 'validation\s+: PASSED') "$case not marked PASSED"
            }
            Check (($output -join "`n") -notmatch '(?m)^Done:') "$case no success announcement"
        } else {
            # Only synthetic data is opened; no real backup is used.
            $inspect = Join-Path $private 'dummy-inspection'
            Expand-Archive -LiteralPath $newZips[0].FullName -DestinationPath $inspect
            Check ((Get-Content -LiteralPath (Join-Path $inspect 'backup-info.txt') -Raw) -match 'validation\s+: PASSED') 'pass ZIP summary'
        }
        Check (@(Get-ChildItem -LiteralPath $temp -Filter 'vb-result-*').Count -eq 0) "$case result JSON cleanup"
        Check ($env:SUPABASE_DB_URL -eq 'DUMMY-PREVIOUS') "$case environment restored"
        Check ((Get-FileHash -LiteralPath $oldZip).Hash -eq $oldZipHash) "$case previous ZIP preserved"
        Check ((Get-FileHash -LiteralPath $oldSummary).Hash -eq $oldSummaryHash) "$case previous summary preserved"
        Check ($global:summaryDummyCalls - $beforeCalls -eq 4) "$case CLI calls all mocked"
        $results += [pscustomobject]@{case=$case;passed=$true;failedAsExpected=(!$success);newZipCount=$newZips.Count;failedSummary=$hasFailedSummary;previousArtifactsPreserved=$true}
        Write-Output "PASS: $case"
    }
    [ordered]@{powershell=$PSVersionTable.PSVersion.ToString();passed=$results.Count;cases=$results;realNetworkCalls=0;npxMockCalls=$global:summaryDummyCalls;testRoot=$TestRoot} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $TestRoot 'result.json')
    Write-Output "RESULT: $($results.Count) dummy cases passed."
} finally {
    $env:SUPABASE_DB_URL=$previous
    Remove-Item Function:\npx
    Remove-Variable summaryDummyCase,summaryDummyCalls -Scope Global -ErrorAction SilentlyContinue
}
