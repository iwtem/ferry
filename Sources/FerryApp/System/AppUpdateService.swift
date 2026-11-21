import AppKit
import CryptoKit
import FerryCore
import Foundation
import Observation

/// Lifecycle state of the in-app GitHub Releases updater.
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(ReleaseInfo)
    case downloading(ReleaseInfo, progress: Double)
    case readyToInstall(ReleaseInfo, archivePath: String)
    case installing(ReleaseInfo)
    case failed(String)

    public var release: ReleaseInfo? {
        switch self {
        case .available(let r),
             .downloading(let r, _),
             .readyToInstall(let r, _),
             .installing(let r):
            return r
        default:
            return nil
        }
    }

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    public var isReadyToInstall: Bool {
        if case .readyToInstall = self { return true }
        return false
    }
}

/// Native GitHub Releases auto-updater: checks for new releases, auto-downloads in the background,
/// verifies SHA-256 integrity, and atomically replaces & relaunches `Ferry.app` on user click.
@MainActor
@Observable
public final class AppUpdateService {
    public var state: UpdateState = .idle
    public var lastCheckedAt: Date? = nil
    public var isBannerDismissed: Bool = false

    public let repository: String
    public let currentVersionString: String
    public let currentVersion: SemanticVersion

    private weak var settingsStore: SettingsStore?
    private var activeTask: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?
    private let session: URLSession

    private static let checkInterval: Duration = .seconds(12 * 60 * 60)
    private static let initialDelay: Duration = .seconds(8)

    public init(
        repository: String? = nil,
        currentVersionString: String? = nil,
        session: URLSession = .shared
    ) {
        let info = Bundle.main.infoDictionary
        self.repository = repository
            ?? (info?["FerryGitHubRepo"] as? String)
            ?? "iwtem/ferry"
        let rawVersion = currentVersionString
            ?? (info?["CFBundleShortVersionString"] as? String)
            ?? "0.1.0"
        self.currentVersionString = rawVersion
        self.currentVersion = SemanticVersion(parsing: rawVersion) ?? SemanticVersion(major: 0, minor: 1, patch: 0)
        self.session = session
    }

    public var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// True when a compact update banner should be surfaced in Popover / Main Window.
    public var shouldShowUpdateBanner: Bool {
        guard !isBannerDismissed else { return false }
        switch state {
        case .available, .downloading, .readyToInstall:
            return true
        default:
            return false
        }
    }

    public func start(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            try? await Task.sleep(for: Self.initialDelay)
            while !Task.isCancelled {
                guard let self else { return }
                if self.settingsStore?.settings.autoCheckForUpdates == true, !self.state.isBusy {
                    await self.performCheck(userInitiated: false)
                }
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    public func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
        activeTask?.cancel()
        activeTask = nil
    }

    public func checkForUpdates(userInitiated: Bool = true) {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.performCheck(userInitiated: userInitiated)
        }
    }

