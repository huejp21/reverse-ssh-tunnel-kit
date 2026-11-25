@echo off & setlocal
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
set "SELF=%~f0"
set "HEREDIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=[IO.File]::ReadAllText($env:SELF);$i=$f.IndexOf([char]35+'PSSTART');Invoke-Expression $f.Substring($i+8)"
exit /b
#PSSTART
$ErrorActionPreference = 'Stop'
$dir = $env:HEREDIR
$ruser = $env:USERNAME
$fwdPort = 2222
$rule = 'RevTunnel-OnDemand'
$conf = Join-Path $dir 'relay.conf'
$defIp = '192.168.1.22'
$defUser = 'huejpark'
if (Test-Path $conf) {
  Get-Content $conf | ForEach-Object {
    if ($_ -match '^\s*ORIGIN_IP\s*=\s*(.+)$') { $defIp = $matches[1].Trim() }
    elseif ($_ -match '^\s*ORIGIN_USER\s*=\s*(.+)$') { $defUser = $matches[1].Trim() }
  }
}
Write-Host ''
Write-Host 'This machine is the RELAY. The ORIGIN dials in and you connect through it.' -ForegroundColor DarkGray
Write-Host 'Find the ORIGIN PC Wi-Fi IPv4 by running THIS on the origin PC:' -ForegroundColor Cyan
Write-Host '  (Get-NetIPAddress -InterfaceAlias Wi-Fi -AddressFamily IPv4).IPAddress' -ForegroundColor Cyan
Write-Host ''
$entry = Read-Host ('Origin PC IP [' + $defIp + ']')
if (-not $entry) { $entry = $defIp }
$ip = ([System.Net.IPAddress]::Parse($entry)).ToString()
$ue = Read-Host ('Origin WSL user [' + $defUser + ']')
if (-not $ue) { $ue = $defUser }
$originUser = $ue
Set-Content -Path $conf -Value ("ORIGIN_IP=$ip`r`nORIGIN_USER=$originUser") -Encoding ascii
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
  Write-Host 'Installing OpenSSH Server (one time)...' -ForegroundColor Yellow
  $r = Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
  if ($r.RestartNeeded) { Write-Host 'Restart Windows then run relay again.' -ForegroundColor Red; Read-Host 'Press Enter to close'; exit }
}
Set-Service sshd -StartupType Manual
if (Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue) {
  Set-NetFirewallRule -Name $rule -RemoteAddress $ip -Enabled True | Out-Null
} else {
  New-NetFirewallRule -Name $rule -DisplayName 'Reverse tunnel on-demand SSH' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -RemoteAddress $ip -Profile Any | Out-Null
}
Start-Service sshd
$relayip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4Address.IPAddress
Write-Host ''
Write-Host ('Relay SSH server ON. Inbound allowed only from origin PC ' + $ip) -ForegroundColor Green
Write-Host 'Access stays ON until you press Enter in THIS window.' -ForegroundColor Green
Write-Host ''
Write-Host '=== ON THE ORIGIN PC (Ubuntu) ===' -ForegroundColor Cyan
Write-Host ('This relay current IP: ' + $relayip) -ForegroundColor Cyan
Write-Host ''
Write-Host 'If the kit script is already on the origin, just:' -ForegroundColor Cyan
Write-Host '  ~/revtun/origin-tunnel.sh on' -ForegroundColor White
Write-Host ''
Write-Host 'No script on the origin? Paste these on the origin WSL, in order:' -ForegroundColor Cyan
Write-Host '  sudo systemctl enable --now ssh' -ForegroundColor White
Write-Host '  [ -f ~/.ssh/id_rtun ] || ssh-keygen -t ed25519 -f ~/.ssh/id_rtun -N ""' -ForegroundColor White
Write-Host ('  scp ~/.ssh/id_rtun.pub ' + $ruser + '@' + $relayip + ':id_rtun.pub') -ForegroundColor White
Write-Host ('  ssh ' + $ruser + '@' + $relayip + ' powershell -c "Get-Content $HOME\id_rtun.pub | Add-Content $Env:ProgramData\ssh\administrators_authorized_keys"') -ForegroundColor White
Write-Host ('  ssh -f -N -T -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -i ~/.ssh/id_rtun -R 127.0.0.1:' + $fwdPort + ':127.0.0.1:22 ' + $ruser + '@' + $relayip) -ForegroundColor White
Write-Host '  (admin relay uses the ProgramData key path above; non-admin relay: $HOME\.ssh\authorized_keys)' -ForegroundColor DarkGray
Write-Host ''
Write-Host '=== CONNECT (here, or from any other terminal, any number of times) ===' -ForegroundColor Cyan
Write-Host ('  ssh -p ' + $fwdPort + ' ' + $originUser + '@127.0.0.1') -ForegroundColor White
Write-Host ''
$e = [char]27
while ($true) {
  $go = Read-Host 'Press Enter to STOP access, or type c then Enter to connect here'
  if ($go -ne 'c') { break }
  ssh.exe -p $fwdPort ($originUser + '@127.0.0.1')
  [Console]::Write($e+'[?1000l'+$e+'[?1002l'+$e+'[?1003l'+$e+'[?1006l'+$e+'[?2004l'+$e+'[?1004l'+$e+'[?25h')
  Write-Host ''
  Write-Host 'Session closed. Access is still ON.' -ForegroundColor Yellow
}
Write-Host 'Tearing down relay SSH access...' -ForegroundColor Yellow
Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue | Disable-NetFirewallRule
Stop-Service sshd -ErrorAction SilentlyContinue
Write-Host 'Relay SSH access OFF.' -ForegroundColor Green
Read-Host 'Press Enter to close'
