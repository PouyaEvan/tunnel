#!/bin/bash

# ==============================================================================
# SNI Spoofing Tunnel Manager Smart Pro v2.6
# ==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Config
LOG_DIR="logs"
TUNNEL_SCRIPT="$(pwd)/sni_tunnel/tunnel.py"
SERVICE_NAME="sni-tunnel"
SNI_LIST=("varzesh3.com" "ikco.ir" "vercel.com" "nextjs.com" "letsencrypt.org" "google.com" "cloudflare.com" "github.com")

log() {
    local level=$1
    local msg=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${msg}" | tee -a "${LOG_DIR}/tunnel.log"
}

check_service_status() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}RUNNING${NC}"
    elif systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo -e "${YELLOW}STOPPED (Enabled)${NC}"
    else
        echo -e "${RED}NOT INSTALLED${NC}"
    fi
}

get_installed_mode() {
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        if grep -q "IRAN" "/etc/systemd/system/${SERVICE_NAME}.service"; then
            echo -e "${CYAN}IRAN Mode${NC}"
        elif grep -q "KHAREJ" "/etc/systemd/system/${SERVICE_NAME}.service"; then
            echo -e "${CYAN}KHAREJ Mode${NC}"
        else echo -e "Unknown"; fi
    else echo -e "None"; fi
}

check_latency() {
    local host=$1
    local start=$(date +%s%N)
    if curl -s -o /dev/null -m 2 "$host"; then
        local end=$(date +%s%N)
        local diff=$(( (end - start) / 1000000 ))
        echo "$diff"
    else echo "999"; fi
}

generate_portable() {
    echo -e "${BLUE}Generating Portable One-Click Installer...${NC}"
    local DEPLOY_FILE="deploy_tunnel.sh"
    local PY_B64=$(base64 -w 0 "$TUNNEL_SCRIPT")
    
    cat > "$DEPLOY_FILE" <<EOF
#!/bin/bash
# Standalone SNI Tunnel Installer
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
echo -e "\${YELLOW}>>> Extracting Tunnel Logic...\${NC}"
mkdir -p sni_tunnel logs
echo "$PY_B64" | base64 -d > sni_tunnel/tunnel.py
if ! command -v python3 &> /dev/null; then
    echo -e "\${YELLOW}>>> Installing Python 3...\${NC}"
    sudo apt update && sudo apt install -y python3
fi
echo -e "\${GREEN}>>> Extraction Complete.\${NC}"
echo -e "You can now run 'bash run.sh' or use this script to reinstall."
# Re-generate a basic run.sh for them
EOF
    # Append the current run.sh logic to the deploy file so it's fully functional
    cat "$0" >> "$DEPLOY_FILE"
    chmod +x "$DEPLOY_FILE"
    echo -e "${GREEN}[SUCCESS] Portable installer created: $DEPLOY_FILE${NC}"
    echo -e "Upload this single file via SFTP to your Iran server and run it."
    read -p "Press enter to return..."
}

test_connection() {
    echo -e "\n${BLUE}--- Connection Test Tool ---${NC}"
    read -p "Enter Target IP: " TEST_IP
    read -p "Enter Target Port: " TEST_PORT
    echo -e "${CYAN}Testing TCP connection to \$TEST_IP:\$TEST_PORT...${NC}"
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/\$TEST_IP/\$TEST_PORT" 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS] Target is reachable.${NC}"
    else echo -e "${RED}[FAILED] Target is unreachable or port is closed.${NC}"; fi
    read -p "Press enter to return..."
}

