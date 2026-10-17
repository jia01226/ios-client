import Foundation
import Security

/// 118：App 和录屏小模块是两个进程，cookie 不通。
/// App 把「家钥匙」和线路地址放进两边共用的钥匙串，小模块开播时拿出来，去问服务器「现在要看吗」。
enum KeScreenPass {
    static let group = "527CR3MRV2.love.jiagude.shared"
    private static let service = "love.jiagude.ke.screen"
    private static let account = "pass"

    struct Pass: Codable, Equatable {
        var base: String
        var cookie: String
    }

    static func save(_ pass: Pass) {
        guard let data = try? JSONEncoder().encode(pass) else { return }
        if load() == pass { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> Pass? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Pass.self, from: data)
    }
}
