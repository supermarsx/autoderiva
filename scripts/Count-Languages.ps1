<#
.SYNOPSIS
Counts languages in the repository but ignores `drivers` and `cuco` by default.

.DESCRIPTION
This script attempts to use `cloc` if available (recommended) and will pass an exclude list to it. If `cloc` is not available, it falls back to a simple, fast PowerShell implementation that maps file extensions to languages and counts files and lines.

.EXAMPLE
# Run with defaults (ignores drivers and cuco)
.
\scripts\Count-Languages.ps1

# Run with cloc and additional excludes
.
\scripts\Count-Languages.ps1 -ExtraExcludes @('tools','third_party')
# Or point to a custom exclude list file
.
\scripts\Count-Languages.ps1 -ExcludeListFile .\scripts\my_excludes.txt
#>

param(
    [string[]] $ExtraExcludes = @(),
    [string] $ExcludeListFile = "",
    [switch] $UseCloc = $true,
    [string] $OutputFile = "language_summary.csv"
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
Set-Location $repoRoot

# Default excludes
$excludes = @('drivers','cuco') + $ExtraExcludes

# If user provided an exclude list file, load it and merge
if ($ExcludeListFile -and (Test-Path $ExcludeListFile)) {
    $fileExcludes = Get-Content -Path $ExcludeListFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $excludes += $fileExcludes
}

# Also include specific driver folders (from driver_folders.txt) if present -- this helps cloc more precisely
$driverListFile = Join-Path $repoRoot 'driver_folders.txt'
if (Test-Path $driverListFile) {
    $driverList = Get-Content -Path $driverListFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    # Convert to folder names relative to repoRoot (cloc expects comma-separated folder names)
    $excludes += $driverList
}

$excludes = $excludes | Select-Object -Unique

Write-Host "Excluding $(($excludes).Count) paths from language count." -ForegroundColor Cyan

# If cloc is available and user wants to use it
if ($UseCloc -and (Get-Command cloc -ErrorAction SilentlyContinue)) {
    Write-Host "cloc detected — using cloc for accurate results." -ForegroundColor Green

    # cloc allows --exclude-dir or --exclude-list-file
    $tempExcludeFile = Join-Path $env:TEMP "autoderiva_cloc_excludes.txt"
    $excludes | Out-File -FilePath $tempExcludeFile -Encoding UTF8

    $outPath = Join-Path $repoRoot "cloc_output.csv"

    # Run cloc with CSV output
    $args = @("--exclude-list-file=$tempExcludeFile", "--csv", "--out=$outPath", ".")
    Write-Host "Running: cloc $($args -join ' ')"

    & cloc @args
n
    if (Test-Path $outPath) {
        Write-Host "cloc output saved to: $outPath" -ForegroundColor Green
        # Optionally copy to OutputFile name requested
        Copy-Item -Path $outPath -Destination (Join-Path $repoRoot $OutputFile) -Force
        Write-Host "Summary saved to: $OutputFile"
    }
    else {
        Write-Warning "cloc finished but no output file was found."
    }

    # cleanup
    Remove-Item $tempExcludeFile -ErrorAction SilentlyContinue

    return
}

Write-Host "cloc not available or disabled; using fallback PowerShell scanner." -ForegroundColor Yellow

# Extension -> language map (common languages)
$extLang = @{
    'ps1'   = 'PowerShell'
    'psm1'  = 'PowerShell'
    'py'    = 'Python'
    'rb'    = 'Ruby'
    'js'    = 'JavaScript'
    'ts'    = 'TypeScript'
    'cs'    = 'C#'
    'cpp'   = 'C++'
    'c'     = 'C'
    'h'     = 'C/C++ Header'
    'java'  = 'Java'
    'go'    = 'Go'
    'rs'    = 'Rust'
    'php'   = 'PHP'
    'html'  = 'HTML'
    'css'   = 'CSS'
    'json'  = 'JSON'
    'xml'   = 'XML'
    'md'    = 'Markdown'
    'yml'   = 'YAML'
    'yaml'  = 'YAML'
    'sh'    = 'Shell'
    'bat'   = 'Batch'
    'psd1'  = 'PowerShell'
}

# Build a set of absolute exclude paths
$absExcludes = @()
foreach ($e in $excludes) {
    # If it's already an absolute path, use it; else assume relative to repo root
    if ([System.IO.Path]::IsPathRooted($e)) { $absExcludes += (Resolve-Path $e).Path } else { $absExcludes += (Join-Path $repoRoot $e) }
}

# Collect files, skipping excluded dirs
$allFiles = Get-ChildItem -Path $repoRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    # skip files that are inside any excluded path
    $full = $_.FullName
    -not ($absExcludes | ForEach-Object { if ($full -like "$_*") { return $true } else { return $false } } | Where-Object { $_ })
}

# Tally by language
$summary = @{}

foreach ($f in $allFiles) {
    $ext = $f.Extension.TrimStart('.').ToLower()
    if (-not $ext) { continue }
    $lang = $extLang[$ext]
    if (-not $lang) { $lang = $ext.ToUpper() }

    # Try count lines — skip non-text heuristically by size or extension
    $lines = 0
    try {
        # only attempt for reasonable sized files
        if ($f.Length -lt 20MB) {
            $lines = (Get-Content -Path $f.FullName -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
        }
    } catch { }

    if (-not $summary.ContainsKey($lang)) {
        $summary[$lang] = [ordered]@{ Files = 0; Lines = 0; Bytes = 0 }
    }

    $summary[$lang].Files += 1
    $summary[$lang].Lines += $lines
    $summary[$lang].Bytes += $f.Length
}

# Convert to objects and export
$rows = $summary.GetEnumerator() | ForEach-Object {
    [PSCustomObject]@{
        Language = $_.Key
        Files    = $_.Value.Files
        Lines    = $_.Value.Lines
        Bytes    = $_.Value.Bytes
    }
} | Sort-Object -Property Files -Descending

$rows | Export-Csv -Path (Join-Path $repoRoot $OutputFile) -NoTypeInformation -Encoding utf8

Write-Host "Counted $(($rows | Measure-Object).Count) languages. Output: $OutputFile" -ForegroundColor Green

# Also print a short table
$rows | Format-Table -AutoSize
