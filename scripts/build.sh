#!/usr/bin/env bash
# Build a golden qcow2 image with Packer.
#
# Usage: build.sh <build-dir>
#
# <build-dir> is any directory containing a Packer template, relative to the
# repository root or absolute. The artifact must be:
#
#   <build-dir>/output/<build-dir>.qcow2
#
# i.e. the qcow2 name matches the directory name.

set -euo pipefail

readonly REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
    echo "usage: $(basename "$0") <build-dir>" >&2
    exit 64
}

main() {
    (($# == 1)) || usage

    local build_dir=$1
    local build_name template
    local output_dir artifact

    [[ $build_dir == /* ]] || build_dir=$REPO_ROOT/$build_dir
    build_name=$(basename -- "$build_dir")
    output_dir=$build_dir/output
    artifact=$output_dir/$build_name.qcow2

    [[ -d "$build_dir" ]] || {
        echo "no build directory: $build_dir" >&2
        exit 1
    }

    echo "building $build_name in $build_dir"
    (
        cd "$build_dir"
        packer init .
        # Full validation rejects an existing output/ directory, which a reused
        # runner will have; packer build performs the full check anyway.
        packer validate -syntax-only .
        packer build -force .
    )

    [[ -f "$artifact" ]] || {
        echo "expected artifact not found: $artifact" >&2
        if [[ -d "$output_dir" ]]; then
            local found
            found=$(find "$output_dir" -maxdepth 1 -type f -name '*.qcow2' -printf '  %f\n')
            if [[ -n "$found" ]]; then
                echo "qcow2 files in $output_dir:" >&2
                printf '%s\n' "$found" >&2
            fi
        fi
        exit 1
    }

    echo "built $artifact"
}

main "$@"
