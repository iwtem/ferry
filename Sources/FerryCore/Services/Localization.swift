import Foundation
import os

public extension Notification.Name {
    static let ferryLanguageDidChange = Notification.Name("Ferry.LanguageDidChange")
}

/// Thread-safe runtime localization helper shared by `FerryCore` and `FerryApp`.
/// SwiftUI views should additionally pass/read `ResolvedAppLanguage` through the view environment
/// so language switches re-render every open window immediately.
public enum FerryLocalization {
    private static let state = OSAllocatedUnfairLock<AppLanguage>(initialState: .system)

    public static var languageSetting: AppLanguage {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    public static var resolved: ResolvedAppLanguage {
        ResolvedAppLanguage.resolve(languageSetting)
    }

    public static func text(
        zh: String,
        en: String,
        in language: ResolvedAppLanguage? = nil
    ) -> String {
        switch language ?? resolved {
        case .zhHans: return zh
        case .en: return en
        }
    }
}
