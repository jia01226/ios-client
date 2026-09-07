import Foundation

enum AppConfiguration {
    static var apiBaseURL: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
              let url = URL(string: raw) else {
            preconditionFailure("Info.plist 缺少合法的 APIBaseURL")
        }
        return url
    }

    static var compactAPIBaseURL: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CompactAPIBaseURL") as? String,
              let url = URL(string: raw) else {
            preconditionFailure("Info.plist 缺少合法的 CompactAPIBaseURL")
        }
        return url
    }
}

enum ChatLine: String, CaseIterable, Identifiable {
    case main
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: return "原版"
        case .compact: return "精简版"
        }
    }

    var apiBaseURL: URL {
        switch self {
        case .main: return AppConfiguration.apiBaseURL
        case .compact: return AppConfiguration.compactAPIBaseURL
        }
    }

    var cacheFileName: String {
        switch self {
        case .main: return "messages.json"
        case .compact: return "messages-compact.json"
        }
    }
}
