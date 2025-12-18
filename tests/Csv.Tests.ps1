Describe 'Exports CSV lint' {
    It 'passes Csv-Check.ps1 (All)' {
        { & "$PSScriptRoot\..\dev-scripts\Csv-Check.ps1" -Mode All } | Should -Not -Throw
    }
}