show_sni_menu() {
    echo -e "\n${BLUE}--- Choose Best SNI ---${NC}"
    echo -e "${CYAN}Testing latencies...${NC}"
    local best_ms=999; local best_sni=""; local results=()
    for sni in "\${SNI_LIST[@]}"; do
        local ms=\$(check_latency "\$sni")
        results+=("\$sni|\$ms")
        if (( ms < best_ms )); then best_ms=\$ms; best_sni=\$sni; fi
    done
    for res in "\${results[@]}"; do
        local s=\${res%|*}; local m=\${res#*|}
        [[ "\$s" == "\$best_sni" ]] && echo -e " - \$s: \${GREEN}\${m}ms\${NC} (Best)" || echo -e " - \$s: \${YELLOW}\${m}ms\${NC}"
    done
    echo -e "\n0) Custom SNI\nR) Auto-Rotation (Uses all SNIs)"
    for i in "\${!SNI_LIST[@]}"; do echo -e "\$((i+1))) \${SNI_LIST[\$i]}"; done
    read -p "Select SNI: " SNI_CHOICE
    ROTATION_INTERVAL=0
    if [[ "\$SNI_CHOICE" == "R" || "\$SNI_CHOICE" == "r" ]]; then
        FINAL_SNI=\$(IFS=,; echo "\${SNI_LIST[*]}")
        read -p "Enter Rotation Interval [300]: " ROTATION_INTERVAL
        ROTATION_INTERVAL=\${ROTATION_INTERVAL:-300}
    elif [[ "\$SNI_CHOICE" == "0" ]]; then read -p "Enter Custom SNI: " FINAL_SNI
    elif [[ "\$SNI_CHOICE" -ge 1 && "\$SNI_CHOICE" -le "\${#SNI_LIST[@]}" ]]; then
        FINAL_SNI="\${SNI_LIST[\$((SNI_CHOICE-1))]}"
    else FINAL_SNI="\$best_sni"; fi
}

ask_auth() {
    read -p "Enable PSK Authentication? (y/n): " ENABLE_AUTH
    if [[ "\$ENABLE_AUTH" == "y" ]]; then
        read -p "Enter PSK [random]: " PSK
        [[ -z "\$PSK" ]] && PSK=\$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        echo -e "\${YELLOW}PSK: \${GREEN}\$PSK\${NC}"
    else PSK=""; fi
}

ask_udp() {
    echo -e "\n\${BLUE}--- UDP Support Options ---\${NC}"
    echo -e "1) None\n2) Native UDP\n3) UDP-over-TCP"
    read -p "Select UDP Mode [1-3]: " UDP_CHOICE
    case \$UDP_CHOICE in 2) UDP_MODE="native" ;; 3) UDP_MODE="tcp" ;; *) UDP_MODE="none" ;; esac
}

ask_obfs() {
    read -p "Enable Traffic Obfuscation? (y/n): " ENABLE_OBFS
    if [[ "\$ENABLE_OBFS" == "y" ]]; then
        read -p "Enter Obfs Key [random]: " OBFS_KEY
        [[ -z "\$OBFS_KEY" ]] && OBFS_KEY=\$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        echo -e "\${YELLOW}Obfs Key: \${GREEN}\$OBFS_KEY\${NC}"
    else OBFS_KEY=""; fi
}

