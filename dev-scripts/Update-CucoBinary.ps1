[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string]$RepoRoot,

    [Parameter()]
    [string]$PrimaryUrl = 'https://cuco.inforlandia.pt/uagent/CtoolGui.exe',

    [Parameter()]
    [string]$OutRelativePath = 'cuco/CtoolGui.exe',

    [Parameter()]
    [int]$TimeoutSec = 120,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
}

function Invoke-DownloadFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$OutFile,

        [Parameter()]
        [int]$TimeoutSec = 120
    )

    # Windows PowerShell (5.1) can require forcing TLS 1.2 for some hosts.
    try {
        if ($PSVersionTable.PSEdition -ne 'Core') {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        }
    }
    catch {
        Write-Verbose ("TLS configuration not supported/failed: " + $_.Exception.Message)
    }

    $iwr = Get-Command Invoke-WebRequest -ErrorAction Stop
    $params = @{
        Uri     = $Uri
        OutFile = $OutFile
    }

    if ($iwr.Parameters.ContainsKey('UseBasicParsing')) {
        $params.UseBasicParsing = $true
    }

    if ($iwr.Parameters.ContainsKey('TimeoutSec')) {
        $params.TimeoutSec = $TimeoutSec
    }

    Invoke-WebRequest @params | Out-Null
}

$outPath = Join-Path $RepoRoot $OutRelativePath
$outDir = Split-Path -Parent $outPath

if (-not (Test-Path -LiteralPath $RepoRoot)) {
    throw "RepoRoot not found: $RepoRoot"
}

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$oldHash = $null
$oldSize = $null
if (Test-Path -LiteralPath $outPath) {
    $oldHash = (Get-FileHash -LiteralPath $outPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $oldSize = (Get-Item -LiteralPath $outPath).Length
}

$tempPath = Join-Path $outDir ((Split-Path -Leaf $outPath) + '.download')
if (Test-Path -LiteralPath $tempPath) {
    Remove-Item -LiteralPath $tempPath -Force
}

Write-Host "Updating Cuco binary..."
Write-Host "- Source: $PrimaryUrl"
Write-Host "- Target: $outPath"

$shouldDownload = $PSCmdlet.ShouldProcess($outPath, 'Download latest Cuco binary')
if (-not $shouldDownload) {
    return
}

Invoke-DownloadFile -Uri $PrimaryUrl -OutFile $tempPath -TimeoutSec $TimeoutSec

if (-not (Test-Path -LiteralPath $tempPath)) {
    throw "Download failed; temp file missing: $tempPath"
}

$newHash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash.ToLowerInvariant()
$newSize = (Get-Item -LiteralPath $tempPath).Length

if (-not $Force -and $oldHash -and ($oldHash -eq $newHash)) {
    Remove-Item -LiteralPath $tempPath -Force
    Write-Host "Cuco binary is already up-to-date." 
    Write-Host "SHA256: $newHash"
    Write-Host "Size:   $newSize bytes"
    exit 0
}

$shouldReplace = $PSCmdlet.ShouldProcess($outPath, 'Replace with downloaded binary')
if (-not $shouldReplace) {
    return
}

Move-Item -LiteralPath $tempPath -Destination $outPath -Force

Write-Host "Updated Cuco binary." 
if ($oldHash) {
    Write-Host "Old SHA256: $oldHash"
    Write-Host "Old size:   $oldSize bytes"
}
Write-Host "New SHA256: $newHash"
Write-Host "New size:   $newSize bytes"

Write-Host "Next: git status; git add $OutRelativePath; git commit -m 'Update Cuco binary'"