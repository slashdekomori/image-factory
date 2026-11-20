#!/usr/bin/env bash
set -euo pipefail
name=$1
file=$2
ver="$(date +%Y%m%d).${GITHUB_RUN_NUMBER:-0}"
root=/srv/images/$name
dest=$root/$ver

mkdir -p "$dest"
cp "$file" "$dest/$name-$ver.qcow2"
(cd "$dest" && sha256sum *.qcow2 >SHA256SUMS)
printf '{"version":"%s","commit":"%s"}\n' "$ver" "${GITHUB_SHA:-unknown}" >"$dest/manifest.json"

ln -sfn "$ver" "$root/latest"                    # move "latest"
ls -1d "$root"/2* | head -n -5 | xargs -r rm -rf # keep the last 5
