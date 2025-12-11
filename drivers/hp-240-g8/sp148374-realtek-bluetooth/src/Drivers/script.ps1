param($inst_para)

#write-host "input parameter: $inst_para"

$install_path="C:\Program Files (x86)\REALTEK\Realtek Bluetooth"

if ($inst_para -eq "inst")
{
    #write-host "install driver"
    $TRUE_FALSE=(Test-Path $install_path)
    if($TRUE_FALSE -eq "True")
    {
        Remove-Item -Recurse -Force $install_path
        #md $install_path
    }

    md $install_path
    #New-Item $install_path -type Directory

    Start-Sleep -s 1

    #Write-Host $install_path\*.inf
    Write-Host $PSScriptRoot
    Copy-Item  $PSScriptRoot\x64\0 -Destination $install_path\0 -Recurse
	Copy-Item  $PSScriptRoot\x64\1 -Destination $install_path\1 -Recurse
    Copy-Item  $PSScriptRoot\devcon.exe $install_path
    Copy-Item  $PSScriptRoot\script.ps1 $install_path
    Copy-Item  $PSScriptRoot\UninstallDriver.cmd $install_path
    pnputil /add-driver "$install_path\0\Rtkfilter.inf" /install >>$install_path\pnp.log
	pnputil /add-driver "$install_path\1\Rtkfilter.inf" /install >>$install_path\pnp.log
}
elseif ($inst_para -eq "unin")
{
    #write-host "uninstall driver"

    $exepath=Join-Path $PSScriptRoot "devcon.exe"
    #Write-Host $exepath
    $RTKBTHWID=gwmi win32_PnPSignedDriver | where {$_.Manufacturer -like "*Realtek*" -and $_.DeviceClass  -eq "Bluetooth"}
    Write-Host $RTKBTHWID
    $delpara="remove"+ " " + $RTKBTHWID.HardWareID
    Write-Host $delpara

    $Filters=Get-WindowsDriver -Online | where {$_.ProviderName -like "*Realtek*" -and $_.ClassName -eq "Bluetooth"} 
    foreach ($filter in $Filters)
    {
        Write-Host "Deleting filter driver..."
        echo $filter
        pnputil /delete-driver $filter.Driver /force
    }    

    Start-Process $exepath -ArgumentList $delpara
    Start-Sleep -s 3
    Start-Process $exepath -ArgumentList "rescan"
       

    Remove-Item -Recurse -Force $install_path
}

else
{
    write-host "unkown para"
}
