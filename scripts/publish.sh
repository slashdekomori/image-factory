#!/usr/bin/env bash
# Publish a built qcow2 image as a new dated release.
#
# Usage: publish.sh <image-name> <path-to-qcow2>
#
# Layout:
#   /srv/images/<image-name>/
#     <YYYYMMDD>.<run>/              one directory per release
#       <image-name>-<version>.qcow2
#       SHA256SUMS
#       manifest.json
#     latest -> <YYYYMMDD>.<run>     symlink to the newest release
#
# Environment:
#   GITHUB_RUN_NUMBER  release suffix (default 0)
#   GITHUB_SHA         commit recorded in manifest.json (default "unknown")
#   IMAGE_ROOT         publish root (default /srv/images)

set -euo pipefail

readonly KEEP_RELEASES=5
readonly IMAGE_ROOT=${IMAGE_ROOT:-/srv/images}

usage() {
  echo "usage: $(basename "$0") <image-name> <path-to-qcow2>" >&2
  exit 64
}

main() {
  (( $# == 2 )) || usage

  local image_name=$1
  local source_image=$2
  local version commit image_dir release_dir image_file

  version="$(date +%Y%m%d).${GITHUB_RUN_NUMBER:-0}"
  commit=${GITHUB_SHA:-unknown}
  image_dir=$IMAGE_ROOT/$image_name
  release_dir=$image_dir/$version
  image_file=$image_name-$version.qcow2

  [[ -f "$source_image" ]] || {
    echo "no such file: $source_image" >&2
    exit 1
  }

  mkdir -p "$release_dir"
  cp "$source_image" "$release_dir/$image_file"
  (cd "$release_dir" && sha256sum "$image_file" >SHA256SUMS)
  printf '{"version":"%s","commit":"%s"}\n' "$version" "$commit" \
    >"$release_dir/manifest.json"

  # Point latest at the new release before pruning, so a failed prune can
  # never leave latest dangling.
  ln -sfn "$version" "$image_dir/latest"

  # Keep the newest KEEP_RELEASES dated directories. Relies on version
  # strings sorting correctly with sort -V: newest first, then skip the
  # newest KEEP_RELEASES and remove the rest.
  find "$image_dir" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' \
    | sort -rV \
    | tail -n "+$((KEEP_RELEASES + 1))" \
    | while IFS= read -r old_release; do
        rm -rf "$old_release"
      done
}

main "$@"
