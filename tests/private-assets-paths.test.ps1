param([Parameter(Mandatory=$true)][string]$TestRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (![IO.Path]::IsPathRooted($TestRoot) -or (Test-Path -LiteralPath $TestRoot)) { throw 'Supply a new absolute dummy TestRoot.' }
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/private-asset-paths.ps1')
$TestRoot = Resolve-PrivateAssetPath -Path $TestRoot
New-Item -ItemType Directory -Path $TestRoot | Out-Null
$code = Join-Path $TestRoot 'code'
$private = Join-Path $TestRoot 'private'
$scripts = Join-Path $code 'scripts'
New-Item -ItemType Directory -Path $scripts, $private | Out-Null
foreach ($name in @('private-asset-paths.ps1','backup-supabase.ps1','backup-supabase-storage.ps1')) {
    Copy-Item -LiteralPath (Join-Path $repo "scripts/$name") -Destination (Join-Path $scripts $name)
}
# Path-flow tests use a stub validator. Actual validation logic is not changed.
@'
param([string]$BackupDir,[string]$ResultPath)
$result=@{validation='PASSED';checks_total=1;checks_passed=1;checks_failed=0;sha256_roles='DUMMY';sha256_schema='DUMMY';sha256_data='DUMMY';copy_total=1;copy_public=1;copy_private=0;copy_auth=0;copy_storage=0;copy_other=0}
$result | ConvertTo-Json | Set-Content -LiteralPath $ResultPath
$global:LASTEXITCODE= $(if ($global:okgDummyFailValidation) {1} else {0})
'@ | Set-Content -LiteralPath (Join-Path $scripts 'validate-backup.ps1')
$global:okgDummyNpxCalls=0
$global:okgDummyHttpCalls=0
$global:okgDummyFailValidation=$false
function global:npx {
    $global:okgDummyNpxCalls++
    $global:LASTEXITCODE=0
    if ($args -contains '--version') { 'DUMMY-CLI'; return }
    $index=[array]::IndexOf($args,'-f')
    if ($index -lt 0) { throw 'Unexpected mock CLI command.' }
    [IO.File]::WriteAllText($args[$index+1], '-- DUMMY SQL ONLY')
}
function global:Invoke-WebRequest {
    param($Uri,$OutFile,[switch]$UseBasicParsing,$TimeoutSec)
    if ($Uri -notlike 'https://dummy.invalid/*') { throw 'Unexpected mock HTTP target.' }
    $global:okgDummyHttpCalls++
    [IO.File]::WriteAllText($OutFile,'DUMMY PHOTO')
}
function Assert-True { param([bool]$Condition,[string]$Label); if (!$Condition) {throw "FAIL: $Label"}; $script:passed++; Write-Output "PASS: $Label" }
function Assert-Rejected {
    param([scriptblock]$Action,[string]$Label)
    $rejected=$false
    try { & $Action | Out-Null } catch {$rejected=$true}
    Assert-True $rejected $Label
}
$script:passed=0
$inputEnv=Join-Path $private '.env.backup.local'
'SUPABASE_DB_URL=DUMMY-NOT-A-CONNECTION' | Set-Content -LiteralPath $inputEnv
$backup=Join-Path $private 'backups'
$temp=Join-Path $private 'tmp'
$previous=$env:SUPABASE_DB_URL
$env:SUPABASE_DB_URL='DUMMY-PREVIOUS'
try {
    & (Join-Path $scripts 'backup-supabase.ps1') -EnvFile $inputEnv -BackupRoot $backup -TempRoot $temp
    Assert-True (@(Get-ChildItem -LiteralPath $backup -Filter '*.sql.zip').Count -eq 1) 'DB ZIP in external BackupRoot'
    Assert-True (@(Get-ChildItem -LiteralPath $temp -Force).Count -eq 0) 'DB temporary SQL and result cleaned'
    Assert-True ($env:SUPABASE_DB_URL -eq 'DUMMY-PREVIOUS') 'DB environment restored'
    Assert-True ($global:okgDummyNpxCalls -eq 4) 'DB CLI entirely mocked (version + three dumps)'
    Assert-True (!(Test-Path (Join-Path $code 'backups'))) 'No repository backup output'
    $before=$global:okgDummyNpxCalls
    Assert-Rejected { & (Join-Path $scripts 'backup-supabase.ps1') -EnvFile $inputEnv -BackupRoot (Join-Path $code 'backups') -TempRoot $temp } 'Repository output rejected before CLI'
    Assert-Rejected { & (Join-Path $scripts 'backup-supabase.ps1') -EnvFile '.env.backup.local' -BackupRoot $backup -TempRoot $temp } 'Relative env path rejected'
    Assert-True ($global:okgDummyNpxCalls -eq $before) 'Rejected paths made no CLI calls'
    $global:okgDummyFailValidation=$true
    $failureTemp=Join-Path $private 'failure-tmp'
    Assert-Rejected { & (Join-Path $scripts 'backup-supabase.ps1') -EnvFile $inputEnv -BackupRoot $backup -TempRoot $failureTemp } 'DB failed validation stops ZIP creation'
    $global:okgDummyFailValidation=$false
    Assert-True (@(Get-ChildItem -LiteralPath $backup -Filter '*.sql.zip').Count -eq 1) 'Failed DB produced no extra ZIP'
    Assert-True (@(Get-ChildItem -LiteralPath $failureTemp -Filter 'vb-result-*').Count -eq 0) 'Failed DB result JSON cleaned'
    Assert-True (@(Get-ChildItem -LiteralPath $failureTemp -Directory).Count -eq 1) 'Failed DB dump retained only in external tmp'
    Assert-True ($env:SUPABASE_DB_URL -eq 'DUMMY-PREVIOUS') 'DB environment restored after failure'
    . (Join-Path $scripts 'private-asset-paths.ps1')
    Assert-Rejected {Resolve-PrivateAssetPath 'C:\'} 'Drive root rejected'
    $oldSync=$env:OneDrive
    $env:OneDrive=Join-Path $TestRoot 'fake-sync'
    try {Assert-Rejected {Resolve-PrivateAssetPath (Join-Path $env:OneDrive 'backups')} 'Known sync root rejected'} finally {$env:OneDrive=$oldSync}
    $junction=Join-Path $TestRoot 'alias'
    New-Item -ItemType Junction -Path $junction -Target $private | Out-Null
    Assert-Rejected {Resolve-PrivateAssetPath (Join-Path $junction 'tmp')} 'Linked private path rejected'
    $sql=Join-Path $private 'data.sql'
    @'
COPY public.reports (id, report_date, photo_urls, photo_count) FROM stdin;
DUMMY_ID	2026-01-01	{https://dummy.invalid/storage/v1/object/public/photos/folder/dummy.png}	1
\.
'@ | Set-Content -LiteralPath $sql
    & (Join-Path $scripts 'backup-supabase-storage.ps1') -DataSqlPath $sql -BackupRoot $backup -TempRoot $temp
    Assert-True ($global:okgDummyHttpCalls -eq 1) 'Storage download entirely mocked'
    Assert-True (@(Get-ChildItem -LiteralPath $backup -Filter '*-storage.zip').Count -eq 1) 'Storage ZIP in external BackupRoot'
    $zip=Join-Path $private 'input.sql.zip'
    Compress-Archive -LiteralPath $sql -DestinationPath $zip
    & (Join-Path $scripts 'backup-supabase-storage.ps1') -SqlZipPath $zip -BackupRoot $backup -TempRoot $temp
    Assert-True ($global:okgDummyHttpCalls -eq 2) 'External ZIP input supported'
    Assert-True (@(Get-ChildItem -LiteralPath $temp -Force).Count -eq 0) 'Storage ZIP extraction cleaned'
    $badZip=Join-Path $private 'bad.sql.zip'
    'DUMMY INVALID ZIP' | Set-Content -LiteralPath $badZip
    Assert-Rejected { & (Join-Path $scripts 'backup-supabase-storage.ps1') -SqlZipPath $badZip -BackupRoot $backup -TempRoot $temp } 'Invalid dummy ZIP fails safely'
    Assert-True (@(Get-ChildItem -LiteralPath $temp -Force).Count -eq 0) 'Extraction failure cleanup'
    Assert-True ($global:okgDummyHttpCalls -eq 2) 'Failed extraction made no HTTP calls'
    $oldText=Get-Content -LiteralPath $sql -Raw
    $oldText.Replace('folder/dummy.png','%2e%2e/%2e%2e/escape.png') | Set-Content -LiteralPath $sql
    & (Join-Path $scripts 'backup-supabase-storage.ps1') -DataSqlPath $sql -BackupRoot $backup -TempRoot $temp
    Assert-True ($LASTEXITCODE -eq 1) 'Encoded photo traversal rejected'
    Assert-True ($global:okgDummyHttpCalls -eq 2) 'Traversal made no HTTP calls'
    Assert-True (!(Test-Path (Join-Path $private 'escape.png'))) 'No escaped photo output'
    [pscustomobject]@{passed=$script:passed;npx_mock_calls=$global:okgDummyNpxCalls;http_mock_calls=$global:okgDummyHttpCalls;real_network_calls=0;dummy_root=$TestRoot} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $TestRoot 'result.json')
    Write-Output "RESULT: $($script:passed) checks passed (dummy only)."
} finally {
    $env:SUPABASE_DB_URL=$previous
    Remove-Item Function:\npx, Function:\Invoke-WebRequest
}
