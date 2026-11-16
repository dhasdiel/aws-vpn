#!/usr/bin/env bash
# Remove the privileged files created by install.sh (asks once via pkexec).
# This directory itself is left untouched.
set -euo pipefail
cd "$(dirname "$0")"

./vpnctl down 2>/dev/null || true
pkexec rm -rf /usr/local/libexec/aws-vpn /etc/polkit-1/rules.d/49-aws-vpn.rules /usr/local/bin/aws-vpn-openvpn
echo "Removed /usr/local/libexec/aws-vpn, the polkit rule and any legacy binary."
