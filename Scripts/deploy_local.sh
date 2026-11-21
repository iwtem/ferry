#!/usr/bin/env zsh
set -euo pipefail

# One-command local build, replace, and relaunch for development.
# Usage: ./Scripts/deploy_local.sh [/Applications/Ferry.app]

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_APP="${1:-/Applications/Ferry.app}"
TARGET_DIR="$(dirname "$TARGET_APP")"
STAGED_APP="$PROJECT_DIR/dist/Ferry.app"

"$PROJECT_DIR/Scripts/build_app.sh"

echo "==> Quitting running Ferry (if any)..."
osascript -e 'tell application id "com.iwtem.Ferry" to quit' 2>/dev/null || true

for _ in {1..20}; do
    if ! pgrep -x "Ferry" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

if pgrep -x "Ferry" >/dev/null 2>&1; then
    killall Ferry 2>/dev/null || true
    sleep 0.3
fi

echo "==> Installing into $TARGET_APP..."
mkdir -p "$TARGET_DIR"
BACKUP_APP="${TARGET_APP}.backup-$$"
rm -rf "$BACKUP_APP"

if [[ -d "$TARGET_APP" ]]; then
    mv "$TARGET_APP" "$BACKUP_APP"
fi

if ditto "$STAGED_APP" "$TARGET_APP"; then
    rm -rf "$BACKUP_APP"
    xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
else
    if [[ -d "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$TARGET_APP"
    fi
    echo "Error: failed to install $TARGET_APP" >&2
    exit 1
fi

echo "==> Relaunching $TARGET_APP..."
open -n "$TARGET_APP"
echo "==> Done!"
