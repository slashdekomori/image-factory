#!/usr/bin/env bash
# Download the RedOS install ISO and verify its checksum.
set -euo pipefail

readonly ISO=redos-8-20260716.0-Everything-x86_64-DVD1.iso
readonly BASE_URL=https://files.red-soft.ru/redos/8.0/x86_64/iso

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mkdir -p iso
cd iso

# Keep the ISO cached between builds; download only what is missing.
[[ -f $ISO ]] || curl -k -O "$BASE_URL/$ISO"
[[ -f $ISO.MD5SUM ]] || curl -k -O "$BASE_URL/$ISO.MD5SUM"

# A partial or stale cache would otherwise fail every build.
if ! md5sum -c "$ISO.MD5SUM"; then
  echo "cached ISO failed checksum; downloading again" >&2
  rm -f "$ISO" "$ISO.MD5SUM"
  curl -k -O "$BASE_URL/$ISO"
  curl -k -O "$BASE_URL/$ISO.MD5SUM"
  md5sum -c "$ISO.MD5SUM"
fi
