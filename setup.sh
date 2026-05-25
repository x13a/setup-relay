#!/bin/bash

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
    local deps=()
    if ! command -v netfilter-persistent &>/dev/null; then
        deps+=(iptables-persistent)
    fi
    if ! command -v dig &>/dev/null; then
        deps+=(dnsutils)
    fi
    (( ${#deps[@]} == 0 )) && return 0
    echo "[*] installing ${deps[*]}"
    sudo apt-get update
    sudo apt-get install -y "${deps[@]}"
    echo "[+] dependencies installed"
}

get_dest_ip() {
    local dest ip
    while true; do
        read -rp "[?] enter destination ip or domain: " dest
        if resolve_dest "$dest"; then
            ip="${VARS[dest_ip]}"
            if [[ "$dest" != "$ip" ]]; then
                echo "[+] resolved $dest to $ip"
            fi
            break
        fi
        echo "[-] invalid destination"
    done
}

resolve_dest() {
    local dest="$1"
    [[ -n "$dest" ]] || return 1
    if is_domain "$dest"; then
        local ips
        ips=$(dig +short +tries=1 "$dest" A "$dest" AAAA) || return 1
        local ip
        while IFS= read -r ip; do
            { [[ -z "$ip" ]] || is_domain "$ip"; } && continue
            check_ip "$ip" && return 0
        done <<< "$ips"
    fi
    check_ip "$dest"
}

get_dest_port() {
    local port
    while true; do
        read -rp "[?] enter destination port: " port
        if [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && (( port <= 65535 )); then
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

check_ip() {
    local ip="$1"
    local opt
    for opt in 4 6; do
        ip -"$opt" route get "$ip" &>/dev/null || continue
        VARS[dest_ip]="$ip"
        return 0
    done
    return 1
}

is_ipv6() {
    [[ "$1" == *:* ]]
}

is_domain() {
    local label='[[:alnum:]]([[:alnum:]-]*[[:alnum:]])?'
    local tld="([[:alpha:]]{2,}|[xX][nN]--${label})"
    local pattern="^(${label}\.)+${tld}\.?$"
    [[ "$1" =~ $pattern ]]
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
    add_iptables_rule "$cmd" filter FORWARD \
        -m conntrack --ctstate RELATED,ESTABLISHED \
        -j ACCEPT
    add_iptables_rule "$cmd" nat PREROUTING \
        -p "$proto" --dport "$port" \
        -m addrtype --dst-type LOCAL \
        -j DNAT --to-destination "$dst"
    add_iptables_rule "$cmd" nat POSTROUTING \
        -p "$proto" -d "$ip" --dport "$port" \
        -m conntrack --ctstate DNAT \
        -j MASQUERADE
    add_iptables_rule "$cmd" filter FORWARD \
        -p "$proto" -d "$ip" --dport "$port" \
        -m conntrack --ctstate DNAT \
        -j ACCEPT
    echo "[+] iptables relay setted"
}

add_iptables_rule() {
    local cmd="$1"
    local table="$2"
    local chain="$3"
    shift 3
    if ! sudo "$cmd" -t "$table" -C "$chain" "$@"; then
        sudo "$cmd" -t "$table" -A "$chain" "$@"
    fi
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
    echo "[+] done"
}

main "$@"
