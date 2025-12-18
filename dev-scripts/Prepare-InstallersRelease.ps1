[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,

    [Parameter()]
    [string]$DistDirName = 'dist',

    [Parameter()]
    [string]$AssetName = 'Install-AutoDeriva.bat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$distDir = Join-Path $RepoRoot $DistDirName
$sourceAssetPath = Join-Path $RepoRoot $AssetName
$distAssetPath = Join-Path $distDir $AssetName
$notesPath = Join-Path $distDir 'release-notes.md'

if (-not (Test-Path -LiteralPath $sourceAssetPath)) {
    throw "Required asset not found: $sourceAssetPath"
}

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Copy-Item -LiteralPath $sourceAssetPath -Destination $distAssetPath -Force

$hash = (Get-FileHash -LiteralPath $distAssetPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sizeBytes = (Get-Item -LiteralPath $distAssetPath).Length

$repo = $env:GITHUB_REPOSITORY
if ([string]::IsNullOrWhiteSpace($repo)) {
    $repo = '<owner>/<repo>'
}

$sha = $env:GITHUB_SHA
if ([string]::IsNullOrWhiteSpace($sha)) {
    $sha = '<commit>'
}

$utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$downloadUrl = "https://github.com/$repo/releases/latest/download/$AssetName"

$notes = @(
    "# Installers",
    "",
    "This release is automatically maintained by GitHub Actions.",
    "",
    "Updated: $utc",
    "Source commit: $sha",
    "",
    "## Assets",
    "- $AssetName",
    ("  - SHA256: " + $hash),
    "  - Size: $sizeBytes bytes",
    "",
    "## Download",
    "- $downloadUrl",
    ""
) -join "`n"

Set-Content -LiteralPath $notesPath -Value $notes -Encoding utf8

Write-Host "Prepared release assets:" 
Write-Host "- $distAssetPath"
Write-Host "- $notesPath"
Write-Host "SHA256: $hash"