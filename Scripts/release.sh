#!/usr/bin/env zsh
set -euo pipefail

# Packages a signed release zip + SHA-256 checksum for Ferry's in-app GitHub Releases auto-updater.
#
# Usage:
#   ./Scripts/release.sh 0.2.0
#   ./Scripts/release.sh 0.2.0 --publish
#   ./Scripts/release.sh 0.2.0 --publish --notes "Added Screenshot OCR & Auto-Update"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_ARG="${1:-}"
PUBLISH=false
NOTES=""

if [[ -z "$VERSION_ARG" || "$VERSION_ARG" == -* ]]; then
    echo "Usage: ./Scripts/release.sh <version> [--publish] [--notes \"...\"]" >&2
    echo "Example: ./Scripts/release.sh 0.2.0 --publish" >&2
    exit 1
fi
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --publish)
            PUBLISH=true
            shift
            ;;
        --notes)
            NOTES="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

CLEAN_VERSION="${VERSION_ARG#v}"
TAG="v$CLEAN_VERSION"
ZIP_NAME="Ferry-${CLEAN_VERSION}.zip"
ZIP_PATH="$PROJECT_DIR/dist/$ZIP_NAME"
SHA_PATH="$ZIP_PATH.sha256"

echo "$CLEAN_VERSION" > "$PROJECT_DIR/VERSION"
echo "==> Updated VERSION to $CLEAN_VERSION"

APP_VERSION="$CLEAN_VERSION" "$PROJECT_DIR/Scripts/build_app.sh"

echo "==> Creating release archive $ZIP_NAME..."
rm -f "$ZIP_PATH" "$SHA_PATH"
ditto -c -k --sequesterRsrc --keepParent "$PROJECT_DIR/dist/Ferry.app" "$ZIP_PATH"

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
printf "%s  %s\n" "$SHA256" "$ZIP_NAME" > "$SHA_PATH"

echo "==> Release artifacts ready:"
echo "    Archive : $ZIP_PATH"
echo "    SHA-256 : $SHA256"

if [[ "$PUBLISH" == true ]]; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "Error: GitHub CLI (gh) is not installed. Install with: brew install gh" >&2
        exit 1
    fi
    RELEASE_BODY="${NOTES:-Release $TAG}"
    RELEASE_BODY="${RELEASE_BODY}"$'\n\n'"SHA-256: \`$SHA256\`"
    echo "==> Publishing GitHub Release $TAG..."
    gh release create "$TAG" "$ZIP_PATH" "$SHA_PATH" \
        --title "渡 Ferry $TAG" \
        --notes "$RELEASE_BODY"
    echo "==> Published $TAG! Existing Ferry installations will now detect and auto-download it."
else
    echo ""
    echo "To publish to GitHub Releases so existing Ferry apps auto-update:"
    echo "    gh release create $TAG \"$ZIP_PATH\" \"$SHA_PATH\" --title \"渡 Ferry $TAG\" --notes \"SHA-256: $SHA256\""
fi
