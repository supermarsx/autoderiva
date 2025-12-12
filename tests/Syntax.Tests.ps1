$ErrorActionPreference = "Stop"

$scripts = Get-ChildItem -Path "$PSScriptRoot\..\scripts", "$PSScriptRoot\..\dev-scripts" -Filter "*.ps1" -Recurse | 
    Select-Object @{Name='FullName'; Expression={$_.FullName}}, @{Name='Name'; Expression={$_.Name}}

Describe "Script Syntax Checks" {
    It "<Name> should have valid PowerShell syntax" -TestCases $scripts {
        param($FullName, $Name)
        $content = Get-Content -Path $FullName -Raw
        $errors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)
        
        $errors | Should -BeNullOrEmpty
    }
}
