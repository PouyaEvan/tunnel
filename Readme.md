# Gost & SNI Tunnel Manager Pro v4.0

A powerful, all-in-one tunnel management script for Iran and Kharej servers. This tool uses **Gost** for creating secure TLS tunnels with SNI spoofing to bypass network restrictions.

## Features
- **Interactive UI**: Navigate menus easily using arrow keys (↑/↓) and Enter (⏎).
- **Pre-compiled Binary**: Includes Gost v2.12.0 for Linux AMD64 (Ubuntu 22.04+)—no building required!
- **Unified Manager**: One script to rule them all (supports both Iran and Kharej modes).
- **SNI Spoofing**: Built-in list of Iranian and popular domains (like `tgjo.org`, `tgju.org`, `snapp.ir`, etc.) to hide your traffic.
- **Systemd Integration**: Easily install tunnels as background services that restart automatically.
- **Automated SSL**: Generates self-signed certificates for the Kharej (TLS receiver) side.

## Quick Start

### 1. Prerequisites
The script requires `openssl` for certificate generation and `sudo` for service management.
```bash
sudo apt update && sudo apt install -y openssl
```

### 2. Run the Manager
```bash
./run.sh
```

### 3. Usage Steps

#### **On Kharej Server (External)**
1. Run `./run.sh`.
2. Select **"Setup Kharej Server (TLS Receiver)"**.
   - This will listen on port `443`.
   - It will ask to generate certificates in `/root` (say `y`).
   - You can choose to install it as a service.

#### **On Iran Server (Internal)**
1. Run `./run.sh`.
2. Select **"Setup Iran Server (Tunnel to Kharej)"**.
   - Enter your **Kharej Server IP**.
   - Select a decoy SNI (e.g., `tgjo.org`).
   - The tunnel will listen on port `10000`.
   - You can choose to install it as a service.

## Menu Options
- **Setup Iran Server**: Configures the client-side tunnel with SNI spoofing.
- **Setup Kharej Server**: Configures the server-side TLS listener.
- **Install Gost to System**: Copies the included binary to `/usr/local/bin/gost`.
- **Manage Service**: Check status, view logs, or stop/restart the background service.
- **Uninstall Everything**: Cleanly removes the systemd service and logs.

## Security
- The Kharej server uses TLS encryption with cert/key pairs.
- The Iran server uses SNI (Server Name Indication) spoofing to make the connection look like a request to a legitimate Iranian website.

## Credits
- Binary: [Gost](https://github.com/ginuerzh/gost) v2.12.0 by ginuerzh.
