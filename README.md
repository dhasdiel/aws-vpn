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

- Installs a **root-owned** copy of the binary at
  `/usr/local/bin/aws-vpn-openvpn`
- Installs `/etc/polkit-1/rules.d/49-aws-vpn.rules`, which lets `pkexec` run
  **that exact path only** without a password for your user / wheel / sudo
  members

Because the rule is scoped to a root-owned file, it cannot be abused to run
arbitrary code as root — the file cannot be replaced without root. After the
one-time install prompt, connecting never asks for your password again.

## Usage

```sh
./vpnctl up        # SAML login opens in your browser, then the tunnel starts
./vpnctl down      # stop the tunnel (via the management socket, no password)
./vpnctl toggle    # up if down, down if up
./vpnctl status    # prints: up | connecting | down
./connect.sh       # same flow in a terminal; Ctrl+C to disconnect
```

Logs and state live in `$XDG_RUNTIME_DIR/aws-vpn/` (`openvpn.log`,
`vpnctl.log`, `mgmt.sock`).

## Bar widget

`contrib/omarchy-bar-widget/` is an Omarchy (Quickshell) bar plugin showing
connection state; left-click toggles, right-click opens the OpenVPN log.
Copy it to `~/.config/omarchy/plugins/<namespace>.aws-vpn/`, set `id` /
`moduleName` to match, and adjust the `vpnctl` path if your clone lives
somewhere other than `~/aws-vpn`.

For any other status bar: `vpnctl status` prints `up`, `connecting` or
`down`, so it is trivial to wire into waybar/polybar/i3bar.

## Files

| File | Purpose |
|------|---------|
| `build.sh` | Download, verify (GPG), patch and build OpenVPN 2.6.12 |
| `openvpn-v2.6.12-aws.patch` | The AWS protocol/buffer patch |
| `setup.sh` | Turn your downloaded `.ovpn` into `config` + `vpn.conf` |
| `install.sh` / `uninstall.sh` | Root-owned binary + polkit rule |
| `vpnctl` | Connect/disconnect without a terminal |
| `connect.sh` | Same flow in a terminal |
| `dns.sh` | OpenVPN up/down hook: pushed DNS via `resolvectl` |
| `config` / `vpn.conf` | Your site settings — **gitignored** |

## Security notes

- The passwordless `pkexec` rule matches only
  `/usr/local/bin/aws-vpn-openvpn`, a root-owned file — audit `install.sh`
  before running it.
- The SAML response is a credential; it is written to files under
  `$XDG_RUNTIME_DIR` or a `mktemp` file with `0600`/`umask 077` and deleted
  as soon as the tunnel is up.
- `vpnctl down` sends `SIGTERM` through the OpenVPN management socket owned
  by your user — no privilege needed.

## Uninstall

```sh
./uninstall.sh   # removes /usr/local/bin/aws-vpn-openvpn + the polkit rule
```

## Credits

- Approach based on [aws-vpn-client](https://github.com/aws-vpn-client/aws-vpn-client)
- The OpenVPN patch mirrors the modifications in AWS's own bundled OpenVPN

## License

GPL-2.0 — the patch applies to GPL-licensed OpenVPN source code.
