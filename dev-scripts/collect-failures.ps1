Import-Module Pester -ErrorAction Stop
$env:AUTODERIVA_TEST='1'
Import-Module Pester -ErrorAction Stop
Write-Host "Invoking Pester (pass-thru) to capture results..."
$r = Invoke-Pester -PassThru
Write-Host "FailedCount: $($r.FailedCount)"
Write-Host "Failed Tests Summary:" 
try {
	Write-Host "-- Full result object --"
	$r | Format-List * | Out-String | Write-Host
	$failed = $r.Results | Where-Object { $_.Status -eq 'Failed' }
	if ($failed) {
		$failed | ForEach-Object {
			Write-Host "- Name : $($_.Name)"; Write-Host "  Message: $($_.Message)"; Write-Host "  Error: $($_.Exception)"; Write-Host ""
		}
	}
}
catch {
	Write-Host "Could not enumerate failed tests: $_"
}
