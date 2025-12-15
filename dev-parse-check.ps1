$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile('C:\Projects\autoderiva\scripts\Install-AutoDeriva.ps1',[ref]$null,[ref]$errors)
if ($errors) { $errors | Format-List; exit 1 } else { Write-Host 'PARSE OK'; exit 0 }
