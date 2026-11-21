#!/usr/bin/env zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Ferry"
BUNDLE_ID="com.iwtem.Ferry"
BUILD_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build --disable-sandbox -c release

BIN_PATH="$(swift build --disable-sandbox -c release --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: compiled binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Packaging $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Generate native macOS HIG squircle AppIcon.icns from Resources/AppIconMaster.png
# (regenerate the master with: swift Scripts/render_app_icon.swift Resources/AppIconMaster.png)
MASTER_ICON="$PROJECT_DIR/Resources/AppIconMaster.png"
if [[ ! -f "$MASTER_ICON" ]]; then
    echo "Error: master icon not found at $MASTER_ICON" >&2
    exit 1
fi

swift - "$MASTER_ICON" "$RESOURCES_DIR/AppIcon.icns" "$BUILD_DIR/AppIconPreview.png" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

let masterPath = CommandLine.arguments[1]
let outputICNSPath = CommandLine.arguments[2]
let previewPNGPath = CommandLine.arguments[3]

guard let masterImage = NSImage(contentsOfFile: masterPath) else {
    fputs("Failed to load master icon at \(masterPath)\n", stderr)
    exit(1)
}

func renderSquircleIconPNG(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = NSSize(width: pixelSize, height: pixelSize)
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(pixelSize)
    // Apple macOS HIG icon grid: 824x824 squircle inside 1024x1024 canvas (~9.76% margin)
    let margin = s * 0.0976
    let innerRect = NSRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let cornerRadius = innerRect.width * 0.2237
    let squirclePath = NSBezierPath(roundedRect: innerRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Subtle Apple-style soft drop shadow under the squircle (inset 1.5px to avoid dark edge halo)
    ctx.saveGraphicsState()
    let shadowInset = max(1.0, s * 0.004)
    let shadowRect = innerRect.insetBy(dx: shadowInset, dy: shadowInset)
    let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: cornerRadius - shadowInset, yRadius: cornerRadius - shadowInset)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.018)
    shadow.shadowBlurRadius = s * 0.032
    shadow.set()
    NSColor.black.setFill()
    shadowPath.fill()
    ctx.restoreGraphicsState()

    // Clip to squircle and draw master artwork slightly zoomed (3%) to keep motif bold and crisp
    ctx.saveGraphicsState()
    squirclePath.addClip()
    let zoomInset = -innerRect.width * 0.03
    let drawRect = innerRect.insetBy(dx: zoomInset, dy: zoomInset)
    masterImage.draw(
        in: drawRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
    ctx.restoreGraphicsState()

    // Delicate inner glass rim highlight
    ctx.saveGraphicsState()
    squirclePath.addClip()
    let rimPath = NSBezierPath(
        roundedRect: innerRect.insetBy(dx: max(0.5, s * 0.002), dy: max(0.5, s * 0.002)),
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    NSColor.white.withAlphaComponent(0.22).setStroke()
    rimPath.lineWidth = max(1.0, s * 0.004)
    rimPath.stroke()
    ctx.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

// Standard macOS PNG-backed ICNS chunk types
let entries: [(String, Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("ic11", 32),
    ("icp6", 64),
    ("ic12", 64),
    ("ic07", 128),
    ("ic13", 256),
    ("ic08", 256),
    ("ic14", 512),
    ("ic09", 512),
    ("ic10", 1024)
]

var chunks = Data()
var previewData: Data?
for (fourCC, px) in entries {
    guard let png = renderSquircleIconPNG(pixelSize: px) else { continue }
    if px == 512 && previewData == nil {
        previewData = png
    }
    var lengthBE = UInt32(8 + png.count).bigEndian
    chunks.append(contentsOf: fourCC.utf8)
    withUnsafeBytes(of: &lengthBE) { chunks.append(contentsOf: $0) }
    chunks.append(png)
}

var icns = Data()
icns.append(contentsOf: "icns".utf8)
var totalSizeBE = UInt32(8 + chunks.count).bigEndian
withUnsafeBytes(of: &totalSizeBE) { icns.append(contentsOf: $0) }
icns.append(chunks)

try icns.write(to: URL(fileURLWithPath: outputICNSPath))
if let previewData {
    try previewData.write(to: URL(fileURLWithPath: previewPNGPath))
}
SWIFT

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleAllowMixedLocalizations</key>
    <true/>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>渡 Ferry</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh_CN</string>
        <string>en</string>
    </array>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign with a stable local identity. Ad-hoc signatures change identity on every rebuild,
# which makes macOS drop the Accessibility grant (double ⌘C stops working). A self-signed
# certificate kept in a project-local keychain gives every build the same identity:
#   designated => identifier "com.iwtem.Ferry" and certificate leaf = H"…"
# The keychain lives in .signing/ (not the login keychain). Deleting it creates a new
# certificate on the next build, after which Accessibility must be granted once more.
SIGN_DIR="$PROJECT_DIR/.signing"
SIGN_KEYCHAIN="$SIGN_DIR/ferry-signing.keychain-db"
SIGN_KEYCHAIN_PASS="ferry-local-signing"
SIGN_IDENTITY="Ferry Local Signing"

if [[ ! -f "$SIGN_KEYCHAIN" ]]; then
    echo "==> Creating local signing identity \"$SIGN_IDENTITY\" in $SIGN_KEYCHAIN..."
    mkdir -p "$SIGN_DIR"
    chmod 700 "$SIGN_DIR"
    TMP_SIGN="$(mktemp -d)"
    cat > "$TMP_SIGN/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $SIGN_IDENTITY
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP_SIGN/cert.cnf" \
        -keyout "$TMP_SIGN/key.pem" -out "$TMP_SIGN/cert.pem" 2>/dev/null
    # Legacy PKCS#12 algorithms: the macOS keychain cannot import OpenSSL 3+/4 defaults.
    openssl pkcs12 -export -name "$SIGN_IDENTITY" -inkey "$TMP_SIGN/key.pem" -in "$TMP_SIGN/cert.pem" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -out "$TMP_SIGN/identity.p12" -passout pass:"$SIGN_KEYCHAIN_PASS"
    security create-keychain -p "$SIGN_KEYCHAIN_PASS" "$SIGN_KEYCHAIN"
    security unlock-keychain -p "$SIGN_KEYCHAIN_PASS" "$SIGN_KEYCHAIN"
    security import "$TMP_SIGN/identity.p12" -k "$SIGN_KEYCHAIN" -P "$SIGN_KEYCHAIN_PASS" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$SIGN_KEYCHAIN_PASS" "$SIGN_KEYCHAIN" >/dev/null
    rm -rf "$TMP_SIGN"
fi

echo "==> Code signing $APP_BUNDLE with \"$SIGN_IDENTITY\"..."
security unlock-keychain -p "$SIGN_KEYCHAIN_PASS" "$SIGN_KEYCHAIN"
codesign --force --deep --keychain "$SIGN_KEYCHAIN" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

echo "==> Done! App bundle created at:"
echo "    $APP_BUNDLE"
