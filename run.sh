#!/bin/bash

# ==============================================================================
# SNI Spoofing Tunnel Manager Pro v2.3
# ==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Config
LOG_DIR="logs"
TUNNEL_SCRIPT="$(pwd)/sni_tunnel/tunnel.py"
SNI_LIST=("vercel.com" "nextjs.com" "letsencrypt.org" "google.com" "cloudflare.com" "github.com")

log() {
    local level=$1
    local msg=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${msg}" | tee -a "${LOG_DIR}/tunnel.log"
}

check_latency() {
    local host=$1
    local start=$(date +%s%N)
    if curl -s -o /dev/null -m 2 "$host"; then
        local end=$(date +%s%N)
        local diff=$(( (end - start) / 1000000 ))
        echo "$diff"
    else
        echo "999"
    fi
}

show_sni_menu() {
    echo -e "\n${BLUE}--- Choose Best SNI ---${NC}"
    echo -e "${CYAN}Testing latencies...${NC}"
    local best_ms=999
    local best_sni=""
    local results=()
    for sni in "${SNI_LIST[@]}"; do
        local ms=$(check_latency "$sni")
        results+=("$sni|$ms")
        if (( ms < best_ms )); then best_ms=$ms; best_sni=$sni; fi
    done
    for res in "${results[@]}"; do
        local s=${res%|*}
        local m=${res#*|}
        [[ "$s" == "$best_sni" ]] && echo -e " - ${s}: ${GREEN}${m}ms${NC} (Best)" || echo -e " - ${s}: ${YELLOW}${m}ms${NC}"
    done
    echo -e "\n0) Custom SNI"
    echo -e "R) Auto-Rotation (Uses all SNIs)"
    for i in "${!SNI_LIST[@]}"; do echo -e "$((i+1))) ${SNI_LIST[$i]}"; done
    
    read -p "Select SNI [1-${#SNI_LIST[@]}, 0, or R]: " SNI_CHOICE
    
    ROTATION_INTERVAL=0
    if [[ "$SNI_CHOICE" == "R" || "$SNI_CHOICE" == "r" ]]; then
        FINAL_SNI=$(IFS=,; echo "${SNI_LIST[*]}")
        read -p "Enter Rotation Interval in seconds [300]: " ROTATION_INTERVAL
        ROTATION_INTERVAL=${ROTATION_INTERVAL:-300}
    elif [[ "$SNI_CHOICE" == "0" ]]; then
        read -p "Enter Custom SNI: " FINAL_SNI
    elif [[ "$SNI_CHOICE" -ge 1 && "$SNI_CHOICE" -le "${#SNI_LIST[@]}" ]]; then
        FINAL_SNI="${SNI_LIST[$((SNI_CHOICE-1))]}"
    else
        FINAL_SNI="$best_sni"
    fi
}

ask_auth() {
    read -p "Enable PSK Authentication? (y/n): " ENABLE_AUTH
    if [[ "$ENABLE_AUTH" == "y" ]]; then
        read -p "Enter Pre-Shared Key (PSK) [random]: " PSK
        if [[ -z "$PSK" ]]; then
            PSK=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
            echo -e "${YELLOW}Generated random PSK: ${GREEN}$PSK${NC}"
        fi
    else
        PSK=""
    fi
}

ask_udp() {
    echo -e "\n${BLUE}--- UDP Support Options ---${NC}"
    echo -e "1) ${YELLOW}None${NC} (TCP only)"
    echo -e "2) ${YELLOW}Native UDP${NC} (Faster, direct, but NO SNI spoofing for UDP)"
    echo -e "3) ${YELLOW}UDP-over-TCP${NC} (Slower, encapsulated, but BENEFITS from SNI spoofing)"
    read -p "Select UDP Mode [1-3]: " UDP_CHOICE
    case $UDP_CHOICE in
        2) UDP_MODE="native" ;;
        3) UDP_MODE="tcp" ;;
        *) UDP_MODE="none" ;;
    esac
}

ask_obfs() {
    echo -e "\n${BLUE}--- Traffic Obfuscation ---${NC}"
    echo -e "${CYAN}Obfuscation hides traffic patterns and entropy from DPI filters.${NC}"
    read -p "Enable Obfuscation? (y/n): " ENABLE_OBFS
    if [[ "$ENABLE_OBFS" == "y" ]]; then
        read -p "Enter Obfuscation Key [random]: " OBFS_KEY
        if [[ -z "$OBFS_KEY" ]]; then
            OBFS_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
            echo -e "${YELLOW}Generated random Obfs Key: ${GREEN}$OBFS_KEY${NC}"
        fi
    else
        OBFS_KEY=""
    fi
}

