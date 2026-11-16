#!/usr/bin/env bash
# Connect to an AWS Client VPN endpoint (SAML) with a patched OpenVPN.
# Based on github.com/aws-vpn-client/aws-vpn-client; no Go or dig needed.
# Usage: ./connect.sh      (Ctrl+C to disconnect)
set -euo pipefail
cd "$(dirname "$0")"

[ -f ./config ] || { echo "Missing ./config - run ./setup.sh <profile.ovpn> (see README.md)"; exit 1; }
. ./config
: "${VPN_HOST:?set VPN_HOST in ./config}"
PORT="${PORT:-443}"
PROTO="${PROTO:-udp}"
OVPN_BIN="./openvpn"
# Root-owned wrapper installed by install.sh; pkexec runs it (with validated
# args only) without a password prompt.
RUN_BIN="/usr/local/libexec/aws-vpn/run"
RUN_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/aws-vpn"
OVPN_CONF="vpn.conf"
SAML_FILE="$PWD/saml-response.txt"
READY="$RUN_DIR/saml-ready"

mkdir -p "$RUN_DIR" && chmod 700 "$RUN_DIR"
[ -x "$OVPN_BIN" ] || { echo "Missing $PWD/openvpn - run ./build.sh (see README.md)"; exit 1; }
[ -x "$RUN_BIN" ] || { echo "Missing $RUN_BIN - run ./install.sh"; exit 1; }

# Random hostname prefix, resolved once so both OpenVPN runs hit the same gateway
RAND=$(openssl rand -hex 12)
SRV=$(getent ahostsv4 "${RAND}.${VPN_HOST}" | awk 'NR==1{print $1}')
[ -n "$SRV" ] || { echo "Could not resolve ${VPN_HOST}"; exit 1; }

rm -f "$SAML_FILE" "$READY"

# Local receiver for the SAML POST from the browser (127.0.0.1:35001)
python3 - "$SAML_FILE" "$READY" <<'PY' &
import os, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
out, ready = sys.argv[1], sys.argv[2]
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        saml = urllib.parse.parse_qs(body).get("SAMLResponse", [""])[0]
        self.send_response(200); self.end_headers()
        if not saml:
            self.wfile.write(b"No SAMLResponse in request"); return
        fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.write(fd, urllib.parse.quote_plus(saml).encode()); os.close(fd)
        self.wfile.write(b"Got SAML response - you can close this window.")
        raise SystemExit
    def log_message(self, *a): pass
try:
    httpd = HTTPServer(("127.0.0.1", 35001), H)
except OSError:
    sys.exit(1)
open(ready, "w").close()
try:
    httpd.serve_forever()
except SystemExit:
    pass
PY
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true; rm -f "$SAML_FILE" "$READY"' EXIT

# Abort if the listener failed to bind: a process already holding :35001
# could otherwise steal the SAMLResponse the browser is about to POST.
for _ in $(seq 25); do
  [ -e "$READY" ] && break
  kill -0 "$SERVER_PID" 2>/dev/null || { echo "Cannot listen on 127.0.0.1:35001 - already in use" >&2; exit 1; }
  sleep 0.2
done
rm -f "$READY"

echo "Getting SAML login URL from ${SRV}:${PORT} ..."
OVPN_OUT=$($OVPN_BIN --config "$OVPN_CONF" --verb 3 \
    --proto "$PROTO" --remote "$SRV" "$PORT" \
    --auth-user-pass <(printf "%s\n%s\n" "N/A" "ACS::35001") 2>&1 | grep AUTH_FAILED,CRV1 || true)
URL=$(echo "$OVPN_OUT" | grep -Eo 'https://.+' || true)
[ -n "$URL" ] || { echo "No SAML URL returned by the server"; exit 1; }
VPN_SID=$(echo "$OVPN_OUT" | awk -F : '{print $7}')

echo "Opening browser for login..."
xdg-open "$URL" >/dev/null 2>&1 &

for _ in $(seq 120); do [ -s "$SAML_FILE" ] && break; sleep 1; done
[ -s "$SAML_FILE" ] || { echo "SAML login timed out (2 min)"; exit 1; }

echo "Login OK - starting tunnel. Ctrl+C to disconnect."
# The wrapper reads creds from this fixed path inside your runtime dir.
CREDS="$RUN_DIR/creds"
( umask 077; printf "%s\n%s\n" "N/A" "CRV1::${VPN_SID}::$(cat "$SAML_FILE")" > "$CREDS" )
rm -f "$SAML_FILE"
trap 'kill $SERVER_PID 2>/dev/null || true; rm -f "$SAML_FILE" "$READY" "$CREDS"' EXIT

# Root part via the root-owned wrapper (fixed argv; passwordless per the
# polkit rule). Foreground mode: Ctrl+C stops the tunnel here; the wrapper's
# management socket also lets vpnctl see/stop it without pkexec kill.
pkexec "$RUN_BIN" "$SRV" "$PORT" "$PROTO" foreground
