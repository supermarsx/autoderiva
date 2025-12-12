$ErrorActionPreference = "Stop"

Describe "PSScriptAnalyzer Rules" {
    $scripts = Get-ChildItem -Path "$PSScriptRoot\..\scripts", "$PSScriptRoot\..\dev-scripts" -Filter "*.ps1" -Recurse

    foreach ($script in $scripts) {
        It "$($script.Name) should pass PSScriptAnalyzer checks" {
            # We exclude some rules that might be too strict for this project context if needed
            # For now, we check for Errors and Warnings
            $results = Invoke-ScriptAnalyzer -Path $script.FullName -Severity Error,Warning
            
            # Filter out specific suppressions if necessary
            # $results = $results | Where-Object { $_.RuleName -ne "PSAvoidUsingWriteHost" } 

            $results | Should -BeNullOrEmpty
        }
    }
}
