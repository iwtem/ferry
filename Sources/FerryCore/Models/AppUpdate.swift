import Foundation

/// Semantic version (`major.minor.patch` with optional prerelease tag), used to compare installed vs. GitHub Release versions.
public struct SemanticVersion: Codable, Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int = 0, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease?.isEmpty == true ? nil : prerelease
    }

    public init?(parsing raw: String) {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        // Strip build metadata (+...)
        if let plusIndex = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIndex])
        }

        let mainPart: String
        let prereleasePart: String?
        if let dashIndex = cleaned.firstIndex(of: "-") {
            mainPart = String(cleaned[..<dashIndex])
            let tail = String(cleaned[cleaned.index(after: dashIndex)...])
            prereleasePart = tail.isEmpty ? nil : tail
        } else {
            mainPart = cleaned
            prereleasePart = nil
        }

        let parts = mainPart.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        guard let major = Int(parts[0]), major >= 0 else { return nil }
        let minor = parts.count >= 2 ? Int(parts[1]) : 0
        let patch = parts.count == 3 ? Int(parts[2]) : 0
        guard let minor, minor >= 0, let patch, patch >= 0 else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prereleasePart
    }

    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        if let prerelease {
            return "\(base)-\(prerelease)"
        }
        return base
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, .some):
            return false // Stable > prerelease
        case (.some, nil):
            return true // Prerelease < stable
        case (.some(let l), .some(let r)):
            return l.localizedStandardCompare(r) == .orderedAscending
        }
    }
}

/// Metadata for a downloadable macOS app release from GitHub Releases.
public struct ReleaseInfo: Codable, Equatable, Sendable {
    public let version: SemanticVersion
    public let tagName: String
    public let name: String
    public let releaseNotes: String
    public let htmlURL: URL
    public let downloadURL: URL
    public let assetFileName: String
    public let assetSize: Int64
    public let sha256: String?
    public let checksumURL: URL?
    public let publishedAt: Date?

    public init(
        version: SemanticVersion,
        tagName: String,
        name: String,
        releaseNotes: String,
        htmlURL: URL,
        downloadURL: URL,
        assetFileName: String,
        assetSize: Int64,
        sha256: String? = nil,
        checksumURL: URL? = nil,
        publishedAt: Date? = nil
    ) {
        self.version = version
        self.tagName = tagName
        self.name = name
        self.releaseNotes = releaseNotes
        self.htmlURL = htmlURL
        self.downloadURL = downloadURL
        self.assetFileName = assetFileName
        self.assetSize = assetSize
        self.sha256 = sha256
        self.checksumURL = checksumURL
        self.publishedAt = publishedAt
    }
}

public enum AppUpdateError: LocalizedError, Equatable, Sendable {
    case invalidEndpoint
    case noReleasePublished
    case noDownloadableAsset
    case invalidResponse
    case httpError(Int)
    case networkError(String)
    case checksumMismatch
    case requiresAppBundle
    case bundleIdentifierMismatch
    case extractionFailed(String)
    case installationFailed(String)

    public var errorDescription: String? {
        let lang = FerryLocalization.resolved
        switch self {
        case .invalidEndpoint:
            return FerryLocalization.text(zh: "更新服务地址无效。", en: "Invalid update feed URL.", in: lang)
        case .noReleasePublished:
            return FerryLocalization.text(zh: "仓库暂未发布任何 Release 版本。", en: "No GitHub Release has been published yet.", in: lang)
        case .noDownloadableAsset:
            return FerryLocalization.text(zh: "最新 Release 中未找到可安装的 .zip 应用包。", en: "No downloadable .zip app archive found in the latest release.", in: lang)
        case .invalidResponse:
            return FerryLocalization.text(zh: "无法解析更新服务器返回的数据。", en: "Could not parse the update server response.", in: lang)
        case .httpError(let status):
            if status == 404 {
                return FerryLocalization.text(
                    zh: "未找到公开的 Release（HTTP 404）。如尚未发版或仓库为私有，请先发布公开 Release。",
                    en: "No public release found (HTTP 404). Publish a public GitHub Release first.",
                    in: lang
                )
            }
            if status == 403 || status == 429 {
                return FerryLocalization.text(
                    zh: "GitHub API 请求受限（HTTP \(status)），请稍后再试。",
                    en: "GitHub API rate limit reached (HTTP \(status)). Try again later.",
                    in: lang
                )
            }
            return FerryLocalization.text(
                zh: "检查更新失败（HTTP \(status)）。",
                en: "Update check failed (HTTP \(status)).",
                in: lang
            )
        case .networkError(let message):
            return FerryLocalization.text(zh: "网络错误：\(message)", en: "Network error: \(message)", in: lang)
        case .checksumMismatch:
            return FerryLocalization.text(
                zh: "安装包 SHA-256 校验失败，已自动清理，请重试下载。",
                en: "Downloaded archive failed SHA-256 verification and was removed. Please try again.",
                in: lang
            )
        case .requiresAppBundle:
            return FerryLocalization.text(
                zh: "当前不是从 Ferry.app 运行，请从 Applications 中的 Ferry.app 启动后再自动更新。",
                en: "Auto-install only works when running from Ferry.app.",
                in: lang
            )
        case .bundleIdentifierMismatch:
            return FerryLocalization.text(
                zh: "下载的应用包标识与 Ferry 不匹配，已中止安装。",
                en: "Downloaded app bundle identifier does not match Ferry. Installation aborted.",
                in: lang
            )
        case .extractionFailed(let detail):
            return FerryLocalization.text(zh: "解压更新包失败：\(detail)", en: "Failed to extract update archive: \(detail)", in: lang)
        case .installationFailed(let detail):
            return FerryLocalization.text(zh: "安装更新失败：\(detail)", en: "Failed to install update: \(detail)", in: lang)
        }
    }
}

