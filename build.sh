#!/usr/bin/env bash
# Builds AWS-patched OpenVPN 2.6.12 natively into ./openvpn. No root needed.
# Source tarball is verified against the OpenVPN security key F554A3687412CFFEBDEFE0A312F5F7B42F2B01E7.
set -euo pipefail
cd "$(dirname "$0")"
DIR=$PWD
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
cd "$B"
curl -sSfLO https://swupdate.openvpn.org/community/releases/openvpn-2.6.12.tar.gz
curl -sSfLO https://swupdate.openvpn.org/community/releases/openvpn-2.6.12.tar.gz.asc
export GNUPGHOME="$B/gpg"; mkdir -m700 "$GNUPGHOME"
curl -sSfL https://keys.openpgp.org/vks/v1/by-fingerprint/F554A3687412CFFEBDEFE0A312F5F7B42F2B01E7 | gpg -q --import
gpg --verify openvpn-2.6.12.tar.gz.asc openvpn-2.6.12.tar.gz
tar xzf openvpn-2.6.12.tar.gz
cd openvpn-2.6.12
patch -p1 < "$DIR/openvpn-v2.6.12-aws.patch"
./configure --disable-plugin-auth-pam --disable-dco --enable-systemd=no >/dev/null
make -j"$(nproc)" >/dev/null
install -m755 src/openvpn/openvpn "$DIR/openvpn"
"$DIR/openvpn" --version | head -1
echo "Built $DIR/openvpn - now run ./install.sh to install the privileged copy"
