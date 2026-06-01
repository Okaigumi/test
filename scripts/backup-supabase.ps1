#Requires -Version 5.1
<#
.SYNOPSIS
    Supabase 本番DBのローカルバックアップを取得する
.DESCRIPTION
    .env.backup.local から SUPABASE_DB_URL を読み込み、
    roles / schema / data の3ファイルをダンプして zip 化する。
    接続文字列・パスワードは画面に表示しない。
.NOTES
    前提: Node.js / npx がインストール済みであること
    動作確認: Windows PowerShell 5.1 以上（PowerShell 7 推奨）
    実行: .\scripts\backup-supabase.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- 1. npx が使えるか確認 ---
Write-Host "[1/6] npx の確認..."
try {
    $null = Get-Command npx -ErrorAction Stop
} catch {
    Write-Error "npx が見つかりません。Node.js をインストールしてください。"
    exit 1
}

# --- 2. npx --yes supabase --version で Supabase CLI 確認 ---
Write-Host "[2/6] Supabase CLI (npx) の確認..."
try {
    $supabaseVersion = npx --yes supabase --version 2>&1
    Write-Host "  Supabase CLI: $supabaseVersion"
} catch {
    Write-Error "npx --yes supabase --version に失敗しました。Node.js / ネットワーク接続を確認してください。"
    exit 1
}

# --- 3. .env.backup.local から SUPABASE_DB_URL を読み込む ---
Write-Host "[3/6] .env.backup.local を読み込み中..."

$envFile = ".env.backup.local"

if (-not (Test-Path $envFile)) {
    throw ".env.backup.local が見つかりません。.env.backup.local.example を参考に作成してください。"
}

$line = Get-Content $envFile | Where-Object { $_ -match '^\s*SUPABASE_DB_URL\s*=' } | Select-Object -First 1

if (-not $line) {
    throw ".env.backup.local に SUPABASE_DB_URL がありません。"
}

$value = $line -replace '^\s*SUPABASE_DB_URL\s*=\s*', ''
$value = $value.Trim()
$value = $value.Trim('"')

if ([string]::IsNullOrWhiteSpace($value)) {
    throw "SUPABASE_DB_URL が空です。"
}

$env:SUPABASE_DB_URL = $value
Write-Host "  SUPABASE_DB_URL: ロード済み（内容は表示しません）"

# --- 4. バックアップフォルダを作成 ---
$timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$backupBase = Join-Path $PSScriptRoot "..\backups"
$backupDir  = Join-Path $backupBase $timestamp
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Write-Host "[4/6] バックアップフォルダ作成: backups\$timestamp"

# --- 5. ダンプ実行 ---
Write-Host "[5/6] ダンプ開始..."

Write-Host "  roles.sql ..."
npx --yes supabase db dump --db-url "$env:SUPABASE_DB_URL" -f "$backupDir\roles.sql" --role-only
if ($LASTEXITCODE -ne 0) {
    Write-Error "roles.sql のダンプに失敗しました。"
    exit 1
}

Write-Host "  schema.sql ..."
npx --yes supabase db dump --db-url "$env:SUPABASE_DB_URL" -f "$backupDir\schema.sql"
if ($LASTEXITCODE -ne 0) {
    Write-Error "schema.sql のダンプに失敗しました。"
    exit 1
}

Write-Host "  data.sql ..."
npx --yes supabase db dump --db-url "$env:SUPABASE_DB_URL" -f "$backupDir\data.sql" --use-copy --data-only -x "storage.buckets_vectors" -x "storage.vector_indexes"
if ($LASTEXITCODE -ne 0) {
    Write-Error "data.sql のダンプに失敗しました。"
    exit 1
}

# --- backup-info.txt を作成 ---
$infoFile = Join-Path $backupDir "backup-info.txt"
@"
backup_timestamp : $timestamp
supabase_cli     : $supabaseVersion
files            : roles.sql, schema.sql, data.sql
note             : Supabase Storage (photos バケット) はこのバックアップに含まれません
"@ | Set-Content -Encoding UTF8 $infoFile
Write-Host "  backup-info.txt 作成済み"

# --- 6. zip 化 ---
Write-Host "[6/6] zip 化..."
$zipPath = Join-Path $backupBase "$timestamp.sql.zip"
Compress-Archive -Path "$backupDir\*" -DestinationPath $zipPath -Force
Write-Host "  zip 作成: backups\$timestamp.sql.zip"

# 元フォルダを削除（zip があれば不要）
Remove-Item -Recurse -Force $backupDir

Write-Host ""
Write-Host "完了: backups\$timestamp.sql.zip"
Write-Host "注意: このファイルは GitHub に push しないでください。"
