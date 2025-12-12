$ErrorActionPreference = "Stop"

Describe "Script Syntax Checks" {
    $scripts = Get-ChildItem -Path "$PSScriptRoot\..\scripts", "$PSScriptRoot\..\dev-scripts" -Filter "*.ps1" -Recurse

    foreach ($script in $scripts) {
        It "$($script.Name) should have valid PowerShell syntax" {
            $content = Get-Content -Path $script.FullName -Raw
            $errors = $null
            $tokens = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)
            
            $errors | Should -BeNullOrEmpty
        }
    }
}
