param(
    [ValidateSet('Format', 'Lint', 'Test', 'All')][string]$Mode = 'All'
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-FileByteArray {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-True (Test-Path -LiteralPath $Path) "File not found: $Path"
    return [System.IO.File]::ReadAllBytes($Path)
}

function Assert-TextFileBasicHygiene {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $bytes = Get-FileByteArray -Path $Path

    # No NUL bytes (catches UTF-16 / binary)
    Assert-True (-not ($bytes -contains 0)) "$($Label): contains NUL bytes (likely UTF-16/binary). Use UTF-8 text."

    $text = [System.Text.Encoding]::UTF8.GetString($bytes)

    # Basic newline hygiene: require CRLF
    Assert-True ($text -match "\r\n") "$($Label): does not appear to contain CRLF newlines."
    Assert-True (-not ($text -match "(?<!\r)\n")) "$($Label): contains LF-only newlines. Use CRLF."

    # No tabs
    Assert-True (-not ($text -match "\t")) "$($Label): contains TAB characters."

    # No trailing whitespace on any line
    Assert-True (-not ($text -match "[ \t]+\r$")) "$($Label): contains trailing whitespace."
}

function Import-CsvStrict {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    try {
        $rows = Import-Csv -LiteralPath $Path
        return ,$rows
    }
    catch {
        throw "$($Label): failed to parse as CSV: $_"
    }
}

function Assert-HeadersExact {
    param(
        [Parameter(Mandatory = $true)][string[]]$Actual,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $actualJoined = ($Actual -join ',')
    $expectedJoined = ($Expected -join ',')
    Assert-True ($actualJoined -eq $expectedJoined) "$($Label): header mismatch. Expected '$expectedJoined' but got '$actualJoined'."

    $dupes = $Actual | Group-Object | Where-Object { $_.Count -gt 1 } | Select-Object -ExpandProperty Name
    Assert-True ($dupes.Count -eq 0) "$($Label): duplicate header(s): $($dupes -join ', ')"
}

function Get-CsvHeadersRaw {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $firstLine = (Get-Content -LiteralPath $Path -TotalCount 1)
    Assert-True ([string]::IsNullOrWhiteSpace($firstLine) -eq $false) "CSV appears empty: $Path"

    # CSVs in this repo use quoted headers.
    $headers = $firstLine -split ',' | ForEach-Object { $_.Trim().Trim('"') }
    return ,$headers
}

function Assert-DriverManifest {
    param([Parameter(Mandatory = $true)][string]$Path)

    $label = "driver_file_manifest.csv"

    $headers = Get-CsvHeadersRaw -Path $Path
    Assert-HeadersExact -Actual $headers -Expected @('RelativePath', 'Size', 'Sha256', 'AssociatedInf') -Label $label

    $rows = Import-CsvStrict -Path $Path -Label $label
    Assert-True ($rows.Count -gt 0) "$($label): expected at least 1 data row."

    foreach ($row in $rows) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($row.RelativePath)) "$($label): RelativePath is empty."
        Assert-True ($row.RelativePath -match "^drivers/") "$($label): RelativePath must start with 'drivers/': $($row.RelativePath)"
        Assert-True ($row.RelativePath -notmatch "\\") "$($label): RelativePath must use forward slashes: $($row.RelativePath)"

        if (-not [string]::IsNullOrWhiteSpace($row.AssociatedInf)) {
            Assert-True ($row.AssociatedInf -match "^drivers/") "$($label): AssociatedInf must start with 'drivers/': $($row.AssociatedInf)"
            Assert-True ($row.AssociatedInf -notmatch "\\") "$($label): AssociatedInf must use forward slashes: $($row.AssociatedInf)"
            Assert-True ($row.AssociatedInf -match "\.inf$" ) "$($label): AssociatedInf should end with .inf: $($row.AssociatedInf)"
        }

        $tmp = 0L
        $sizeOk = [int64]::TryParse([string]$row.Size, [ref]$tmp)
        Assert-True ($sizeOk -and $tmp -ge 0) "$($label): Size must be an integer >= 0 for $($row.RelativePath) (got '$($row.Size)')"

        Assert-True (-not [string]::IsNullOrWhiteSpace($row.Sha256)) "$($label): Sha256 is empty for $($row.RelativePath)"
        Assert-True ($row.Sha256 -match '^[A-Fa-f0-9]{64}$') "$($label): Sha256 must be 64 hex chars for $($row.RelativePath) (got '$($row.Sha256)')"
    }
}

function Assert-DriverInventory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $label = "driver_inventory.csv"

    $headers = Get-CsvHeadersRaw -Path $Path
    Assert-HeadersExact -Actual $headers -Expected @('FileName', 'InfPath', 'Class', 'Provider', 'Date', 'Version', 'HardwareIDs') -Label $label

    $rows = Import-CsvStrict -Path $Path -Label $label
    Assert-True ($rows.Count -gt 0) "$($label): expected at least 1 data row."

    foreach ($row in $rows) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($row.FileName)) "$($label): FileName is empty."
        Assert-True ($row.FileName -match "\.inf$" ) "$($label): FileName must end with .inf (got '$($row.FileName)')"

        Assert-True (-not [string]::IsNullOrWhiteSpace($row.InfPath)) "$($label): InfPath is empty for $($row.FileName)"
        Assert-True ($row.InfPath -match "\.inf$" ) "$($label): InfPath must end with .inf for $($row.FileName) (got '$($row.InfPath)')"

        Assert-True (-not [string]::IsNullOrWhiteSpace($row.Class)) "$($label): Class is empty for $($row.FileName)"
        Assert-True (-not [string]::IsNullOrWhiteSpace($row.Provider)) "$($label): Provider is empty for $($row.FileName)"

        # Date/Version/HardwareIDs are allowed to contain TODO annotations today, so keep checks light.
    }
}

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$exportsDir = Join-Path $repoRoot 'exports'
$manifestPath = Join-Path $exportsDir 'driver_file_manifest.csv'
$inventoryPath = Join-Path $exportsDir 'driver_inventory.csv'

if ($Mode -in @('Format', 'All')) {
    Write-Host "CSV: format check" -ForegroundColor Cyan
    Assert-TextFileBasicHygiene -Path $manifestPath -Label 'exports/driver_file_manifest.csv'
    Assert-TextFileBasicHygiene -Path $inventoryPath -Label 'exports/driver_inventory.csv'
    Write-Host "CSV: format check OK" -ForegroundColor Green
}

if ($Mode -in @('Lint', 'All')) {
    Write-Host "CSV: lint check" -ForegroundColor Cyan
    Assert-DriverManifest -Path $manifestPath
    Assert-DriverInventory -Path $inventoryPath
    Write-Host "CSV: lint check OK" -ForegroundColor Green
}

if ($Mode -in @('Test', 'All')) {
    Write-Host "CSV: runtime parse test" -ForegroundColor Cyan
    [void](Import-CsvStrict -Path $manifestPath -Label 'exports/driver_file_manifest.csv')
    [void](Import-CsvStrict -Path $inventoryPath -Label 'exports/driver_inventory.csv')
    Write-Host "CSV: runtime parse test OK" -ForegroundColor Green
}
