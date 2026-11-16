# aws-vpn

Unofficial AWS Client VPN client for Linux with SAML (federated) login —
pure Bash and Python stdlib, works on **aarch64** and any distro, with
desktop integration (notifications, polkit, optional bar widget).

## Why

AWS's own Linux client is an x86_64 `.deb` only. This project rebuilds the
AWS-patched OpenVPN from source — the release tarball is verified against the
OpenVPN signing key — and drives the SAML flow with a few small scripts. No
Go, no Node, no browser extension.

## How it works

AWS Client VPN with federated auth works like this under the hood:

1. The client connects with a fake password `ACS::35001`, which tells the
   server to answer `AUTH_FAILED` with a `CRV1` challenge containing a SAML
   SSO URL and a session id.
2. You log in to your IdP in a real browser; the IdP POSTs the
   `SAMLResponse` to `http://127.0.0.1:35001`, where a small Python server
   catches it.
3. The client reconnects with `CRV1::<sid>::<saml response>` as the
   "password".

That SAML response is a huge base64 blob — far bigger than OpenVPN's 128-byte
`USER_PASS_LEN` — which is why a patched OpenVPN is required.
`openvpn-v2.6.12-aws.patch` enlarges the relevant buffers and matches AWS's
modified key-exchange framing (the same patch AWS applies to its bundled
OpenVPN). `remote-random-hostname` is emulated by resolving a random
subdomain of the endpoint before connecting, so both OpenVPN runs hit the
same gateway.

## Requirements

- Runtime: `bash`, `python3`, `openssl`, `pkexec` (polkit), `xdg-open`,
  `resolvectl` (systemd-resolved)
- Build: `curl`, `gpg`, `make`, `gcc`/`clang`
- Kernel `tun` support

## Install

```sh
git clone <this-repo> ~/aws-vpn && cd ~/aws-vpn
./setup.sh ~/Downloads/client-profile.ovpn   # writes ./config and ./vpn.conf
./build.sh                                 # verify + patch + build ./openvpn
./install.sh                               # one password prompt (pkexec)
```

`install.sh` does two things:

- Installs a **root-owned** copy of everything OpenVPN executes or reads as
  root — the binary, the `run` wrapper, the `dns.sh` hook and `vpn.conf` —
  under `/usr/local/libexec/aws-vpn/`
- Installs `/etc/polkit-1/rules.d/49-aws-vpn.rules`, which lets `pkexec` run
  **that wrapper only** without a password — for your user and wheel/sudo
  members — and only with a whitelisted argument shape

Re-run `install.sh` after rebuilding or changing `vpn.conf`.

## Usage

```sh
./vpnctl up        # SAML login opens in your browser, then the tunnel starts
./vpnctl down      # stop the tunnel (via the management socket, no password)
./vpnctl toggle    # up if down, down if up
./vpnctl status    # prints: up | connecting | down
./vpnctl watch     # long-running watcher: notifies if the tunnel drops
./connect.sh       # same flow in a terminal; Ctrl+C to disconnect
```

To get a "Connection lost" notification when the tunnel dies on its own
(network change, crash), install the user service:

```sh
mkdir -p ~/.config/systemd/user
cp contrib/systemd/aws-vpn-watch.service ~/.config/systemd/user/
systemctl --user enable --now aws-vpn-watch
```

Logs and state live in `$XDG_RUNTIME_DIR/aws-vpn/` (`openvpn.log`,
`vpnctl.log`, `mgmt.sock`).

## Bar widget

`contrib/omarchy-bar-widget/` is an Omarchy (Quickshell) bar plugin showing
connection state; left-click toggles, right-click opens the OpenVPN log.
It is also published as a standalone plugin repo at
[dhasdiel/omarchy-aws-vpn](https://github.com/dhasdiel/omarchy-aws-vpn) —
install that one if you want marketplace updates. To use the copy here
directly, put it in `~/.config/omarchy/plugins/<namespace>.aws-vpn/`, set
`id` / `moduleName` to match, and adjust the `vpnctl` path if your clone
lives somewhere other than `~/aws-vpn`.

For any other status bar: `vpnctl status` prints `up`, `connecting` or
`down`, so it is trivial to wire into waybar/polybar/i3bar.

## Files

| File | Purpose |
|------|---------|
| `build.sh` | Download, verify (GPG), patch and build OpenVPN 2.6.12 |
| `openvpn-v2.6.12-aws.patch` | The AWS protocol/buffer patch |
| `setup.sh` | Turn your downloaded `.ovpn` into `config` + `vpn.conf` |
| `install.sh` / `uninstall.sh` | Root-owned files + polkit rule |
| `run` | Root-owned pkexec wrapper: fixed argv, validated args |
| `vpnctl` | Connect/disconnect without a terminal |
| `connect.sh` | Same flow in a terminal |
| `dns.sh` | OpenVPN up/down hook: pushed DNS via `resolvectl` |
| `config` / `vpn.conf` | Your site settings — **gitignored** |

## Security notes

- Passwordless `pkexec` reaches **only** `/usr/local/libexec/aws-vpn/run`, a
  root-owned wrapper whose OpenVPN argv is fixed. Callers can pass nothing
  but a validated remote address, port, protocol and mode — no flags, config
  files, hooks or plugins can reach the root OpenVPN process. The polkit
  rule additionally whitelists the exact argument shape. Audit `run` and
  `install.sh` before installing.
- The SAML callback listener **aborts the login if it cannot bind**
  `127.0.0.1:35001`, so a local process that grabbed the port first cannot
  collect the `SAMLResponse` your browser POSTs.
- The SAML response is a credential; it is written under `$XDG_RUNTIME_DIR`
  (`0600`/`umask 077`) and deleted as soon as the tunnel is up.
- `vpnctl down` sends `SIGTERM` through the OpenVPN management socket owned
  by your user — no privilege needed.

## Uninstall

```sh
./uninstall.sh   # removes /usr/local/libexec/aws-vpn + the polkit rule
```

## Credits

- Approach based on [aws-vpn-client](https://github.com/aws-vpn-client/aws-vpn-client)
- The OpenVPN patch mirrors the modifications in AWS's own bundled OpenVPN

## License

GPL-2.0 — the patch applies to GPL-licensed OpenVPN source code.