install_systemd() {
    local mode=$1
    local ports=$2
    local rhost=$3
    local sni=$4
    local extra_args=$5

    echo -e "${BLUE}Installing Systemd Service...${NC}"
    local SERVICE_NAME="sni-tunnel"
    local DESCRIPTION="SNI Spoofing Tunnel ($mode)"
    local CMD="python3 $TUNNEL_SCRIPT --rhost $rhost --ports $ports --sni $sni $extra_args"
    
    [[ -n "$ROTATION_INTERVAL" && "$ROTATION_INTERVAL" -gt 0 ]] && CMD="$CMD --rotate $ROTATION_INTERVAL"
    [[ -n "$PSK" ]] && CMD="$CMD --psk $PSK"
    [[ -n "$OBFS_KEY" ]] && CMD="$CMD --obfs-key $OBFS_KEY"
    [[ "$UDP_MODE" != "none" ]] && CMD="$CMD --udp-mode $UDP_MODE"

    sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=$DESCRIPTION
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(pwd)
ExecStart=$CMD
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF"

    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME}
    sudo systemctl restart ${SERVICE_NAME}
    echo -e "${GREEN}Service installed and started!${NC}"
    read -p "Press enter to return..."
}

run_iran() {
    echo -e "\n${BLUE}--- Iran Server Configuration ---${NC}"
    read -p "Enter Kharej Server IP: " KHAREJ_IP
    read -p "Enter Ports (comma separated) [443]: " PORTS; PORTS=${PORTS:-443}
    show_sni_menu
    ask_auth
    ask_udp
    ask_obfs
    
    read -p "Install as Systemd Service? (y/n): " IS_SYSTEMD
    if [[ "$IS_SYSTEMD" == "y" ]]; then
        install_systemd "IRAN" "$PORTS" "$KHAREJ_IP" "$FINAL_SNI" ""
    else
        log "INFO" "Starting IRAN Mode"
        CMD="python3 $TUNNEL_SCRIPT --rhost $KHAREJ_IP --ports $PORTS --sni $FINAL_SNI --rotate $ROTATION_INTERVAL --udp-mode $UDP_MODE"
        [[ -n "$PSK" ]] && CMD="$CMD --psk $PSK"
        [[ -n "$OBFS_KEY" ]] && CMD="$CMD --obfs-key $OBFS_KEY"
        $CMD 2>&1 | tee -a "${LOG_DIR}/tunnel.log"
    fi
}

run_kharej() {
    echo -e "\n${BLUE}--- Kharej Server Configuration (Receiver) ---${NC}"
    read -p "Enter Ports (comma separated) [443]: " PORTS; PORTS=${PORTS:-443}
    read -p "Enter Local Target IP [127.0.0.1]: " TIP; TIP=${TIP:-127.0.0.1}
    read -p "Enter Local Target Port [1080]: " TPORT; TPORT=${TPORT:-1080}
    ask_auth
    ask_udp
    ask_obfs
    
    local port_map=""
    IFS=',' read -ra ADDR <<< "$PORTS"
    for i in "${ADDR[@]}"; do port_map+="${i}:${TPORT},"; done
    port_map=${port_map%,}

    read -p "Install as Systemd Service? (y/n): " IS_SYSTEMD
    if [[ "$IS_SYSTEMD" == "y" ]]; then
        install_systemd "KHAREJ" "$port_map" "$TIP" "none" "--no-spoof"
    else
        log "INFO" "Starting KHAREJ Mode"
        CMD="python3 $TUNNEL_SCRIPT --rhost $TIP --ports $port_map --no-spoof --udp-mode $UDP_MODE"
        [[ -n "$PSK" ]] && CMD="$CMD --psk $PSK"
        [[ -n "$OBFS_KEY" ]] && CMD="$CMD --obfs-key $OBFS_KEY"
        $CMD 2>&1 | tee -a "${LOG_DIR}/tunnel.log"
    fi
}

setup_env() {
    mkdir -p "$LOG_DIR"
    if ! command -v python3 &> /dev/null; then
        sudo apt update && sudo apt install -y python3
    fi
}

while true; do
    echo -e "\n${CYAN}================================================${NC}"
    echo -e "${GREEN}       SNI Spoofing Tunnel Management Pro v2.3  ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "1) ${YELLOW}IRAN Mode${NC}      (Sender/Spoofer)"
    echo -e "2) ${YELLOW}KHAREJ Mode${NC}    (Receiver/Transparent)"
    echo -e "3) ${YELLOW}Manage Service${NC} (Systemd Status/Logs)"
    echo -e "4) ${RED}Exit${NC}"
    echo -e "${CYAN}------------------------------------------------${NC}"
    read -p "Select [1-4]: " CHOICE
    case $CHOICE in
        1) run_iran ;;
        2) run_kharej ;;
        3) 
            echo -e "\n1) Status  2) Restart  3) Stop  4) Logs"
            read -p "Option: " S_OPT
            case $S_OPT in
                1) sudo systemctl status sni-tunnel ;;
                2) sudo systemctl restart sni-tunnel ;;
                3) sudo systemctl stop sni-tunnel ;;
                4) sudo journalctl -u sni-tunnel -f ;;
            esac
            ;;
        4) exit 0 ;;
        *) echo -e "${RED}Invalid.${NC}"; sleep 1 ;;
    esac
done
