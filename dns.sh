#!/usr/bin/env bash
# OpenVPN up/down hook: apply VPN-pushed DNS servers/domains to the tun device via systemd-resolved.
[ "$script_type" = "up" ] || exit 0
# Let the bar widget's "open log" read the root-written log (set by vpnctl via --setenv).
[ -n "${AWSVPN_LOG:-}" ] && [ -f "$AWSVPN_LOG" ] && chmod 644 "$AWSVPN_LOG"
dns=(); domains=()
for var in ${!foreign_option_*}; do
  opt="${!var}"
  case "$opt" in
    "dhcp-option DNS "*)    dns+=("${opt#dhcp-option DNS }") ;;
    "dhcp-option DOMAIN "*) domains+=("${opt#dhcp-option DOMAIN }") ;;
  esac
done
[ ${#dns[@]} -gt 0 ] && resolvectl dns "$dev" "${dns[@]}"
[ ${#domains[@]} -gt 0 ] && resolvectl domain "$dev" "${domains[@]}"
exit 0
