$ErrorActionPreference = "Stop"

$scripts = Get-ChildItem -Path "$PSScriptRoot\..\scripts", "$PSScriptRoot\..\dev-scripts" -Filter "*.ps1" -Recurse | 
    Select-Object @{Name='FullName'; Expression={$_.FullName}}, @{Name='Name'; Expression={$_.Name}}

Describe "PSScriptAnalyzer Rules" {
    It "<Name> should pass PSScriptAnalyzer checks" -TestCases $scripts {
        param($FullName, $Name)
        # We exclude PSAvoidUsingWriteHost because this is a TUI application
        $results = Invoke-ScriptAnalyzer -Path $FullName -Severity Error,Warning -ExcludeRule PSAvoidUsingWriteHost
        
        $results | Should -BeNullOrEmpty
    }
}
