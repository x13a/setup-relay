#!/usr/bin/env bash

set -eEuo pipefail
trap 'echo "error: $BASH_COMMAND on line $LINENO" >&2' ERR

BASE_DIR="$(dirname "$(realpath "$0")")"

declare -A VARS
declare -A DEFAULTS

VARS[dest_ip]=""
VARS[dest_port]=""
VARS[dest_proto]=""
DEFAULTS[proto]="udp"

configure_system() {
    local dst="/etc/sysctl.d/99-relay.conf"
    [[ -f "$dst" ]] && { echo "[*] skip: sysctl config file exists $dst"; return 0; }
    echo "[*] configuring system"
    local src="$BASE_DIR/$dst"
    [[ -f "$src" ]] || { echo "[-] error: sysctl config file not found $src" >&2; exit 1; }
    sudo install -m 0644 "$src" "$dst"
    sudo sysctl --system
    echo "[+] sysctl config file deployed to $dst"
}

install_deps() {
    if command -v netfilter-persistent &>/dev/null; then
        return 0;
    fi
    echo "[*] installing iptables-persistent"
    sudo apt-get update
    sudo apt-get install -y iptables-persistent
    echo "[+] iptables-persistent installed"
}

get_dest_ip() {
    local ip
    while true; do
        read -rp "[?] enter destination ip: " ip
        if is_valid_ip "$ip"; then
            VARS[dest_ip]="$ip"
            break
        fi
        echo "[-] invalid ip address"
    done
}

get_dest_port() {
    local port
    while true; do
        read -rp "[?] enter destination port: " port
        if [[ "$port" =~ ^[0-9]+$ ]] && ((port > 0 && port <= 65535)); then
            VARS[dest_port]="$port"
            break
        fi
        echo "[-] invalid port"
    done
}

get_dest_proto() {
    local default="${DEFAULTS[proto]}"
    local proto
    read -rp "[?] enter protocol (tcp/udp) [$default]: " proto
    proto="${proto:-$default}"
    if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
        echo "[-] invalid protocol, using default: $default"
        proto="$default"
    fi
    VARS[dest_proto]="$proto"
}

is_valid_ip() {
    local ip="$1"
    if ip route get "$ip" &>/dev/null; then
        return 0
    fi
    if ip -6 route get "$ip" &>/dev/null; then
        return 0
    fi
    return 1
}

is_ipv6() {
    [[ "$1" == *:* ]]
}

setup_iptables() {
    echo "[*] setting up iptables relay"
    local ip="${VARS[dest_ip]}"
    local port="${VARS[dest_port]}"
    local proto="${VARS[dest_proto]}"
    local cmd dst
    if is_ipv6 "$ip"; then
        cmd="ip6tables"
        dst="[$ip]:$port"
    else
        cmd="iptables"
        dst="$ip:$port"
    fi
    sudo $cmd -t nat -A PREROUTING \
        -p "$proto" --dport "$port" \
        -j DNAT --to-destination "$dst"
    sudo $cmd -t nat -A POSTROUTING \
        -p "$proto" -d "$ip" --dport "$port" \
        -j MASQUERADE
    sudo $cmd -A FORWARD \
        -p "$proto" -d "$ip" --dport "$port" \
        -j ACCEPT
    echo "[+] iptables relay setted"
}

save_iptables() {
    echo "[*] saving iptables rules"
    sudo netfilter-persistent save
    echo "[+] iptables rules saved"
}

# ============================
# Main
# ============================

main() {
    echo "[*] starting"
    configure_system
    install_deps
    get_dest_ip
    get_dest_port
    get_dest_proto
    setup_iptables
    save_iptables
    echo "[*] done"
}

main "$@"
