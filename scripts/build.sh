#!/bin/bash
# Build one variant from versions.json.
# Usage: scripts/build.sh <variant> [docker build options...]
# The image is tagged checkmk-arm64:<variant> unless you pass your own -t.

set -e -o pipefail

VARIANT="${1:?usage: $0 <variant> [docker build options...]}"
shift

cd "$(dirname "$0")/.."

entry=$(jq -ce --arg v "$VARIANT" '.[] | select(.variant == $v)' versions.json) || {
    echo "Unknown variant '$VARIANT', available: $(jq -r 'map(.variant) | join(", ")' versions.json)" >&2
    exit 1
}

field() {
    jq -r ".$1" <<<"$entry"
}

docker build \
    --platform linux/arm64 \
    --build-arg IMAGE_CMK_BASE="$(field base_image)" \
    --build-arg DISTRO_CODENAME="$(field distro)" \
    --build-arg CMK_EDITION="$(field edition)" \
    --build-arg CMK_VERSION="$(field version)" \
    --build-arg CMK_RELEASE_TAG="$(field release_tag)" \
    --build-arg CMK_PKG_SHA256="$(field sha256)" \
    --build-arg CMK_EXTRA_PACKAGES="$(field extra_packages)" \
    -t "checkmk-arm64:$VARIANT" \
    "$@" .