/// Parses GitHub Releases API JSON payloads and SHA-256 checksum text into `ReleaseInfo`.
public enum UpdateFeedParser {
    private struct GitHubReleasePayload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String
            let size: Int64?
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
                case digest
            }
        }

        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String
        let draft: Bool?
        let prerelease: Bool?
        let publishedAt: String?
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case draft
            case prerelease
            case publishedAt = "published_at"
            case assets
        }
    }

    public static func latestReleaseEndpoint(for repository: String) -> URL? {
        let trimmed = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("/") else { return nil }
        return URL(string: "https://api.github.com/repos/\(trimmed)/releases/latest")
    }

    public static func parseLatestRelease(from data: Data) throws -> ReleaseInfo {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(GitHubReleasePayload.self, from: data) else {
            throw AppUpdateError.invalidResponse
        }
        guard payload.draft != true else {
            throw AppUpdateError.noReleasePublished
        }
        guard let version = SemanticVersion(parsing: payload.tagName),
              let htmlURL = URL(string: payload.htmlURL)
        else {
            throw AppUpdateError.invalidResponse
        }

        let assets = payload.assets ?? []
        // Prefer an archive specifically named Ferry*.zip, otherwise fall back to the first .zip asset.
        let zipAsset = assets.first(where: {
            let lower = $0.name.lowercased()
            return lower.hasPrefix("ferry") && lower.hasSuffix(".zip")
        }) ?? assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })

        guard let zipAsset, let downloadURL = URL(string: zipAsset.browserDownloadURL) else {
            throw AppUpdateError.noDownloadableAsset
        }

        // Companion .sha256 asset (e.g. Ferry-0.2.0.zip.sha256)
        let checksumAsset = assets.first(where: {
            let lower = $0.name.lowercased()
            return lower == zipAsset.name.lowercased() + ".sha256" || lower.hasSuffix(".sha256")
        })
        let checksumURL = checksumAsset.flatMap { URL(string: $0.browserDownloadURL) }

        // SHA-256 from GitHub's native asset `digest` field or embedded in release notes body
        let inlineSHA256 = parseSHA256(from: zipAsset.digest ?? "")
            ?? parseSHA256(from: payload.body ?? "")

        let publishedDate: Date?
        if let rawDate = payload.publishedAt {
            let iso = ISO8601DateFormatter()
            publishedDate = iso.date(from: rawDate)
        } else {
            publishedDate = nil
        }

        let title = (payload.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return ReleaseInfo(
            version: version,
            tagName: payload.tagName,
            name: title.isEmpty ? payload.tagName : title,
            releaseNotes: notes,
            htmlURL: htmlURL,
            downloadURL: downloadURL,
            assetFileName: zipAsset.name,
            assetSize: zipAsset.size ?? 0,
            sha256: inlineSHA256,
            checksumURL: checksumURL,
            publishedAt: publishedDate
        )
    }

    /// Extracts a 64-character hex SHA-256 digest from strings such as:
    /// - `"sha256:e3b0c442..."` (GitHub API asset `digest`)
    /// - `"e3b0c442...  Ferry-0.2.0.zip"` (`shasum -a 256` output)
    /// - `"SHA-256: `e3b0c442...`"` (Release notes)
    public static func parseSHA256(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let pattern = #"(?i)\b([0-9a-f]{64})\b"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(text[range]).lowercased()
    }
}

/// Parsed event emitted by a lightweight SSE release push stream (such as `ntfy.sh` or a custom worker).
/// Push messages are strictly wake-up hints; downloads are always fetched & verified from GitHub Releases.
public enum UpdatePushEvent: Equatable, Sendable {
    case connected
    case keepalive
    case releaseAvailable(versionHint: SemanticVersion?)
    case ignore
}

/// Parses SSE lines from `ntfy.sh` JSON events or custom JSON/plain-text version announcements.
public enum UpdatePushParser {
    public static let defaultPushEndpoint = "https://ntfy.sh/ferry-releases-iwtem-v1/sse"

    private struct NtfyPayload: Decodable {
        let event: String?
        let message: String?
        let version: String?
        let tag: String?
    }

    public static func parseSSELine(_ line: String) -> UpdatePushEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return .ignore }
        guard trimmed.hasPrefix("data:") else { return .ignore }

        let payloadText = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payloadText.isEmpty else { return .ignore }

        if let data = payloadText.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(NtfyPayload.self, from: data) {
            if let event = decoded.event?.lowercased() {
                switch event {
                case "open":
                    return .connected
                case "keepalive":
                    return .keepalive
                case "message":
                    let candidate = decoded.version ?? decoded.tag ?? decoded.message ?? ""
                    return .releaseAvailable(versionHint: extractVersion(from: candidate))
                default:
                    return .ignore
                }
            }
            if let explicit = decoded.version ?? decoded.tag ?? decoded.message {
                return .releaseAvailable(versionHint: extractVersion(from: explicit))
            }
            return .ignore
        }

        // Plain-text fallback (e.g. `data: v0.2.1` or `data: check`)
        return .releaseAvailable(versionHint: extractVersion(from: payloadText))
    }

    public static func extractVersion(from text: String) -> SemanticVersion? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = SemanticVersion(parsing: trimmed) {
            return direct
        }
        let pattern = #"(?i)v?(\d+\.\d+(?:\.\d+)?(?:-[0-9a-zA-Z\.]+)?)"#
        guard let range = trimmed.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return SemanticVersion(parsing: String(trimmed[range]))
    }
}
