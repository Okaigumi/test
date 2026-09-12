# Shared path validation. No secret reads or directory creation.
function Test-AssetPathWithin {
    param([string]$Path, [string]$Root)
    $r = $Root.TrimEnd('\', '/')
    return $Path.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or
        $Path.StartsWith($r + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
function Resolve-PrivateAssetPath {
    param([Parameter(Mandatory=$true)][string]$Path,
          [ValidateSet('File','Directory')][string]$Kind = 'Directory')
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(2) -match '[:*?"<>|]') {
        throw 'Private asset path must be an absolute local drive path.'
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    if ($full -match '^[A-Za-z]:$') { throw 'A drive root is not a private asset directory.' }
    $repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
    if (Test-AssetPathWithin $full $repo) { throw 'Private assets must be outside the repository.' }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Private asset paths cannot contain links.' }
            if ($item.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $cursor '.git'))) {
                throw 'Private assets must be outside Git working trees.'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    $syncRoots = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)
    $accountsKey = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (Test-Path $accountsKey) {
        foreach ($key in Get-ChildItem $accountsKey) {
            $account = Get-ItemProperty $key.PSPath
            if ($account.PSObject.Properties['UserFolder']) { $syncRoots += $account.UserFolder }
        }
    }
    foreach ($base in @($env:LOCALAPPDATA, $env:APPDATA)) {
        if (!$base) { continue }
        $info = Join-Path $base 'Dropbox\info.json'
        if (Test-Path -LiteralPath $info) {
            $dropbox = Get-Content -LiteralPath $info -Raw | ConvertFrom-Json
            foreach ($account in $dropbox.PSObject.Properties) { $syncRoots += $account.Value.path }
        }
    }
    foreach ($root in $syncRoots) {
        if ($root -and (Test-AssetPathWithin $full ([IO.Path]::GetFullPath($root)))) { throw 'Private assets must be outside known cloud sync roots.' }
    }
    if ($Kind -eq 'File' -and !(Test-Path -LiteralPath $full -PathType Leaf)) { throw 'Private input file does not exist.' }
    if ($Kind -eq 'Directory' -and (Test-Path -LiteralPath $full) -and !(Test-Path -LiteralPath $full -PathType Container)) { throw 'Expected a directory.' }
    return $full
}
function Remove-PrivateTempDirectory {
    param([string]$Path, [string]$TempRoot)
    $full = Resolve-PrivateAssetPath -Path $Path
    $root = Resolve-PrivateAssetPath -Path $TempRoot
    if ($full -eq $root -or !(Test-AssetPathWithin $full $root)) { throw 'Unsafe temporary cleanup target.' }
    if (Test-Path -LiteralPath $full) {
        foreach ($item in Get-ChildItem -LiteralPath $full -Recurse -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Link detected in temporary directory.' }
        }
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
