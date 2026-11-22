#!/usr/bin/env bash
# Push a built qcow2 image to GitHub Container Registry (ghcr.io) as an OCI
# artifact using ORAS.
#
# Usage: github-publish.sh <image-name> [version]
#
# Pushes <image-name>/output/<image-name>.qcow2 (and its .meta.json sidecar
# when present) to:
#   ghcr.io/<owner>/<image-name>:<version>
#   ghcr.io/<owner>/<image-name>:latest
#
# Pull it back with:
#   oras pull ghcr.io/<owner>/<image-name>:latest
#
# Environment:
#   GITHUB_REPOSITORY_OWNER  package namespace (set by GitHub Actions)
#   GITHUB_REPOSITORY        linked repo, for the package's source annotation
#   GITHUB_RUN_NUMBER        used for the default version (default 0)
#
# Requires: oras, already logged in to ghcr.io.

set -euo pipefail

readonly REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REGISTRY=ghcr.io

usage() {
  echo "usage: $(basename "$0") <image-name> [version]" >&2
  exit 64
}

main() {
  (($# >= 1 && $# <= 2)) || usage

  local image_name=$1
  local version=${2:-$(date +%Y%m%d).${GITHUB_RUN_NUMBER:-0}}
  local owner repo output_dir
  local files=()

  # Registry paths must be lowercase.
  owner=${GITHUB_REPOSITORY_OWNER:?GITHUB_REPOSITORY_OWNER is not set}
  owner=${owner,,}
  repo=$REGISTRY/$owner/${image_name,,}

  output_dir=$REPO_ROOT/$image_name/output
  [[ -f "$output_dir/$image_name.qcow2" ]] || {
    echo "no such file: $output_dir/$image_name.qcow2" >&2
    exit 1
  }

  files+=("$image_name.qcow2:application/octet-stream")
  if [[ -f "$output_dir/$image_name.qcow2.meta.json" ]]; then
    files+=("$image_name.qcow2.meta.json:application/json")
  fi

  echo "pushing $repo:$version and $repo:latest"

  # The source annotation links the package to this repository, which lets
  # it inherit the repo's access permissions.
  (
    cd "$output_dir"
    oras push "$repo:$version,latest" \
      --artifact-type application/vnd.qcow2 \
      --annotation "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY:-unknown}" \
      --annotation "org.opencontainers.image.version=$version" \
      --annotation "org.opencontainers.image.revision=${GITHUB_SHA:-unknown}" \
      "${files[@]}"
  )
}

main "$@"
