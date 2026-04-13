# 📝 Future Updates (TODO)

## ✅ Completed Features
- [x] **Systemd Integration**: Automated service generation and management.
- [x] **Multi-Port Support**: Simultaneous listening on multiple ports with mapping.

## 🔧 Core Enhancements
- [x] **SNI Auto-Rotation**: Periodically switch between the "best" SNIs automatically.
- [x] **UDP Support**: Native UDP and UDP-over-TCP (Encapsulated) support.

## 🛡️ Security
- [x] **Authentication**: Pre-shared key (PSK) between Iran and Kharej servers.
- [x] **Traffic Obfuscation**: Rolling XOR stream cipher for DPI evasion.

## 📊 Monitoring & UI
- [ ] **Real-time Monitoring**: Integrate a lightweight TUI for live traffic stats and latency graphs.
- [ ] **Web Dashboard**: Optional web-based management interface.
- [ ] **External Alerts**: Support for Telegram/Discord webhooks.

## ⚙️ DevOps & Deployment
- [ ] **One-Click Installer**: A single bash command to install all dependencies and start the tunnel.

---
**Note for Developer**: Always ask the user if they want to enable optional features (Auth, UDP, Obfuscation, etc.) during configuration. These must not be required by default.
