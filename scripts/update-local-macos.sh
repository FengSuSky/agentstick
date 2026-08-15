#!/bin/bash
# Build AgentStick (arm64) and swap the locally installed app in place:
#   1. Build a fresh release bundle (unless --skip-build).
#   2. Gracefully quit the running AgentStick (force-kill as a last resort).
#   3. Remove every /Applications/AgentStick*.app (versioned or plain names).
#   4. Install the new bundle and relaunch it.
#
# Usage: scripts/update-local-macos.sh [--skip-build] [--no-launch]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$ROOT_DIR/build"
INSTALL_DIR="/Applications"
BUNDLE_ID="app.agentstick.mac"
APP_PROCESS_PATTERN="AgentStick.*\.app/Contents/MacOS/AgentStickApp"

SKIP_BUILD=0
LAUNCH=1
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=1 ;;
        --no-launch) LAUNCH=0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [ "$SKIP_BUILD" -eq 0 ]; then
    echo "==> Building AgentStick (arm64 release)..."
    AGENTSTICK_TARGET_ARCHS="${AGENTSTICK_TARGET_ARCHS:-arm64}" "$SCRIPT_DIR/build-macos.sh" --release
fi

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_NAME="AgentStick-${VERSION}.app"
SRC_APP="$BUILD_DIR/$APP_NAME"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"

if [ ! -d "$SRC_APP" ]; then
    echo "ERROR: built app not found at $SRC_APP (run without --skip-build first)" >&2
    exit 1
fi

echo "==> Quitting running AgentStick..."
if pgrep -f "$APP_PROCESS_PATTERN" >/dev/null 2>&1; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 50); do
        pgrep -f "$APP_PROCESS_PATTERN" >/dev/null 2>&1 || break
        sleep 0.2
    done
    if pgrep -f "$APP_PROCESS_PATTERN" >/dev/null 2>&1; then
        echo "    still running, sending TERM..."
        pkill -TERM -f "$APP_PROCESS_PATTERN" || true
        sleep 2
    fi
    if pgrep -f "$APP_PROCESS_PATTERN" >/dev/null 2>&1; then
        echo "    refusing to die, sending KILL..."
        pkill -KILL -f "$APP_PROCESS_PATTERN" || true
        sleep 1
    fi
    pgrep -f "$APP_PROCESS_PATTERN" >/dev/null 2>&1 && {
        echo "ERROR: AgentStick is still running; aborting." >&2
        exit 1
    }
else
    echo "    not running."
fi

echo "==> Removing old installs..."
shopt -s nullglob
removed=0
for old in "$INSTALL_DIR"/AgentStick*.app; do
    echo "    rm $old"
    rm -rf "$old"
    removed=1
done
shopt -u nullglob
[ "$removed" -eq 0 ] && echo "    nothing to remove."

echo "==> Installing $SRC_APP -> $INSTALLED_APP"
ditto "$SRC_APP" "$INSTALLED_APP"
codesign --verify "$INSTALLED_APP"

if [ "$LAUNCH" -eq 1 ]; then
    echo "==> Launching AgentStick..."
    open "$INSTALLED_APP"
    echo "Done. AgentStick $VERSION installed and running."
else
    echo "Done. AgentStick $VERSION installed (not launched)."
fi
