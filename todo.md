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
- [x] **Real-time Monitoring**: Integrated TUI for live traffic stats and connection testing.

## ⚙️ DevOps & Deployment
- [x] **One-Click Installer**: Portable standalone script generator for SFTP-ready deployment.

---
**Note for Developer**: Always ask the user if they want to enable optional features (Auth, UDP, Obfuscation, etc.) during configuration. These must not be required by default.