    public func downloadUpdate() {
        guard case .available(let release) = state else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.performDownload(release: release, userInitiated: true)
        }
    }

    public func skipCurrentUpdate() {
        guard let release = state.release else { return }
        settingsStore?.settings.skippedUpdateVersion = release.version.description
        isBannerDismissed = true
        state = .idle
    }

    public func dismissBanner() {
        isBannerDismissed = true
    }

    public func openReleasePage() {
        if let url = state.release?.htmlURL {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "https://github.com/\(repository)/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Extracts the verified archive, spawns a detached swap-and-relaunch script, and terminates Ferry.
    public func installAndRelaunch() {
        guard case .readyToInstall(let release, let archivePath) = state else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.performInstallAndRelaunch(release: release, archivePath: archivePath)
        }
    }

    // MARK: - Check

    private func performCheck(userInitiated: Bool) async {
        guard let endpoint = UpdateFeedParser.latestReleaseEndpoint(for: repository) else {
            if userInitiated {
                state = .failed(AppUpdateError.invalidEndpoint.localizedDescription)
            }
            return
        }

        if userInitiated || !state.isReadyToInstall {
            state = .checking
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ferry/\(currentVersionString)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled else { return }

            guard let http = response as? HTTPURLResponse else {
                throw AppUpdateError.invalidResponse
            }
            if http.statusCode == 404 {
                throw AppUpdateError.httpError(404)
            }
            guard (200...299).contains(http.statusCode) else {
                throw AppUpdateError.httpError(http.statusCode)
            }

            let release = try UpdateFeedParser.parseLatestRelease(from: data)
            lastCheckedAt = Date()

            guard release.version > currentVersion else {
                if userInitiated {
                    state = .upToDate(currentVersion: currentVersionString)
                } else {
                    state = .idle
                }
                return
            }

            if !userInitiated && settingsStore?.settings.skippedUpdateVersion == release.version.description {
                state = .idle
                return
            }

            if userInitiated && settingsStore?.settings.skippedUpdateVersion == release.version.description {
                settingsStore?.settings.skippedUpdateVersion = nil
            }

            isBannerDismissed = false

            // Check if a verified copy is already cached locally.
            let expectedSHA = await resolveExpectedSHA256(for: release)
            let cachedURL = cachedArchiveURL(for: release)
            if FileManager.default.fileExists(atPath: cachedURL.path),
               await Self.verifyCachedArchive(at: cachedURL, expectedSHA256: expectedSHA, expectedSize: release.assetSize) {
                state = .readyToInstall(release, archivePath: cachedURL.path)
                return
            }

            if settingsStore?.settings.autoDownloadUpdates == true {
                await performDownload(release: release, preResolvedSHA256: expectedSHA, userInitiated: userInitiated)
            } else {
                state = .available(release)
            }
        } catch is CancellationError {
            return
        } catch let updateError as AppUpdateError {
            if userInitiated {
                state = .failed(updateError.localizedDescription)
            } else {
                state = .idle
            }
        } catch {
            if userInitiated {
                state = .failed(AppUpdateError.networkError(error.localizedDescription).localizedDescription)
            } else {
                state = .idle
            }
        }
    }

    // MARK: - Download & Verify

    private func performDownload(
        release: ReleaseInfo,
        preResolvedSHA256: String? = nil,
        userInitiated: Bool
    ) async {
        state = .downloading(release, progress: 0)

        let expectedSHA: String?
        if let preResolvedSHA256 {
            expectedSHA = preResolvedSHA256
        } else {
            expectedSHA = await resolveExpectedSHA256(for: release)
        }

        let cacheDir = updatesCacheDirectory()
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let destinationURL = cachedArchiveURL(for: release)
        let partURL = destinationURL.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partURL)

        var request = URLRequest(url: release.downloadURL)
        request.timeoutInterval = 180
        request.setValue("Ferry/\(currentVersionString)", forHTTPHeaderField: "User-Agent")

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw AppUpdateError.httpError(code)
            }

            let expectedLength = http.expectedContentLength > 0 ? http.expectedContentLength : release.assetSize
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: partURL)
            defer { try? handle.close() }

            var hasher = SHA256()
            var receivedBytes: Int64 = 0
            var lastReportedProgress: Double = 0
            var chunk = Data()
            let bufferCapacity = 65_536
            chunk.reserveCapacity(bufferCapacity)

            for try await byte in bytes {
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: partURL)
                    return
                }
                chunk.append(byte)
                if chunk.count >= bufferCapacity {
                    try handle.write(contentsOf: chunk)
                    hasher.update(data: chunk)
                    receivedBytes += Int64(chunk.count)
                    chunk.removeAll(keepingCapacity: true)

                    if expectedLength > 0 {
                        let progress = min(Double(receivedBytes) / Double(expectedLength), 0.99)
                        if progress - lastReportedProgress >= 0.02 {
                            lastReportedProgress = progress
                            state = .downloading(release, progress: progress)
                        }
                    }
                }
            }

            if !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
                hasher.update(data: chunk)
                receivedBytes += Int64(chunk.count)
            }

            try handle.synchronize()
            try handle.close()

            let actualSHA256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            if let expectedSHA, actualSHA256.lowercased() != expectedSHA.lowercased() {
                try? FileManager.default.removeItem(at: partURL)
                throw AppUpdateError.checksumMismatch
            }

            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: partURL, to: destinationURL)

            state = .readyToInstall(release, archivePath: destinationURL.path)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: partURL)
            return
        } catch let updateError as AppUpdateError {
            try? FileManager.default.removeItem(at: partURL)
            if userInitiated {
                state = .failed(updateError.localizedDescription)
            } else {
                state = .available(release)
            }
        } catch {
            try? FileManager.default.removeItem(at: partURL)
            if userInitiated {
                state = .failed(AppUpdateError.networkError(error.localizedDescription).localizedDescription)
            } else {
                state = .available(release)
            }
        }
    }

    private func resolveExpectedSHA256(for release: ReleaseInfo) async -> String? {
        if let inline = release.sha256 {
            return inline
        }
        guard let checksumURL = release.checksumURL else { return nil }
        var req = URLRequest(url: checksumURL)
        req.timeoutInterval = 15
        req.setValue("Ferry/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return UpdateFeedParser.parseSHA256(from: text)
    }

    // MARK: - Extract, Verify & Atomic Replace + Relaunch

    private func performInstallAndRelaunch(release: ReleaseInfo, archivePath: String) async {
        guard isRunningFromAppBundle else {
            state = .failed(AppUpdateError.requiresAppBundle.localizedDescription)
            return
        }

        state = .installing(release)

        let targetAppURL = Bundle.main.bundleURL.standardizedFileURL
        let expectedBundleID = Bundle.main.bundleIdentifier ?? "com.iwtem.Ferry"
        let stagingDir = updatesCacheDirectory()
            .appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            // 1. Extract archive preserving macOS bundle metadata and signatures
            let extractStatus = try await Self.runProcess(
                executable: "/usr/bin/ditto",
                arguments: ["-x", "-k", archivePath, stagingDir.path]
            )
            guard extractStatus == 0 else {
                throw AppUpdateError.extractionFailed("ditto exit \(extractStatus)")
            }

            // 2. Locate extracted .app bundle
            let stagedAppURL = try Self.findAppBundle(in: stagingDir)

            // 3. Validate bundle identifier matches Ferry
            let plistURL = stagedAppURL.appendingPathComponent("Contents/Info.plist")
            guard let plistData = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                  let stagedBundleID = plist["CFBundleIdentifier"] as? String,
                  stagedBundleID == expectedBundleID
            else {
                throw AppUpdateError.bundleIdentifierMismatch
            }

            // 4. Verify parent directory is writable before quitting
            let parentDir = targetAppURL.deletingLastPathComponent()
            guard FileManager.default.isWritableFile(atPath: parentDir.path) else {
                throw AppUpdateError.installationFailed(
                    FerryLocalization.text(
                        zh: "没有权限写入 \(parentDir.path)",
                        en: "No write permission for \(parentDir.path)"
                    )
                )
            }

            // 5. Write & spawn detached atomic replacement script, then quit Ferry
            let scriptURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ferry-apply-update-\(UUID().uuidString).sh")
            try Self.updaterScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                scriptURL.path,
                String(ProcessInfo.processInfo.processIdentifier),
                stagedAppURL.path,
                targetAppURL.path,
                stagingDir.path,
                archivePath
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()

            // Give the helper process a moment to initialize before terminating
            try? await Task.sleep(for: .milliseconds(150))
            NSApp.terminate(nil)
        } catch let updateError as AppUpdateError {
            try? FileManager.default.removeItem(at: stagingDir)
            state = .failed(updateError.localizedDescription)
        } catch {
            try? FileManager.default.removeItem(at: stagingDir)
            state = .failed(AppUpdateError.installationFailed(error.localizedDescription).localizedDescription)
        }
    }

    // MARK: - Helpers

    private func updatesCacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches
            .appendingPathComponent("com.iwtem.Ferry", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    private func cachedArchiveURL(for release: ReleaseInfo) -> URL {
        updatesCacheDirectory().appendingPathComponent("Ferry-\(release.version.description).zip")
    }

    private static func verifyCachedArchive(
        at url: URL,
        expectedSHA256: String?,
        expectedSize: Int64
    ) async -> Bool {
        await Task.detached(priority: .utility) {
            if let expectedSHA256 {
                guard let actual = Self.sha256Hex(ofFileAt: url) else { return false }
                return actual.lowercased() == expectedSHA256.lowercased()
            }
            if expectedSize > 0,
               let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attrs[.size] as? Int64 {
                return fileSize == expectedSize
            }
            return false
        }.value
    }

    private nonisolated static func sha256Hex(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try? handle.read(upToCount: 65_536), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func findAppBundle(in directory: URL) throws -> URL {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        if let direct = contents.first(where: { $0.pathExtension == "app" }) {
            return direct
        }
        // Check one directory level deeper in case zip wrapped the bundle inside a folder
        for subdir in contents {
            let nested = (try? fm.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil)) ?? []
            if let found = nested.first(where: { $0.pathExtension == "app" }) {
                return found
            }
        }
        throw AppUpdateError.extractionFailed("No .app bundle found in archive")
    }

    private static func runProcess(executable: String, arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Detached POSIX shell script that waits for the old Ferry PID to quit, atomically swaps
    /// the `.app` bundle with automatic rollback on failure, clears quarantine, cleans up, and relaunches.
    private static let updaterScript = #"""
#!/bin/sh
set -eu

OLD_PID="$1"
STAGED_APP="$2"
TARGET_APP="$3"
STAGING_DIR="$4"
ARCHIVE_PATH="$5"
SELF_SCRIPT="$0"
BACKUP_APP="${TARGET_APP}.previous-$$"

cleanup() {
    rm -rf "$STAGING_DIR" "$SELF_SCRIPT" 2>/dev/null || true
}
trap cleanup EXIT

# Wait up to 15 seconds for the running Ferry process to exit cleanly
i=0
while [ "$i" -lt 75 ]; do
    if ! kill -0 "$OLD_PID" 2>/dev/null; then
        break
    fi
    sleep 0.2
    i=$((i + 1))
done

rm -rf "$BACKUP_APP" 2>/dev/null || true
if [ -d "$TARGET_APP" ]; then
    mv "$TARGET_APP" "$BACKUP_APP"
fi

if mv "$STAGED_APP" "$TARGET_APP" 2>/dev/null || /usr/bin/ditto "$STAGED_APP" "$TARGET_APP"; then
    rm -rf "$BACKUP_APP" "$ARCHIVE_PATH" 2>/dev/null || true
    /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
    /usr/bin/open -n "$TARGET_APP"
else
    # Roll back to previous working app bundle on any copy/move failure
    if [ -d "$BACKUP_APP" ]; then
        rm -rf "$TARGET_APP" 2>/dev/null || true
        mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
    fi
    exit 1
fi
"""#
}
