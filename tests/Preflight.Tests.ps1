Describe 'Preflight checks behavior' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'

        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile
    }

    It 'Includes Cuco URL check when enabled (no real network)' {
        $calls = New-Object System.Collections.Generic.List[object]

        $Script:Test_PreflightAllowInTest = $true
        $Script:Test_InvokePreflightHttpCheck = {
            param($Name, $Url, $Method, $TimeoutMs, $AllowGetFallback)
            $calls.Add([PSCustomObject]@{ Name = [string]$Name; Url = [string]$Url; Method = [string]$Method; TimeoutMs = [int]$TimeoutMs; AllowGetFallback = [bool]$AllowGetFallback })
        }
        $Script:Test_InvokePreflightPing = {
            param($Target, $TimeoutMs)
            # Return a PingReply-like object
            return [PSCustomObject]@{ Status = [System.Net.NetworkInformation.IPStatus]::Success; RoundtripTime = 10 }
        }

        $Config.PreflightEnabled = $true
        $Config.PreflightCheckNetwork = $true
        $Config.PreflightCheckCucoSite = $true
        $Config.PreflightCucoUrl = 'https://cuco.inforlandia.pt/'

        Test-PreFlight

        ($calls | Where-Object { $_.Name -eq 'Cuco' -and $_.Url -eq 'https://cuco.inforlandia.pt/' -and $_.Method -eq 'GET' }).Count | Should -Be 1
    }

    It 'Uses GET for GitHub and allows BaseUrl GET fallback' {
        $calls = New-Object System.Collections.Generic.List[object]

        $Script:Test_PreflightAllowInTest = $true
        $Script:Test_InvokePreflightHttpCheck = {
            param($Name, $Url, $Method, $TimeoutMs, $AllowGetFallback)
            $calls.Add([PSCustomObject]@{ Name = [string]$Name; Url = [string]$Url; Method = [string]$Method; AllowGetFallback = [bool]$AllowGetFallback })
        }
        $Script:Test_InvokePreflightPing = { param($Target, $TimeoutMs) return [PSCustomObject]@{ Status = [System.Net.NetworkInformation.IPStatus]::Success; RoundtripTime = 10 } }

        $Config.PreflightEnabled = $true
        $Config.PreflightCheckNetwork = $true
        $Config.PreflightCheckGitHub = $true
        $Config.PreflightCheckBaseUrl = $true
        $Config.BaseUrl = 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/'

        Test-PreFlight

        ($calls | Where-Object { $_.Name -eq 'GitHub' -and $_.Url -eq 'https://github.com/' -and $_.Method -eq 'GET' }).Count | Should -Be 1
        ($calls | Where-Object { $_.Name -eq 'GitHub (BaseUrl)' -and $_.Method -eq 'HEAD' -and $_.AllowGetFallback -eq $true }).Count | Should -Be 1
    }

    It 'Exits when Internet (DNS) check fails and policy is Exit' {
        $Script:Test_PreflightAllowInTest = $true
        $Script:Test_InvokePreflightDnsCheck = { param($HostName) return $false }
        $Script:Test_InvokePreflightHttpCheck = { param($Name, $Url, $Method, $TimeoutMs, $AllowGetFallback) }
        $Script:Test_InvokePreflightPing = { param($Target, $TimeoutMs) return [PSCustomObject]@{ Status = [System.Net.NetworkInformation.IPStatus]::Success; RoundtripTime = 10 } }

        $Config.PreflightEnabled = $true
        $Config.PreflightCheckNetwork = $true
        $Config.PreflightInternetFailurePolicy = 'Exit'

        { Test-PreFlight } | Should -Throw

        $Script:Test_InvokePreflightDnsCheck = $null
    }
}
