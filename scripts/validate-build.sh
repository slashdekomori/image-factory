#!/usr/bin/env bash
# Build a golden qcow2 image with Packer.
#
# Usage: validate-build.sh <build-dir>
#
# <build-dir> is any directory containing a Packer template, relative to the
# repository root or absolute. The artifact must be:
#
#   <build-dir>/output/<build-dir>.qcow2
#
# i.e. the qcow2 name matches the directory name.
#
# If <build-dir>/pre-build.sh exists, it runs first, from inside <build-dir>.
# Use it for image-specific setup such as downloading an install ISO.
#
# Metadata: after the build, a JSON file is injected into the image at
# /etc/image-metadata.json (via libguestfs) and written next to the
# artifact as <artifact>.meta.json. The description comes from
# $IMAGE_DESCRIPTION, or else <build-dir>/DESCRIPTION.
#
# Requires: packer, jq, qemu-img, virt-customize (libguestfs-tools).

set -euo pipefail

readonly REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly GUEST_METADATA_PATH=/etc/image-metadata.json

usage() {
    echo "usage: $(basename "$0") <build-dir>" >&2
    exit 64
}

resolve_description() {
    local build_dir=$1
    if [[ -n ${IMAGE_DESCRIPTION:-} ]]; then
        printf '%s' "$IMAGE_DESCRIPTION"
    elif [[ -f "$build_dir/DESCRIPTION" ]]; then
        cat -- "$build_dir/DESCRIPTION"
    fi
}

# Metadata known before/at build time. This exact file is baked into the image.
write_base_metadata() {
    local out=$1 build_name=$2 description=$3

    jq -n \
        --arg name "$build_name" \
        --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg description "$description" \
        --arg git_commit "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --arg git_dirty "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | grep -q . && echo true || echo false)" \
        --arg packer "$(packer version | head -n1)" \
        '{name:$name, built_at:$built_at, description:$description,
          git:{commit:$git_commit, dirty:($git_dirty=="true")},
          packer:$packer}' \
        >"$out"
}

# Upload the metadata file into the finished qcow2.
inject_metadata() {
    local artifact=$1 metadata_file=$2

    LIBGUESTFS_BACKEND=direct virt-customize -a "$artifact" \
        --upload "$metadata_file:$GUEST_METADATA_PATH" \
        --chmod "0644:$GUEST_METADATA_PATH" \
        --selinux-relabel
}

# Sidecar = baked metadata + fields that only exist after the image is final.
write_sidecar() {
    local artifact=$1 metadata_file=$2
    local sidecar=$artifact.meta.json

    jq \
        --arg sha256 "$(sha256sum "$artifact" | cut -d' ' -f1)" \
        --argjson qemu "$(qemu-img info --output=json "$artifact")" \
        '. + {sha256:$sha256, virtual_size:$qemu["virtual-size"], format:$qemu.format}' \
        "$metadata_file" >"$sidecar"

    echo "wrote $sidecar"
}

main() {
    (($# == 1)) || usage

    local build_dir=$1
    local build_name
    local output_dir artifact metadata_file

    [[ $build_dir == /* ]] || build_dir=$REPO_ROOT/$build_dir
    build_name=$(basename -- "$build_dir")
    output_dir=$build_dir/output
    artifact=$output_dir/$build_name.qcow2

    [[ -d "$build_dir" ]] || {
        echo "no build directory: $build_dir" >&2
        exit 1
    }

    echo "building $build_name in $build_dir"

    # Image-specific preparation (e.g. downloading an install ISO).
    if [[ -f "$build_dir/pre-build.sh" ]]; then
        echo "running pre-build hook for $build_name"
        (cd "$build_dir" && bash ./pre-build.sh)
    fi

    # Kept outside output/ because `packer build -force` may wipe that directory.
    metadata_file=$(mktemp)
    trap "rm -f '$metadata_file'" EXIT
    write_base_metadata "$metadata_file" "$build_name" "$(resolve_description "$build_dir")"

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

    inject_metadata "$artifact" "$metadata_file"
    write_sidecar "$artifact" "$metadata_file"

    echo "built $artifact"
}

main "$@"
