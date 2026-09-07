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
    case test1

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: return "原版"
        case .compact: return "精简版"
        case .test1: return "测试1"
        }
    }

    var apiBaseURL: URL {
        switch self {
        case .main: return AppConfiguration.apiBaseURL
        case .compact: return AppConfiguration.compactAPIBaseURL
        case .test1: return AppConfiguration.apiBaseURL.appendingPathComponent("ke-test1")
        }
    }

    var cacheFileName: String {
        switch self {
        case .main: return "messages.json"
        case .compact: return "messages-compact.json"
        case .test1: return "messages-test1.json"
        }
    }
}
