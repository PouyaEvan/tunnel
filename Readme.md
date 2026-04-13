# Python SNI Spoof Tunnel Pro

A professional SNI spoofing tunnel designed to bypass network filtering by masking traffic with fake Server Name Indication (SNI) headers.

## 🚀 Features
- **Multi-SNI Support**: Choose from a curated list of high-reputation domains (Vercel, Next.js, Let's Encrypt, etc.).
- **Latency Testing**: Automatically tests and suggests the best SNI for your current server environment.
- **Dual Mode Operations**:
  - **IRAN Mode (Sender)**: Spoofs outgoing packets with a fake SNI.
  - **KHAREJ Mode (Receiver)**: Acts as a transparent bridge to accept any incoming spoofed traffic.
- **Professional CLI**: Color-coded output, automatic environment checks, and integrated logging.
- **Transparent Forwarding**: Supports non-TLS traffic (SSH, HTTP) without modification.

## 🛠️ Installation
The management script will automatically check for and attempt to install Python 3 if it's missing.

```bash
git clone <repository-url>
cd tunnel
chmod +x run.sh
```

## 📖 How to Use

### 1. Kharej (Receiver) Server Setup
First, run the script on your foreign server to prepare it for incoming traffic.
```bash
./run.sh
```
- Select **Option 2 (KHAREJ Mode)**.
- Set the local port (usually **443**).
- Set the target IP/Port (where your proxy service like V2Ray or Shadowsocks is listening, e.g., `127.0.0.1:1080`).

### 2. Iran (Sender) Server Setup
Run the script on your Iran server to start forwarding traffic.
```bash
./run.sh
```
- Select **Option 1 (IRAN Mode)**.
- Enter your **Kharej Server IP**.
- The script will test latencies for several SNIs and suggest the **"Best"** one.
- Select the suggested SNI or enter a custom one.

## 📊 Verification & Logs
You can monitor the tunnel's performance directly through the CLI:
- Select **Option 3 (View Logs)** in the main menu to see the last 20 lines of traffic logs.
- Full logs are stored in `logs/tunnel.log`.

## ⚠️ Important Notes
- **SSL Certificates**: Clients (browsers) will show a certificate mismatch error because the server provides the real certificate for the original domain while the SNI is spoofed. This is expected.
- **Root Privileges**: To bind to ports below 1024 (like 443), you may need to run the script with `sudo`.
