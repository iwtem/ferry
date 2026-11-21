import AppKit
import CoreGraphics
import FerryCore
import Foundation
import ImageIO
import Observation

/// Result of an interactive screen selection capture.
public struct ScreenCaptureResult: @unchecked Sendable {
    public let cgImage: CGImage
    public let anchorPoint: NSPoint
}

/// Interactive region screen capture powered by macOS `/usr/sbin/screencapture`,
/// plus Screen Recording permission tracking and clipboard image extraction.
@MainActor
@Observable
public final class ScreenCaptureService {
    public var isCapturing: Bool = false
    public var hasScreenRecordingPermission: Bool = false

    private var activeAppObserver: NSObjectProtocol?

    public init() {
        self.hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        installObservers()
    }

    public func stopObserving() {
        if let activeAppObserver {
            NotificationCenter.default.removeObserver(activeAppObserver)
            self.activeAppObserver = nil
        }
    }

    public func refreshPermissionStatus() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    }

    public func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
        refreshPermissionStatus()
    }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Launches the native macOS interactive crosshair capture silently (`screencapture -i -x`).
    /// Returns `nil` when the user cancels with Esc or a capture is already running.
    public func captureInteractiveRegion() async throws -> ScreenCaptureResult? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer {
            isCapturing = false
            refreshPermissionStatus()
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ferry-ocr-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let exitStatus = try await runScreenCaptureProcess(outputPath: tempURL.path)
        let mouseLocation = NSEvent.mouseLocation

        // When the user presses Esc to cancel, screencapture exits without creating the output file.
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            if exitStatus != 0 && exitStatus != 1 {
                throw OCRError.captureFailed("exit \(exitStatus)")
            }
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: tempURL)
        } catch {
            throw OCRError.captureFailed(error.localizedDescription)
        }

        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw OCRError.invalidImage
        }

        return ScreenCaptureResult(cgImage: cgImage, anchorPoint: mouseLocation)
    }

    /// Extracts an image from the general pasteboard (for pasting screenshots directly into Ferry).
    public static func imageFromPasteboard(_ pasteboard: NSPasteboard = .general) -> CGImage? {
        if let pngData = pasteboard.data(forType: .png),
           let source = CGImageSourceCreateWithData(pngData as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let source = CGImageSourceCreateWithData(tiffData as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        if let nsImage = NSImage(pasteboard: pasteboard) {
            var rect = NSRect(origin: .zero, size: nsImage.size)
            return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return nil
    }

    private func runScreenCaptureProcess(outputPath: String) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", outputPath]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: OCRError.captureFailed(error.localizedDescription))
            }
        }
    }

    private func installObservers() {
        activeAppObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionStatus()
            }
        }
    }
}
