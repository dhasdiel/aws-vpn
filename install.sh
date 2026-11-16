#!/usr/bin/env bash
# Install the privileged pieces (asks for your password once, via pkexec):
#   /usr/local/libexec/aws-vpn/             root-owned openvpn, "run" wrapper,
#                                           dns.sh hook and vpn.conf
#   /etc/polkit-1/rules.d/49-aws-vpn.rules  passwordless pkexec for that
#                                           wrapper only, with validated args
# Everything OpenVPN executes or reads as root lives in that root-owned dir.
# Re-run after rebuilding or changing vpn.conf.
set -euo pipefail
cd "$(dirname "$0")"

D=/usr/local/libexec/aws-vpn
RULES=/etc/polkit-1/rules.d/49-aws-vpn.rules

[ -x ./openvpn ] && [ -f ./vpn.conf ] && [ -x ./run ] \
  || { echo "Run ./setup.sh and ./build.sh first"; exit 1; }

# The wrapper is root-owned and its argv is fixed, so the polkit grant can
# never reach openvpn flags, configs, hooks or plugins supplied by a caller.
pkexec sh -c '
  set -e
  install -d -m755 "$2"
  install -m755 "$1/openvpn" "$1/dns.sh" "$1/run" -t "$2"
  install -m644 "$1/vpn.conf" "$2/vpn.conf"
  rm -f /usr/local/bin/aws-vpn-openvpn   # legacy unrestricted path
  cat > "$3" && chmod 644 "$3"
' sh "$PWD" "$D" "$RULES" <<EOF
// aws-vpn: run the AWS-patched OpenVPN via the root-owned "run" wrapper
// without a password prompt. The wrapper fixes openvpn's argv; this rule
// additionally whitelists the exact argument shape it accepts.
polkit.addRule(function (action, subject) {
    if (action.id !== "org.freedesktop.policykit.exec") return;
    if (!(subject.user === "$USER" || subject.isInGroup("wheel") || subject.isInGroup("sudo"))) return;
    if (action.lookup("program") !== "$D/run") return;
    var cmd = action.lookup("command_line");
    if (typeof cmd === "string" &&
        /^\\/usr\\/local\\/libexec\\/aws-vpn\\/run [0-9a-fA-F.:]{1,45} [0-9]{1,5} (udp|tcp)( (daemon|foreground))?\$/.test(cmd)) {
        return polkit.Result.YES;
    }
});
EOF

echo "Installed $D/ and $RULES"
echo "Connect with './vpnctl up' (no terminal) or './connect.sh' (terminal)."
