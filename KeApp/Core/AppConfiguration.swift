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
    case test2

    // 原版、精简版、测试2 仍保留为兼容旧缓存和深链的内部线路。
    // 佳佳 2026-10-06：「只留一个就可以了」——聊天页只剩这一个窗口，测试2 的内容并进柯的记忆。
    static let allCases: [ChatLine] = [.test1]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: return "原版"
        case .compact: return "精简版"
        // 她要的是不叫任何名字；别处拼成「保存到柯的…」「柯 · 已收下」读着自然。
        case .test1: return "柯"
        case .test2: return "测试2"
        }
    }

    var apiBaseURL: URL {
        switch self {
        case .main: return AppConfiguration.apiBaseURL
        case .compact: return AppConfiguration.compactAPIBaseURL
        case .test1: return AppConfiguration.apiBaseURL.appendingPathComponent("ke-test1")
        case .test2: return AppConfiguration.apiBaseURL.appendingPathComponent("ke-test2")
        }
    }

    var cacheFileName: String {
        switch self {
        case .main: return "messages.json"
        case .compact: return "messages-compact.json"
        case .test1: return "messages-test1.json"
        case .test2: return "messages-test2.json"
        }
    }
}
