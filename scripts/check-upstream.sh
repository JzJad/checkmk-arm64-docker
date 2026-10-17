#!/bin/bash
# Look for newer packages in the upstream releases and update versions.json.
# A variant is updated when upstream has a newer version for its edition and
# distro, or when the package of the pinned version was re-uploaded with a
# different checksum (upstream replaces assets in place).
# Prints "title=<summary>" when versions.json was changed.
# Needs gh (authenticated) and jq.

set -e -o pipefail

UPSTREAM_REPO="sergiodadi/check-mk-raspberry"
VERSIONS="${VERSIONS:-versions.json}"

# "<version> <tag> <asset>" for every stable package of every release
packages=$(
    gh api --paginate "repos/$UPSTREAM_REPO/releases" --jq '.[]' |
        jq -r '
            select(.prerelease | not) | .tag_name as $tag
            | .assets[]
            | (.name | capture("^check-mk-[a-z]+-(?<v>[0-9]+\\.[0-9]+\\.[0-9]+p[0-9]+)_0\\.[a-z]+_arm64\\.deb$")?) as $m
            | select($m != null)
            | "\($m.v) \($tag) \(.name)"'
)

changes=()
for variant in $(jq -r '.[].variant' "$VERSIONS"); do
    entry=$(jq -c --arg v "$variant" '.[] | select(.variant == $v)' "$VERSIONS")
    current=$(jq -r .version <<<"$entry")
    current_sha=$(jq -r .sha256 <<<"$entry")
    suffix="_0.$(jq -r .distro <<<"$entry")_arm64.deb"
    prefix="check-mk-$(jq -r .edition <<<"$entry")-"

    read -r latest tag asset < <(
        awk -v p="$prefix" -v s="$suffix" 'index($3, p) == 1 && substr($3, length($3) - length(s) + 1) == s' <<<"$packages" |
            sort -V | tail -n 1
    )
    if [ -z "$latest" ]; then
        echo "$variant: no package found in $UPSTREAM_REPO" >&2
        exit 1
    fi
    if [ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n 1)" != "$latest" ]; then
        echo "$variant: pinned $current is newer than upstream $latest, skipping" >&2
        continue
    fi

    sha=$(gh release download "$tag" -R "$UPSTREAM_REPO" -p SHA256SUMS -O - |
        awk -v f="$asset" '$2 == f { print $1 }')
    if ! [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
        echo "$variant: no checksum for $asset in SHA256SUMS of $tag" >&2
        exit 1
    fi

    if [ "$latest" != "$current" ]; then
        echo "$variant: $current -> $latest ($tag)" >&2
        changes+=("$variant $latest")
    elif [ "$sha" != "$current_sha" ]; then
        echo "$variant: $current package re-uploaded upstream ($sha)" >&2
        changes+=("$variant $latest (rebuilt package)")
    else
        echo "$variant: up to date ($current)" >&2
        continue
    fi

    updated=$(jq --arg v "$variant" --arg version "$latest" --arg tag "$tag" --arg sha "$sha" \
        'map(if .variant == $v then .version = $version | .release_tag = $tag | .sha256 = $sha else . end)' \
        "$VERSIONS")
    printf '%s\n' "$updated" >"$VERSIONS"
done

if [ "${#changes[@]}" -gt 0 ]; then
    title=$(printf '%s, ' "${changes[@]}")
    echo "title=Checkmk: ${title%, }"
fi
