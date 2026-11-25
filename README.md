# Reverse SSH Tunnel Kit

Reach the **ORIGIN** PC WSL from this **RELAY** PC.

## Roles
- **ORIGIN**: the machine you work on. It cannot accept inbound, so it dials out.
- **RELAY**: this machine. You sit here and connect through it.

## Kit (this folder)
| File | Runs on | Purpose |
|------|---------|---------|
| `relay.cmd` | RELAY (this PC) | one double click |
| `origin-tunnel.sh` | ORIGIN WSL | self-setup helper, copy over if you can |
| `relay.conf` | auto | saved origin IP and user |
| `README.md` | this file | |

## Use (in order)
1. **RELAY**: double click `relay.cmd`, accept UAC, enter the ORIGIN PC IP and WSL user. Find the IP on the origin:
   ```powershell
   (Get-NetIPAddress -InterfaceAlias Wi-Fi -AddressFamily IPv4).IPAddress
   ```
2. **ORIGIN**: open its Ubuntu (WSL) and do one of:
   - Script present on the origin:
     ```bash
     ~/revtun/origin-tunnel.sh on
     ```
   - No script on the origin: paste the runbook that `relay.cmd` prints under **No script on the origin?**. It installs sshd, makes a key, registers it on the relay (relay password once), and opens the tunnel.
3. **Connect** from the relay (the `relay.cmd` window with `c` then Enter, or any terminal):
   ```bash
   ssh -p 2222 <origin-wsl-user>@127.0.0.1
   ```
4. **Stop**: press Enter in the `relay.cmd` window. On the origin:
   ```bash
   ~/revtun/origin-tunnel.sh off
   ```
   (or kill the `ssh -R` process if you used the paste runbook).

## Reuse for another pair
Nothing to edit. `relay.cmd` asks for the origin IP and user each run and saves them in `relay.conf`. `origin-tunnel.sh` asks for this relay IP and user on first run and saves `revtun.conf` beside it. The runbook that `relay.cmd` prints is already filled with this relay IP and user.

## Notes
- The relay SSH server runs only while `relay.cmd` is open, and inbound is limited to the origin IP you entered.
- The origin must be powered on with WSL running.
- Work you do runs on the origin and is logged there.
