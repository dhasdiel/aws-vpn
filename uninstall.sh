#!/usr/bin/env bash
# Remove the privileged files created by install.sh (asks once via pkexec).
# This directory itself is left untouched.
set -euo pipefail
cd "$(dirname "$0")"

./vpnctl down 2>/dev/null || true
pkexec rm -f /usr/local/bin/aws-vpn-openvpn /etc/polkit-1/rules.d/49-aws-vpn.rules
echo "Removed /usr/local/bin/aws-vpn-openvpn and /etc/polkit-1/rules.d/49-aws-vpn.rules"
