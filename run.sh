#!/bin/bash

# ==============================================================================
# Gost & SNI Tunnel Manager Pro v4.0
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
SERVICE_NAME="gost-tunnel"
LOCAL_GOST="./bin/gost"
SYSTEM_GOST="/usr/local/bin/gost"
SNI_LIST=("tgju.org" "tgjo.org" "snapp.ir" "divar.ir" "ikco.ir" "varzesh3.com" "bazaar.ir")
CERT_DIR="/root"

# Helpers
mkdir -p "$LOG_DIR"

log() {
    local level=$1
    local msg=$2
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${level}] ${msg}" >> "${LOG_DIR}/manager.log"
}

# ------------------------------------------------------------------------------
# Menu Logic (Arrow Keys)
# ------------------------------------------------------------------------------
select_option() {
    local -a options=("$@")
    local cur=0
    local key=""

    # Hide cursor
    tput civis

    while true; do
        clear
        echo -e "${CYAN}================================================${NC}"
        echo -e "${GREEN}      Gost & SNI Tunnel Manager Pro v4.0      ${NC}"
        echo -e "${CYAN}================================================${NC}"
        echo -e "${YELLOW} Use Arrow Keys (↑/↓) to navigate and Enter (⏎) to select:${NC}\n"

        for i in "${!options[@]}"; do
            if [ $cur -eq $i ]; then
                echo -e "${CYAN}  ➔  ${MAGENTA}[ ${options[$i]} ]${NC}"
            else
                echo -e "      ${options[$i]}"
            fi
        done
        echo -e "\n${CYAN}================================================${NC}"

        # Read keys
        read -rsn3 key
        case "$key" in
            $'\x1b[A') # Up
                ((cur--))
                [ $cur -lt 0 ] && cur=$(( ${#options[@]} - 1 ))
                ;;
            $'\x1b[B') # Down
                ((cur++))
                [ $cur -ge ${#options[@]} ] && cur=0
                ;;
            "") # Enter
                tput cnorm # Show cursor
                return $cur
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Gost Logic
# ------------------------------------------------------------------------------
check_gost() {
    if [ -f "$LOCAL_GOST" ]; then
        GOST_BIN="$LOCAL_GOST"
        return 0
    elif command -v gost &> /dev/null; then
        GOST_BIN=$(command -v gost)
        return 0
    else
        echo -e "${RED}[ERROR] Gost binary not found!${NC}"
        echo -e "Please ensure 'bin/gost' exists in the project folder."
        read -p "Press Enter to return..."
        return 1
    fi
}

install_gost_system() {
    if [ -f "$LOCAL_GOST" ]; then
        echo -e "${BLUE}>>> Installing pre-compiled Gost binary to $SYSTEM_GOST...${NC}"
        sudo cp "$LOCAL_GOST" "$SYSTEM_GOST"
        sudo chmod +x "$SYSTEM_GOST"
        echo -e "${GREEN}[SUCCESS] Gost installed to system path.${NC}"
    else
        echo -e "${RED}[ERROR] Local bin/gost not found.${NC}"
    fi
    read -p "Press Enter to return..."
}

generate_certs() {
    if [ ! -f "$CERT_DIR/cert.pem" ] || [ ! -f "$CERT_DIR/key.pem" ]; then
        echo -e "${YELLOW}>>> Certificates not found in $CERT_DIR.${NC}"
        echo -e "Gost TLS requires cert.pem and key.pem."
        read -p "Do you want to generate self-signed certificates now? (y/n): " gen
        if [[ "$gen" == "y" ]]; then
            sudo openssl req -x509 -newkey rsa:4096 -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" -days 3650 -nodes -subj "/C=IR/ST=Tehran/L=Tehran/O=IT/OU=IT/CN=tgju.org"
            sudo chmod 644 "$CERT_DIR/cert.pem"
            sudo chmod 600 "$CERT_DIR/key.pem"
            echo -e "${GREEN}>>> Certificates generated successfully.${NC}"
        else
            echo -e "${RED}>>> Warning: Gost may fail to start without certificates.${NC}"
        fi
    else
        echo -e "${GREEN}>>> Certificates found in $CERT_DIR.${NC}"
    fi
}

install_service() {
    local mode=$1
    local cmd=$2
    
    # Ensure we use absolute path for the binary in systemd
    local absolute_gost
    if [[ "$GOST_BIN" == "./bin/gost" ]]; then
        absolute_gost="$(pwd)/bin/gost"
    else
        absolute_gost="$GOST_BIN"
    fi
    
    # Replace the binary path in the command with the absolute path
    local final_cmd="${cmd/\"$GOST_BIN\"/\"$absolute_gost\"}"
    final_cmd="${final_cmd/$GOST_BIN/$absolute_gost}"

    echo -e "${BLUE}>>> Installing Systemd Service: $SERVICE_NAME ($mode)${NC}"
    
    sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Gost Tunnel Service ($mode)
After=network.target

[Service]
Type=simple
ExecStart=$final_cmd
Restart=always
RestartSec=3
LimitNOFILE=65535
WorkingDirectory=$(pwd)

[Install]
WantedBy=multi-user.target
EOF"

    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl restart "$SERVICE_NAME"
    
    echo -e "${GREEN}>>> Service started successfully!${NC}"
    sudo systemctl status "$SERVICE_NAME" --no-pager
    read -p "Press Enter to return..."
}

setup_kharej() {
    if ! check_gost; then return; fi
    echo -e "\n${BLUE}--- Kharej Server Setup ---${NC}"
    echo -e "This server will listen on port 443 with TLS and wait for Iran server connections."
    
    generate_certs
    
    local CMD="$GOST_BIN -L \"tcp://:443?tls=true&cert=$CERT_DIR/cert.pem&key=$CERT_DIR/key.pem\""
    
    echo -e "\n${CYAN}Proposed Command:${NC}"
    echo -e "$CMD"
    
    read -p "Install as Service? (y/n): " is_svc
    if [[ "$is_svc" == "y" ]]; then
        install_service "KHAREJ" "$CMD"
    else
        echo -e "${YELLOW}>>> Starting Gost manually. Press Ctrl+C to stop.${NC}"
        eval $CMD
    fi
}

setup_iran() {
    if ! check_gost; then return; fi
    echo -e "\n${BLUE}--- Iran Server Setup ---${NC}"
    echo -e "This server will tunnel local traffic to the Kharej server using a fake SNI (Server Name)."
    
    read -p "Enter Kharej Server IP: " KHAREJ_IP
    if [[ -z "$KHAREJ_IP" ]]; then
        echo -e "${RED}Error: IP is required.${NC}"
        sleep 2; return
    fi
    
    echo -e "\n${CYAN}Select Decoy SNI (tgju.org is recommended):${NC}"
    for i in "${!SNI_LIST[@]}"; do echo -e "$((i+1))) ${SNI_LIST[$i]}"; done
    echo -e "$(( ${#SNI_LIST[@]} + 1 ))) Custom SNI"
    read -p "Selection [1]: " sni_opt; sni_opt=${sni_opt:-1}
    
    local FINAL_SNI
    if [[ "$sni_opt" -le "${#SNI_LIST[@]}" ]]; then
        FINAL_SNI="${SNI_LIST[$((sni_opt-1))]}"
    else
        read -p "Enter Custom SNI: " FINAL_SNI
    fi

    local CMD="$GOST_BIN -L \"tcp://:10000\" -F \"tcp://$KHAREJ_IP:443?tls=true&servername=$FINAL_SNI\""
    
    echo -e "\n${CYAN}Proposed Command:${NC}"
    echo -e "$CMD"
    
    read -p "Install as Service? (y/n): " is_svc
    if [[ "$is_svc" == "y" ]]; then
        install_service "IRAN" "$CMD"
    else
        echo -e "${YELLOW}>>> Starting Gost manually. Press Ctrl+C to stop.${NC}"
        eval $CMD
    fi
}

uninstall() {
    echo -e "${RED}>>> Uninstalling Service and Logs...${NC}"
    sudo systemctl stop "$SERVICE_NAME" &>/dev/null
    sudo systemctl disable "$SERVICE_NAME" &>/dev/null
    sudo rm "/etc/systemd/system/${SERVICE_NAME}.service" &>/dev/null
    sudo systemctl daemon-reload
    echo -e "${GREEN}>>> Service uninstalled successfully.${NC}"
    read -p "Press Enter to return..."
}

# ------------------------------------------------------------------------------
# Main Loop
# ------------------------------------------------------------------------------
while true; do
    options=(
        "Setup Iran Server (Tunnel to Kharej)"
        "Setup Kharej Server (TLS Receiver)"
        "Install Gost to System (/usr/local/bin)"
        "Manage Service (Status/Logs/Stop)"
        "Uninstall Everything"
        "Exit"
    )
    
    select_option "${options[@]}"
    choice=$?
    
    case $choice in
        0) setup_iran ;;
        1) setup_kharej ;;
        2) install_gost_system ;;
        3) 
            echo -e "\n1) Status  2) Logs  3) Stop  4) Restart"
            read -p "Option: " m_opt
            case $m_opt in
                1) sudo systemctl status "$SERVICE_NAME" --no-pager ;;
                2) journalctl -u "$SERVICE_NAME" -f ;;
                3) sudo systemctl stop "$SERVICE_NAME" && echo "Stopped." ;;
                4) sudo systemctl restart "$SERVICE_NAME" && echo "Restarted." ;;
            esac
            read -p "Press Enter..." ;;
        4) uninstall ;;
        5) exit 0 ;;
    esac
done
