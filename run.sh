#!/bin/bash

# ==============================================================================
# SNI Spoofing Tunnel Manager Pro
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
TUNNEL_SCRIPT="sni_tunnel/tunnel.py"
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
    echo -e "${CYAN}Testing latencies from your current server...${NC}"
    
    local best_ms=999
    local best_sni=""
    local results=()

    for sni in "${SNI_LIST[@]}"; do
        local ms=$(check_latency "$sni")
        results+=("$sni|$ms")
        if (( ms < best_ms )); then
            best_ms=$ms
            best_sni=$sni
        fi
    done

    # Display results
    for res in "${results[@]}"; do
        local s=${res%|*}
        local m=${res#*|}
        if [[ "$s" == "$best_sni" ]]; then
            echo -e " - ${s}: ${GREEN}${m}ms${NC} (Best Suggestion)"
        else
            echo -e " - ${s}: ${YELLOW}${m}ms${NC}"
        fi
    done

    echo -e "\n0) Custom SNI"
    for i in "${!SNI_LIST[@]}"; do
        echo -e "$((i+1))) ${SNI_LIST[$i]}"
    done

    read -p "Select SNI [1-${#SNI_LIST[@]}, or 0 for custom]: " SNI_CHOICE
    if [[ "$SNI_CHOICE" == "0" ]]; then
        read -p "Enter Custom SNI: " FINAL_SNI
    elif [[ "$SNI_CHOICE" -ge 1 && "$SNI_CHOICE" -le "${#SNI_LIST[@]}" ]]; then
        FINAL_SNI="${SNI_LIST[$((SNI_CHOICE-1))]}"
    else
        FINAL_SNI="$best_sni"
    fi
    echo -e "${GREEN}Using SNI: $FINAL_SNI${NC}"
}

setup_env() {
    mkdir -p "$LOG_DIR"
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Python 3 not found. Attempting to install...${NC}"
        sudo apt update && sudo apt install -y python3
    fi
}

run_iran() {
    echo -e "\n${BLUE}--- Iran Server Configuration ---${NC}"
    read -p "Enter Kharej Server IP: " KHAREJ_IP
    read -p "Enter Local Port [8080]: " LPORT; LPORT=${LPORT:-8080}
    read -p "Enter Kharej Port [443]: " RPORT; RPORT=${RPORT:-443}
    
    show_sni_menu

    log "INFO" "Starting IRAN Mode ($LPORT -> $KHAREJ_IP:$RPORT via $FINAL_SNI)"
    python3 "$TUNNEL_SCRIPT" --lport "$LPORT" --rhost "$KHAREJ_IP" --rport "$RPORT" --sni "$FINAL_SNI" 2>&1 | tee -a "${LOG_DIR}/tunnel.log"
}

run_kharej() {
    echo -e "\n${BLUE}--- Kharej Server Configuration (Receiver Mode) ---${NC}"
    echo -e "${CYAN}Note: This server will accept ANY spoofed SNI automatically.${NC}"
    read -p "Enter Local Port to listen on [443]: " LPORT; LPORT=${LPORT:-443}
    read -p "Enter Local Target IP [127.0.0.1]: " TIP; TIP=${TIP:-127.0.0.1}
    read -p "Enter Local Target Port (Proxy) [1080]: " TPORT; TPORT=${TPORT:-1080}

    log "INFO" "Starting KHAREJ Mode (Listening on $LPORT, Forwarding to $TIP:$TPORT)"
    # Note the --no-spoof flag
    python3 "$TUNNEL_SCRIPT" --lport "$LPORT" --rhost "$TIP" --rport "$TPORT" --no-spoof 2>&1 | tee -a "${LOG_DIR}/tunnel.log"
}

setup_env

while true; do
    echo -e "\n${CYAN}================================================${NC}"
    echo -e "${GREEN}       SNI Spoofing Tunnel Management Pro       ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "1) ${YELLOW}IRAN Mode${NC}      (Sender/Spoofer)"
    echo -e "2) ${YELLOW}KHAREJ Mode${NC}    (Receiver/Transparent)"
    echo -e "3) ${YELLOW}View Logs${NC}"
    echo -e "4) ${RED}Exit${NC}"
    echo -e "${CYAN}------------------------------------------------${NC}"
    read -p "Select [1-4]: " CHOICE

    case $CHOICE in
        1) run_iran ;;
        2) run_kharej ;;
        3) tail -n 20 "${LOG_DIR}/tunnel.log" ;;
        4) exit 0 ;;
        *) echo -e "${RED}Invalid.${NC}"; sleep 1 ;;
    esac
done
