Describe "AutoDeriva Script Validation" {
    
    BeforeAll {
        $RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $ScriptsPath = Join-Path $RepoRoot "scripts"
        $DevScriptsPath = Join-Path $RepoRoot "dev-scripts"
    }

    # Gather all .ps1 files (Run during discovery for TestCases)
    $RepoRootDiscovery = (Resolve-Path "$PSScriptRoot\..").Path
    $ScriptsPathDiscovery = Join-Path $RepoRootDiscovery "scripts"
    $DevScriptsPathDiscovery = Join-Path $RepoRootDiscovery "dev-scripts"
    
    $AllScripts = Get-ChildItem -Path $ScriptsPathDiscovery, $DevScriptsPathDiscovery -Filter "*.ps1" -Recurse | 
        ForEach-Object { @{ FullName = $_.FullName; Name = $_.Name } }

    It "Scripts directory should exist" {
        $ScriptsPath | Should -Exist
    }

    Context "Syntax Validation" {
        It "<Name> should have valid PowerShell syntax" -TestCases $AllScripts {
            param($FullName, $Name)
            $content = Get-Content -Path $FullName -Raw
            $errors = $null
            $tokens = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)
            
            $errors | Should -BeNullOrEmpty
        }
    }

    Context "PSScriptAnalyzer Linting" {
        It "<Name> should pass PSScriptAnalyzer Error rules" -TestCases $AllScripts {
            param($FullName, $Name)
            if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
                # We only fail on Errors for now to be safe
                $results = Invoke-ScriptAnalyzer -Path $FullName -Severity Error
                $results | Should -BeNullOrEmpty
            } else {
                Set-ItResult -Pending -Because "PSScriptAnalyzer module is not installed"
            }
        }
    }
}