install_systemd() {
    local mode=\$1; local ports=\$2; local rhost=\$3; local sni=\$4; local extra_args=\$5
    echo -e "\${BLUE}Installing Systemd Service...\${NC}"
    local CMD="python3 \$TUNNEL_SCRIPT --rhost \$rhost --ports \$ports --sni \$sni --show-stats \$extra_args"
    [[ -n "\$ROTATION_INTERVAL" && "\$ROTATION_INTERVAL" -gt 0 ]] && CMD="\$CMD --rotate \$ROTATION_INTERVAL"
    [[ -n "\$PSK" ]] && CMD="\$CMD --psk \$PSK"
    [[ -n "\$OBFS_KEY" ]] && CMD="\$CMD --obfs-key \$OBFS_KEY"
    [[ "\$UDP_MODE" != "none" ]] && CMD="\$CMD --udp-mode \$UDP_MODE"
    sudo bash -c "cat > /etc/systemd/system/\${SERVICE_NAME}.service <<EOF
[Unit]
Description=SNI Tunnel (\$mode)
After=network.target
[Service]
Type=simple
User=\$(whoami)
WorkingDirectory=\$(pwd)
ExecStart=\$CMD
Restart=always
RestartSec=5
StandardOutput=append:\$(pwd)/logs/tunnel.log
StandardError=append:\$(pwd)/logs/tunnel.log
[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl daemon-reload; sudo systemctl enable \${SERVICE_NAME}; sudo systemctl restart \${SERVICE_NAME}
    echo -e "\${GREEN}Service installed and started!\${NC}"
    read -p "Press enter to return..."
}

run_iran() {
    echo -e "\n\${BLUE}--- Iran Server Configuration ---\${NC}"
    read -p "Enter Kharej Server IP: " KHAREJ_IP
    read -p "Enter Ports [443]: " PORTS; PORTS=\${PORTS:-443}
    show_sni_menu; ask_auth; ask_udp; ask_obfs
    read -p "Install as Systemd Service? (y/n): " IS_SYSTEMD
    if [[ "\$IS_SYSTEMD" == "y" ]]; then install_systemd "IRAN" "\$PORTS" "\$KHAREJ_IP" "\$FINAL_SNI" ""
    else
        CMD="python3 \$TUNNEL_SCRIPT --rhost \$KHAREJ_IP --ports \$PORTS --sni \$FINAL_SNI --rotate \$ROTATION_INTERVAL --udp-mode \$UDP_MODE --show-stats"
        [[ -n "\$PSK" ]] && CMD="\$CMD --psk \$PSK"
        [[ -n "\$OBFS_KEY" ]] && CMD="\$CMD --obfs-key \$OBFS_KEY"
        \$CMD 2>&1 | tee -a "\${LOG_DIR}/tunnel.log"; fi
}

run_kharej() {
    echo -e "\n\${BLUE}--- Kharej Server Configuration ---\${NC}"
    read -p "Enter Ports [443]: " PORTS; PORTS=\${PORTS:-443}
    read -p "Enter Target IP [127.0.0.1]: " TIP; TIP=\${TIP:-127.0.0.1}
    read -p "Enter Target Port [1080]: " TPORT; TPORT=\${TPORT:-1080}
    ask_auth; ask_udp; ask_obfs
    local port_map=""; IFS=',' read -ra ADDR <<< "\$PORTS"
    for i in "\${ADDR[@]}"; do port_map+="\${i}:\${TPORT},"; done; port_map=\${port_map%,}
    read -p "Install as Systemd Service? (y/n): " IS_SYSTEMD
    if [[ "\$IS_SYSTEMD" == "y" ]]; then install_systemd "KHAREJ" "\$port_map" "\$TIP" "none" "--no-spoof"
    else
        CMD="python3 \$TUNNEL_SCRIPT --rhost \$TIP --ports \$port_map --no-spoof --udp-mode \$UDP_MODE --show-stats"
        [[ -n "\$PSK" ]] && CMD="\$CMD --psk \$PSK"
        [[ -n "\$OBFS_KEY" ]] && CMD="\$CMD --obfs-key \$OBFS_KEY"
        \$CMD 2>&1 | tee -a "\${LOG_DIR}/tunnel.log"; fi
}

uninstall_service() {
    echo -e "\${RED}Uninstalling Service...\${NC}"
    sudo systemctl stop "\$SERVICE_NAME" 2>/dev/null; sudo systemctl disable "\$SERVICE_NAME" 2>/dev/null
    sudo rm "/etc/systemd/system/\${SERVICE_NAME}.service" 2>/dev/null; sudo systemctl daemon-reload
    echo -e "\${GREEN}Service uninstalled successfully.\${NC}"
    read -p "Press enter to return..."
}

setup_env() {
    mkdir -p "\$LOG_DIR"
    if ! command -v python3 &> /dev/null; then
        sudo apt update && sudo apt install -y python3
    fi
}

setup_env
while true; do
    STATUS=\$(check_service_status); MODE=\$(get_installed_mode)
    clear
    echo -e "\${CYAN}================================================\${NC}"
    echo -e "\${GREEN}      SNI Spoofing Tunnel Smart Manager v2.6    \${NC}"
    echo -e "\${CYAN}================================================\${NC}"
    echo -e " Status: \$STATUS"
    echo -e " Mode:   \$MODE"
    echo -e "\${CYAN}------------------------------------------------\${NC}"
    if [[ "\$MODE" == "None" ]]; then
        echo -e "1) \${YELLOW}Install IRAN Mode\${NC}"
        echo -e "2) \${YELLOW}Install KHAREJ Mode\${NC}"
    else
        echo -e "1) \${MAGENTA}Reinstall/Change to IRAN\${NC}"
        echo -e "2) \${MAGENTA}Reinstall/Change to KHAREJ\${NC}"
        echo -e "U) \${RED}Uninstall Current Service\${NC}"
    fi
    echo -e "T) \${CYAN}Test Remote Connection\${NC}"
    echo -e "M) \${CYAN}Manage Service (Stats/Logs/Restart)\${NC}"
    echo -e "P) \${BLUE}Generate Portable Installer (SFTP Ready)\${NC}"
    echo -e "X) \${RED}Exit\${NC}"
    echo -e "\${CYAN}================================================\${NC}"
    read -p "Select Choice: " CHOICE
    case \$CHOICE in
        1) run_iran ;;
        2) run_kharej ;;
        u|U) uninstall_service ;;
        t|T) test_connection ;;
        p|P) generate_portable ;;
        m|M) 
            echo -e "\n1) Status 2) Restart 3) Stop 4) Live Stats"
            read -p "Option: " S_OPT
            case \$S_OPT in
                1) sudo systemctl status "\$SERVICE_NAME" ;;
                2) sudo systemctl restart "\$SERVICE_NAME" ;;
                3) sudo systemctl stop "\$SERVICE_NAME" ;;
                4) tail -f "\${LOG_DIR}/tunnel.log" | grep "STATS" ;;
            esac ;;
        x|X) exit 0 ;;
        *) echo -e "\${RED}Invalid.\${NC}"; sleep 1 ;;
    esac
done
