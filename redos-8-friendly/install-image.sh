#!/usr/bin/env bash
# Fetch the redos-8-cloud base image from ghcr.io and expose it under a
# stable name for main.pkr.hcl.
#
# Pulls :latest by default. To pin a specific release, set IMAGE_TAG, e.g.
#   IMAGE_TAG=20260722.5 ./install-image.sh
set -euo pipefail

REPO="ghcr.io/slashdekomori/redos-8-cloud"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_DIR="image"
LINK="${IMAGE_DIR}/redos-8-cloud.qcow2"

mkdir -p "$IMAGE_DIR"

# Resolve the tag to a digest first. A moving tag like "latest" can't be
# used as a cache key, but the digest changes exactly when the image does.
digest=$(oras resolve "${REPO}:${IMAGE_TAG}")
short=${digest#sha256:}
short=${short:0:12}

IMAGE_FILE="${IMAGE_DIR}/redos-8-cloud-${short}.qcow2"

if [[ -s "$IMAGE_FILE" ]]; then
    echo "image already present: $IMAGE_FILE ($IMAGE_TAG), skipping pull"
else
    echo "pulling ${REPO}:${IMAGE_TAG} (${digest})"

    # Pull into a temp dir so an interrupted download never leaves a
    # half-written file at the final path
    tmp=$(mktemp -d "${IMAGE_DIR}/.pull.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT

    oras pull "${REPO}@${digest}" -o "$tmp"
    mv "$tmp/redos-8-cloud.qcow2" "$IMAGE_FILE"
fi

# Stable name that main.pkr.hcl points at
ln -sfn "$(basename "$IMAGE_FILE")" "$LINK"

# Drop older cached images so the runner's disk doesn't fill up
find "$IMAGE_DIR" -maxdepth 1 -type f -name 'redos-8-cloud-*.qcow2' \
    ! -name "$(basename "$IMAGE_FILE")" -delete
