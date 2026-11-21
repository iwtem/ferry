# AGENTS.md — 渡 Ferry Project Guide

This repository contains **渡 Ferry**, a lightweight native macOS menu-bar LLM translator built with **Swift 6 + SwiftUI + AppKit** via pure Swift Package Manager (no Xcode project, zero third-party dependencies, macOS 14+).

Follow these conventions when developing, testing, or releasing changes.

---

## 1. Architecture & Directory Layout

- `Sources/FerryCore/` — Platform-light models & services (prompts, SSE streaming, Vision OCR + layout formatter, PDF line-break preprocessor, hotkey/update models, persistence). Keep business logic here so it stays unit-testable.
- `Sources/FerryApp/` — macOS UI views (`SwiftUI`), AppKit window/panel controllers, global monitors/hotkeys, speech, screen capture, text replacement, and in-app updater.
- `Sources/Ferry/` — Executable entry point (`main.swift`).
- `Tests/FerryCoreTests/` — Swift Testing suite covering `FerryCore`.
- `Scripts/` — Build, local deploy, and GitHub Release scripts.
- `VERSION` — Single source of truth for `CFBundleShortVersionString` (e.g. `0.2.3`).
- `docs/ROADMAP.md` — Product roadmap & milestone checklist.

---

## 2. Hard Project Rules & Gotchas

1. **Use `@ViewState` instead of `@State`**
   - See `Sources/FerryApp/Views/Components/ViewState.swift`. Command Line Tools builds do not ship the SwiftUI `@State` macro plugin, so always use `@ViewState` inside SwiftUI views.
2. **Bilingual Localization (Required for all UI & Errors)**
   - Every user-facing string must provide both Simplified Chinese (`zhHans`) and English (`en`):
     - `FerryApp` UI strings → `Sources/FerryApp/Localization/L10n.swift`
     - `FerryCore` model display names & `LocalizedError` → `FerryLocalization.text(zh:en:in:)`
3. **Backward-Compatible Persistence**
   - `AppSettings`, `ProviderProfile`, and `TranslationRecord` are persisted in `~/Library/Application Support/Ferry/`.
   - Any newly added `Codable` property **must** use `decodeIfPresent(...) ?? default` in `init(from:)` AND have a legacy decoding assertion in `Tests/FerryCoreTests/FerryCoreTests.swift`.
4. **Code Signing & macOS TCC Permissions (Critical)**
   - Always build `.app` bundles via `./Scripts/build_app.sh`, which signs with the stable project-local certificate `"Ferry Local Signing"` in `.signing/ferry-signing.keychain-db`.
   - **Never delete `.signing/` or switch to ad-hoc signing** — changing the code signature breaks macOS **Accessibility** (Double `⌘C`, `⌥⇧R`, Replace) and **Screen Recording** (`⌥⇧S` OCR) grants after an update.
5. **Public Repository Hygiene**
   - `iwtem/ferry` is a **public** repository. Never commit `.signing/`, `dist/`, `.build/`, personal API keys, or tokens.

---

## 3. Build, Test & Visual Verification

### Run Unit Tests
```bash
swift test
# If using macOS Command Line Tools without Xcode:
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

### Visual UI Snapshot Check (Required for UI Changes)
Ferry includes a built-in headless snapshot renderer (`Sources/FerryApp/System/UISnapshot.swift`):
```bash
swift build
.build/debug/Ferry --ui-snapshot /tmp/ferry-ui-en --lang en
.build/debug/Ferry --ui-snapshot /tmp/ferry-ui-zh --lang zh
```
Inspect the generated `main-light.png`, `main-dark.png`, `popover-light.png`, and `settings-*.png` images in both English and Chinese before releasing UI changes.

### Local Development Hot-Reload (Do Not Use for Releases)
Builds, signs, quits the running Ferry, replaces `/Applications/Ferry.app`, and relaunches:
```bash
./Scripts/deploy_local.sh
```

---

## 4. Standard Release & Real-Time Push Workflow

Ferry has a built-in GitHub Releases auto-updater (`AppUpdateService`) with:
- Real-time SSE push notifications (`https://ntfy.sh/ferry-releases-iwtem-v1/sse`)
- ETag conditional polling fallback (`304` does not consume GitHub API quota)
- Automatic background download + SHA-256 verification + atomic `.app` swap & relaunch

When the user asks to **release / publish a new version** so installed Ferry apps receive an automatic update, follow this exact order:

1. **Verify before packaging**
   - Run unit tests (`swift test`) and UI snapshots (if UI changed).
   - Update `docs/ROADMAP.md` (check off completed items) and `README.md` if user-facing features changed.
2. **Bump `VERSION` and build signed release artifacts**
   ```bash
   ./Scripts/release.sh <x.y.z>
   ```
   This updates `VERSION`, builds release binary, signs `dist/Ferry.app` with `"Ferry Local Signing"`, and creates:
   - `dist/Ferry-<x.y.z>.zip`
   - `dist/Ferry-<x.y.z>.zip.sha256`
   Note the printed `SHA-256` digest.
   *(Do **not** run `./Scripts/deploy_local.sh` if the user wants to test receiving the update in-app on their currently installed version.)*
3. **Commit and push `main` BEFORE creating the GitHub Release**
   *(Ensures git tag `v<x.y.z>` points to the exact release commit including the updated `VERSION` file.)*
   ```bash
   git add -A
   git commit -m "Release v<x.y.z>: <concise summary>"
   git push origin main
   ```
4. **Publish GitHub Release `v<x.y.z>`**
   Upload **both** the `.zip` and `.sha256` assets, and include the `SHA-256` hash in the release notes:
   ```bash
   gh release create v<x.y.z> \
     dist/Ferry-<x.y.z>.zip \
     dist/Ferry-<x.y.z>.zip.sha256 \
     --title "渡 Ferry v<x.y.z>" \
     --notes "<release notes>\n\nSHA-256: \`<sha256>\`"
   ```
5. **Broadcast Real-Time SSE Update Push**
   Immediately notify all online Ferry clients to check GitHub Releases and start background download:
   ```bash
   curl -fsSL -X POST \
     -H "Title: Ferry v<x.y.z>" \
     -d "<x.y.z>" \
     https://ntfy.sh/ferry-releases-iwtem-v1
   ```
   *(Security note: the SSE message is only a wake-up signal; clients always verify version, download exclusively from `https://api.github.com/repos/iwtem/ferry/releases/latest`, check SHA-256, and verify `CFBundleIdentifier == com.iwtem.Ferry`.)*
