#!/usr/bin/env bash
# wifi-testbed.sh — virtual Wi-Fi test bed for Symmetria's connect flow.
#
# Creates two simulated 802.11 radios via mac80211_hwsim, runs a real WPA2-PSK
# access point (hostapd + dnsmasq) on one of them, and leaves the other under
# NetworkManager's control. Symmetria's UI can then connect to a real, secured,
# fully-controllable network WITHOUT touching the machine's actual Wi-Fi card,
# so testing the connect flow never costs internet connectivity.
#
# The AP deliberately advertises NO default route and NO DNS server, so the
# client association cannot hijack the real internet path.
#
#   ./wifi-testbed.sh up      # bring the virtual AP online
#   ./wifi-testbed.sh status  # show current state
#   ./wifi-testbed.sh down    # tear everything down, unload the module
#
# Requires: hostapd, dnsmasq, iw, and the mac80211_hwsim kernel module.

set -euo pipefail

TESTBED_SSID="SymmetriaTestAP"
TESTBED_PASSWORD="testpass123"
TESTBED_AP_ADDRESS="10.99.0.1"
TESTBED_AP_SUBNET="10.99.0"
TESTBED_RUNTIME_DIR="/run/symmetria-wifi-testbed"
HOSTAPD_CONFIG_PATH="$TESTBED_RUNTIME_DIR/hostapd.conf"
HOSTAPD_PID_PATH="$TESTBED_RUNTIME_DIR/hostapd.pid"
DNSMASQ_PID_PATH="$TESTBED_RUNTIME_DIR/dnsmasq.pid"
INTERFACE_RECORD_PATH="$TESTBED_RUNTIME_DIR/interfaces"

