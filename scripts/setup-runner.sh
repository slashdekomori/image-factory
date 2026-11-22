#!/usr/bin/env bash
# Install everything the image factory needs on a Debian 13 (trixie) runner.
#
# Usage: sudo ./setup-runner.sh [runner-user]
#
# runner-user  the account the GitHub Actions runner runs as; it is added
#              to the kvm group so Packer can use /dev/kvm.
#              Defaults to $SUDO_USER.
#
# Installs: qemu, libguestfs (virt-customize), xorriso, jq, packer, oras.
# Packer and oras are the latest releases, fetched from their official
# release endpoints, so no versions are pinned here.

set -euo pipefail

readonly RUNNER_USER=${1:-${SUDO_USER:-}}

((EUID == 0)) || {
    echo "run as root: sudo $0" >&2
    exit 1
}

export DEBIAN_FRONTEND=noninteractive

echo "==> apt packages"
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl unzip git jq \
    qemu-system-x86 qemu-utils \
    libguestfs-tools \
    xorriso genisoimage \
    linux-image-amd64

# libguestfs's appliance needs a readable kernel in /boot. Debian allows
# this by default; the check guards against hardened setups.
if ! ls /boot/vmlinuz-* >/dev/null 2>&1; then
    echo "no kernel found in /boot; libguestfs needs one" >&2
    exit 1
fi
chmod 0644 /boot/vmlinuz-* 2>/dev/null || true

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "==> packer"
packer_version=$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/packer |
    jq -r .current_version)
curl -fsSL -o "$tmp/packer.zip" \
    "https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_amd64.zip"
unzip -oq "$tmp/packer.zip" packer -d "$tmp"
install -m 0755 "$tmp/packer" /usr/local/bin/packer

echo "==> oras"
oras_version=$(curl -fsSL https://api.github.com/repos/oras-project/oras/releases/latest |
    jq -r .tag_name | sed 's/^v//')
curl -fsSL -o "$tmp/oras.tar.gz" \
    "https://github.com/oras-project/oras/releases/download/v${oras_version}/oras_${oras_version}_linux_amd64.tar.gz"
tar -xzf "$tmp/oras.tar.gz" -C "$tmp" oras
install -m 0755 "$tmp/oras" /usr/local/bin/oras

echo "==> kvm access"
if [[ -n $RUNNER_USER ]]; then
    usermod -aG kvm "$RUNNER_USER"
    echo "added $RUNNER_USER to kvm (restart the runner service to apply)"
else
    echo "no runner user given; add yours with: usermod -aG kvm <user>"
fi
[[ -e /dev/kvm ]] || echo "WARNING: /dev/kvm missing; enable virtualization (nested virt if this is a VM)"

echo "==> versions"
for cmd in packer oras jq qemu-img qemu-system-x86_64 virt-customize xorriso; do
    command -v "$cmd" >/dev/null || {
        echo "MISSING: $cmd" >&2
        exit 1
    }
done
packer version | head -n1
oras version | head -n1
qemu-img --version | head -n1
virt-customize --version

echo "done"
