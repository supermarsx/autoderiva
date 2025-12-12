Describe "Script Validation" {
    $repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
    $scriptsPath = Join-Path $repoRoot "scripts"
    $scripts = Get-ChildItem -Path $scriptsPath -Filter "*.ps1"

    It "Scripts directory should exist" {
        $scriptsPath | Should -Exist
    }

    Context "Syntax Checks" {
        foreach ($script in $scripts) {
            It "$($script.Name) should have valid syntax" {
                $content = Get-Content $script.FullName -Raw
                $errors = $null
                [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors) | Out-Null
                $errors.Count | Should -Be 0
            }
        }
    }

    Context "PSScriptAnalyzer Rules" {
        foreach ($script in $scripts) {
            It "$($script.Name) should pass PSScriptAnalyzer Error rules" {
                if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
                    $results = Invoke-ScriptAnalyzer -Path $script.FullName -Severity Error
                    $results.Count | Should -Be 0
                } else {
                    Set-ItResult -Pending -Because "PSScriptAnalyzer module is not installed"
                }
            }
        }
    }
}
