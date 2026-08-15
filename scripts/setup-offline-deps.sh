#!/bin/bash
# Set up local SwiftPM dependency mirrors so macOS builds work without GitHub
# access, without polluting Package.resolved.
#
# Why: build-macos.sh wipes the scratch dir each run, forcing a re-resolve.
# Without network that fails; pointing SwiftPM at bare mirrors of the shared
# SwiftPM cache fixes it. Mirror directory NAMES matter — SwiftPM derives the
# dependency identity from the mirror path, so they must be exactly "Sparkle"
# and "TOMLKit" (anything like "Sparkle-09d89c53" rewrites Package.resolved
# with a polluted identity).
#
# The mirror config is stored per-package in desktop/macos/.swiftpm/ (gitignored).
# When network is available again, remove it with:
#   swift package --package-path desktop/macos config unset-mirror \
#       --original "https://github.com/sparkle-project/Sparkle"
#   swift package --package-path desktop/macos config unset-mirror \
#       --original "https://github.com/LebJe/TOMLKit.git"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESKTOP_DIR="$SCRIPT_DIR/../desktop/macos"
DEPS_DIR="$HOME/.agentstick-deps"
SWIFTPM_CACHE="$HOME/Library/Caches/org.swift.swiftpm/repositories"

MIRROR_FOR=(
    "https://github.com/sparkle-project/Sparkle|Sparkle-09d89c53|Sparkle"
    "https://github.com/LebJe/TOMLKit.git|TOMLKit-4b412b01|TOMLKit"
)

mkdir -p "$DEPS_DIR"
for entry in "${MIRROR_FOR[@]}"; do
    IFS='|' read -r original cache_name mirror_name <<< "$entry"
    cache_repo="$SWIFTPM_CACHE/$cache_name"
    mirror_repo="$DEPS_DIR/$mirror_name"
    if [ ! -d "$cache_repo" ]; then
        echo "ERROR: SwiftPM cache repo missing: $cache_repo" >&2
        echo "       Build once with network access to populate the cache." >&2
        exit 1
    fi
    echo "==> Refreshing $mirror_repo from $cache_repo"
    rm -rf "$mirror_repo"
    git clone --quiet --bare "$cache_repo" "$mirror_repo"
    swift package --package-path "$DESKTOP_DIR" config set-mirror \
        --original "$original" --mirror "file://$mirror_repo"
done

echo "Done. Offline mirrors configured:"
find "$DEPS_DIR" -maxdepth 1 -type d -not -path "$DEPS_DIR" | sed 's/^/    /'
