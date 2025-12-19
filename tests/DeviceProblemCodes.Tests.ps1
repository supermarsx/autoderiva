Describe 'Problem-code device filtering' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\.." ).Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'

        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile

        # Mocks must be defined at Describe scope so the dot-sourced functions
        # (defined outside individual It blocks) can see them.
        $script:LastCimFilter = $null
        $script:CimReturn = @()
        $script:CimCallCount = 0

        Mock Get-CimInstance {
            [CmdletBinding()]
            param(
                [string]$ClassName,
                [string]$Filter
            )

            $script:CimCallCount++
            $script:LastCimFilter = [string]$Filter
            return $script:CimReturn
        }

        # If CIM works (even with 0 matches), we should not hit the per-device property scan path.
        Mock Get-PnpDeviceProperty {
            [CmdletBinding()]
            param()
            throw 'Should not be called when CIM query is available.'
        }
    }

    BeforeEach {
        $script:LastCimFilter = $null
        $script:CimReturn = @()
        $script:CimCallCount = 0
    }

    It 'Uses a single CIM query with OR filter for multiple codes' {
        $devices = @(
            [PSCustomObject]@{ InstanceId = 'DEV_A' },
            [PSCustomObject]@{ InstanceId = 'DEV_B' }
        )

        $script:CimReturn = @(
            [PSCustomObject]@{ PNPDeviceID = 'DEV_B' },
            [PSCustomObject]@{ PNPDeviceID = 'DEV_X' }
        )

        $result = Get-MissingDriverDevice -SystemDevices $devices -ProblemCodes @(28, 1)

        $script:LastCimFilter | Should -Be 'ConfigManagerErrorCode=1 OR ConfigManagerErrorCode=28'
        $script:CimCallCount | Should -Be 1
        $result.Count | Should -Be 1
        $result[0].InstanceId | Should -Be 'DEV_B'
    }

    It 'Returns empty array when CIM returns no results (no fallback scan)' {
        $devices = @(
            [PSCustomObject]@{ InstanceId = 'DEV_A' },
            [PSCustomObject]@{ InstanceId = 'DEV_B' }
        )

        $script:CimReturn = @()

        $result = Get-MissingDriverDevice -SystemDevices $devices -ProblemCodes @(28)
        $script:LastCimFilter | Should -Be 'ConfigManagerErrorCode=28'
        $script:CimCallCount | Should -Be 1
        $result.Count | Should -Be 0
    }
}
