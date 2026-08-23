import Foundation
import Security


protocol HouseKeyValueStoring {
    func load() -> String?
    @discardableResult
    func save(_ value: String) -> Bool
}


struct KeychainHouseKeyValueStore: HouseKeyValueStoring {
    private let service = "love.jiagude.ke.house-key"
    private let account = "ke_home"

    func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return false }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var insertion = query
        attributes.forEach { insertion[$0.key] = $0.value }
        return SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess
    }
}


struct HouseKeyCookieStore {
    static let cookieName = "ke_home"

    private let keychain: HouseKeyValueStoring

    init(keychain: HouseKeyValueStoring = KeychainHouseKeyValueStore()) {
        self.keychain = keychain
    }

    /// App 重装或系统清掉 Cookie 后，从 Keychain 把家钥匙放回共享 Cookie 罐。
    func restoreCookie(into storage: HTTPCookieStorage, for baseURL: URL) {
        guard let value = keychain.load(),
              let cookie = Self.cookie(value: value, for: baseURL) else { return }
        storage.setCookie(cookie)
    }

    /// 认领期第一次收到 HttpOnly Cookie 后，立刻抄一份进 Keychain。
    func persistCookie(from storage: HTTPCookieStorage, for baseURL: URL) {
        guard let cookie = storage.cookies(for: baseURL)?.first(where: {
            $0.name == Self.cookieName && !$0.value.isEmpty
        }) else { return }
        _ = keychain.save(cookie.value)
    }

    static func cookie(value: String, for baseURL: URL) -> HTTPCookie? {
        guard !value.isEmpty, let host = baseURL.host, !host.isEmpty else { return nil }
        return HTTPCookie(properties: [
            .name: cookieName,
            .value: value,
            .domain: host,
            .path: "/",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(60 * 60 * 24 * 3650),
        ])
    }
}