log() { printf '  %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Echo every network interface backed by a mac80211_hwsim phy, in phy order.
list_simulated_interfaces() {
    local interface_path interface_name driver_path
    for interface_path in /sys/class/net/*; do
        interface_name="$(basename "$interface_path")"
        [[ -e "$interface_path/phy80211" ]] || continue
        driver_path="$(readlink -f "$interface_path/phy80211/device/driver" 2>/dev/null || true)"
        [[ "$driver_path" == *mac80211_hwsim* ]] && echo "$interface_name"
    done
}

require_root() {
    [[ $EUID -eq 0 ]] || fail "must run as root (use sudo)"
}

testbed_up() {
    require_root

    if lsmod | grep -q '^mac80211_hwsim'; then
        log "mac80211_hwsim already loaded — tearing down first for a clean slate"
        testbed_down_quiet
    fi

    mkdir -p "$TESTBED_RUNTIME_DIR"

    log "loading mac80211_hwsim with 2 simulated radios"
    modprobe mac80211_hwsim radios=2
    # Interface creation is asynchronous; wait for udev to name both devices.
    local waited=0
    while [[ "$(list_simulated_interfaces | wc -l)" -lt 2 ]]; do
        sleep 0.2
        waited=$((waited + 1))
        [[ $waited -lt 50 ]] || fail "simulated interfaces never appeared"
    done

    mapfile -t simulated_interfaces < <(list_simulated_interfaces)
    local access_point_interface="${simulated_interfaces[0]}"
    local client_interface="${simulated_interfaces[1]}"
    printf 'access_point_interface=%s\nclient_interface=%s\n' \
        "$access_point_interface" "$client_interface" >"$INTERFACE_RECORD_PATH"
    log "AP side: $access_point_interface   client side: $client_interface"

    # NetworkManager must not touch the AP radio (it would fight hostapd), but
    # MUST manage the client radio — that is the device under test.
    nmcli device set "$access_point_interface" managed no
    nmcli device set "$client_interface" managed yes

    cat >"$HOSTAPD_CONFIG_PATH" <<EOF
interface=$access_point_interface
driver=nl80211
ssid=$TESTBED_SSID
hw_mode=g
channel=1
wpa=2
wpa_passphrase=$TESTBED_PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

    log "starting hostapd (SSID '$TESTBED_SSID', WPA2-PSK '$TESTBED_PASSWORD')"
    hostapd -B -P "$HOSTAPD_PID_PATH" "$HOSTAPD_CONFIG_PATH" >"$TESTBED_RUNTIME_DIR/hostapd.log" 2>&1 \
        || fail "hostapd failed to start — see $TESTBED_RUNTIME_DIR/hostapd.log"

    ip addr add "$TESTBED_AP_ADDRESS/24" dev "$access_point_interface" 2>/dev/null || true
    ip link set "$access_point_interface" up

    # --dhcp-option=3 (no router) and =6 (no DNS) are what keep the real
    # internet path intact: the client gets an address but never a default
    # route, so wlan0 remains the only way out.
    log "starting dnsmasq (DHCP only, no gateway, no DNS)"
    dnsmasq \
        --interface="$access_point_interface" \
        --bind-interfaces \
        --except-interface=lo \
        --dhcp-range="$TESTBED_AP_SUBNET.10,$TESTBED_AP_SUBNET.100,2h" \
        --dhcp-option=3 \
        --dhcp-option=6 \
        --port=0 \
        --pid-file="$DNSMASQ_PID_PATH" \
        || fail "dnsmasq failed to start"

    log "waiting for the client radio to see the beacon"
    local scan_attempt=0
    while ! nmcli -t -f SSID device wifi list ifname "$client_interface" --rescan yes 2>/dev/null | grep -qx "$TESTBED_SSID"; do
        sleep 1
        scan_attempt=$((scan_attempt + 1))
        [[ $scan_attempt -lt 15 ]] || fail "client radio never saw '$TESTBED_SSID'"
    done

    log ""
    log "Test bed ready. '$TESTBED_SSID' is visible to NetworkManager on $client_interface."
    log "Correct password: $TESTBED_PASSWORD"
    log "Real Wi-Fi ($(nmcli -t -f DEVICE,STATE device | grep '^wlan0' || echo 'wlan0:?')) is untouched."
}

testbed_down_quiet() {
    [[ -f "$HOSTAPD_PID_PATH" ]] && kill "$(cat "$HOSTAPD_PID_PATH")" 2>/dev/null || true
    [[ -f "$DNSMASQ_PID_PATH" ]] && kill "$(cat "$DNSMASQ_PID_PATH")" 2>/dev/null || true
    pkill -f "hostapd .*symmetria-wifi-testbed" 2>/dev/null || true
    # Remove the client profile the test created so each run starts clean.
    nmcli -t -f UUID,NAME connection show 2>/dev/null | while IFS=: read -r uuid name; do
        [[ "$name" == "$TESTBED_SSID" ]] && nmcli connection delete uuid "$uuid" >/dev/null 2>&1 || true
    done
    sleep 0.5
    modprobe -r mac80211_hwsim 2>/dev/null || true
    rm -rf "$TESTBED_RUNTIME_DIR"
}

testbed_down() {
    require_root
    log "tearing down the virtual test bed"
    testbed_down_quiet
    log "done — mac80211_hwsim unloaded, '$TESTBED_SSID' profile removed"
}

testbed_status() {
    if lsmod | grep -q '^mac80211_hwsim'; then
        log "mac80211_hwsim: LOADED"
        log "simulated interfaces: $(list_simulated_interfaces | tr '\n' ' ')"
    else
        log "mac80211_hwsim: not loaded"
    fi
    if pgrep -x hostapd >/dev/null; then log "hostapd: running"; else log "hostapd: stopped"; fi
    log "wifi devices:"
    nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device | grep wifi | sed 's/^/    /'
}

case "${1:-}" in
    up) testbed_up ;;
    down) testbed_down ;;
    status) testbed_status ;;
    *) fail "usage: $0 {up|down|status}" ;;
esac
