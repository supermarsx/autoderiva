Describe 'Performance tweaks (registry) behavior' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'
        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile
    }

    It 'Calls expected registry operations when enabled' {
        $calls = New-Object System.Collections.Generic.List[object]

        $Script:Test_SetRegistryDword = {
            param($Path, $Name, $Value)
            $calls.Add([PSCustomObject]@{ Op = 'SetDword'; Path = [string]$Path; Name = [string]$Name; Value = [int]$Value })
        }
        $Script:Test_RemoveRegistryValue = {
            param($Path, $Name)
            $calls.Add([PSCustomObject]@{ Op = 'RemoveValue'; Path = [string]$Path; Name = [string]$Name })
        }

        $Script:DryRun = $false
        $Config.DisableOneDriveStartup = $true
        $Config.HideTaskViewButton = $true
        $Config.DisableNewsAndInterestsAndWidgets = $true
        $Config.HideTaskbarSearch = $true

        Apply-PerformanceTweaks

        # OneDrive startup removal
        ($calls | Where-Object { $_.Op -eq 'RemoveValue' -and $_.Path -like 'HKCU:*Run' -and $_.Name -eq 'OneDrive' }).Count | Should -Be 1
        ($calls | Where-Object { $_.Op -eq 'RemoveValue' -and $_.Path -like 'HKLM:*Run' -and $_.Name -eq 'OneDrive' }).Count | Should -Be 1

        # Task View
        ($calls | Where-Object { $_.Op -eq 'SetDword' -and $_.Path -like 'HKCU:*Explorer*Advanced' -and $_.Name -eq 'ShowTaskViewButton' -and $_.Value -eq 0 }).Count | Should -Be 1

        # Search
        ($calls | Where-Object { $_.Op -eq 'SetDword' -and $_.Path -like 'HKCU:*CurrentVersion*Search' -and $_.Name -eq 'SearchboxTaskbarMode' -and $_.Value -eq 0 }).Count | Should -Be 1

        # Feeds policy + setting
        ($calls | Where-Object { $_.Op -eq 'SetDword' -and $_.Path -like 'HKCU:*CurrentVersion*Feeds' -and $_.Name -eq 'ShellFeedsTaskbarViewMode' -and $_.Value -eq 2 }).Count | Should -Be 1
        ($calls | Where-Object { $_.Op -eq 'SetDword' -and $_.Path -like 'HKLM:*Policies*Windows Feeds' -and $_.Name -eq 'EnableFeeds' -and $_.Value -eq 0 }).Count | Should -Be 1

        # Widgets
        ($calls | Where-Object { $_.Op -eq 'SetDword' -and $_.Path -like 'HKCU:*Explorer*Advanced' -and $_.Name -eq 'TaskbarDa' -and $_.Value -eq 0 }).Count | Should -Be 1
    }

    It 'Does not call registry operations when all tweaks disabled' {
        $calls = New-Object System.Collections.Generic.List[object]

        $Script:Test_SetRegistryDword = {
            param($Path, $Name, $Value)
            $calls.Add([PSCustomObject]@{ Op = 'SetDword'; Path = [string]$Path; Name = [string]$Name; Value = [int]$Value })
        }
        $Script:Test_RemoveRegistryValue = {
            param($Path, $Name)
            $calls.Add([PSCustomObject]@{ Op = 'RemoveValue'; Path = [string]$Path; Name = [string]$Name })
        }

        $Script:DryRun = $false
        $Config.DisableOneDriveStartup = $false
        $Config.HideTaskViewButton = $false
        $Config.DisableNewsAndInterestsAndWidgets = $false
        $Config.HideTaskbarSearch = $false

        Apply-PerformanceTweaks

        $calls.Count | Should -Be 0
    }
}
