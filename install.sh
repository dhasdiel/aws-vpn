#!/usr/bin/env bash
# Install the privileged pieces (asks for your password once, via pkexec):
#   /usr/local/bin/aws-vpn-openvpn          root-owned copy of ./openvpn
#   /etc/polkit-1/rules.d/49-aws-vpn.rules  passwordless pkexec for that path
# Run ./build.sh first. Re-run after every rebuild to refresh the binary.
set -euo pipefail
cd "$(dirname "$0")"

BIN=/usr/local/bin/aws-vpn-openvpn
RULES=/etc/polkit-1/rules.d/49-aws-vpn.rules

[ -x ./openvpn ] || { echo "Missing ./openvpn - run ./build.sh first"; exit 1; }

# The rule only ever matches this exact root-owned path, so the binary cannot
# be swapped out to run arbitrary code as root without a password.
pkexec sh -c 'install -Dm755 "$1" "$2" && cat > "$3" && chmod 644 "$3"' \
    sh ./openvpn "$BIN" "$RULES" <<EOF
// aws-vpn: run the AWS-patched OpenVPN via pkexec without a password prompt.
polkit.addRule(function (action, subject) {
    if (action.id === "org.freedesktop.policykit.exec" &&
        (subject.user === "$USER" || subject.isInGroup("wheel") || subject.isInGroup("sudo")) &&
        action.lookup("program") === "$BIN") {
        return polkit.Result.YES;
    }
});
EOF

echo "Installed $BIN and $RULES"
echo "Connect with './vpnctl up' (no terminal) or './connect.sh' (terminal)."
