#!/usr/bin/env bash
set -euo pipefail

IMAGE_DATE="2026-07-22"
IMAGE_DIR="image"
IMAGE_FILE="${IMAGE_DIR}/redos-8-cloud-${IMAGE_DATE}.qcow2"
LINK="${IMAGE_DIR}/redos-8-cloud.qcow2"

mkdir -p "$IMAGE_DIR"

if [[ -s "$IMAGE_FILE" ]]; then
    echo "image already present: $IMAGE_FILE, skipping pull"
else
    # Pull into a temp dir so an interrupted download never leaves a
    # half-written file at the final path
    tmp=$(mktemp -d "${IMAGE_DIR}/.pull.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT

    oras pull "ghcr.io/slashdekomori/redos-8-cloud:${IMAGE_DATE}" -o "$tmp"
    mv "$tmp/redos-8-cloud.qcow2" "$IMAGE_FILE"
fi

# Stable name that main.pkr.hcl points at
ln -sf "$(basename "$IMAGE_FILE")" "$LINK"
