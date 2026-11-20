#!/usr/bin/env bash
# Runs before the RedOS Packer build. The template reads the ISO from iso/,
# so make sure it is present and verified first.
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
exec bash ./install-iso.sh
