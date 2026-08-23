import Foundation
import XCTest
@testable import KeApp


private final class MemoryHouseKeyStore: HouseKeyValueStoring {
    var value: String?

    init(_ value: String? = nil) {
        self.value = value
    }

    func load() -> String? { value }

    @discardableResult
    func save(_ value: String) -> Bool {
        self.value = value
        return true
    }
}


final class HouseKeyCookieStoreTests: XCTestCase {
    private let baseURL = URL(string: "https://house-key-tests.invalid")!
    private let storage = HTTPCookieStorage.shared

    override func setUp() {
        super.setUp()
        clearCookies()
    }

    override func tearDown() {
        clearCookies()
        super.tearDown()
    }

    func testRestoresKeychainValueIntoSharedCookieStorage() throws {
        let keychain = MemoryHouseKeyStore("saved-house-key")
        let store = HouseKeyCookieStore(keychain: keychain)

        store.restoreCookie(into: storage, for: baseURL)

        let cookie = storage.cookies(for: baseURL)?.first {
            $0.name == HouseKeyCookieStore.cookieName
        }
        XCTAssertEqual(cookie?.value, "saved-house-key")
        XCTAssertTrue(cookie?.isSecure == true)
        XCTAssertEqual(cookie?.path, "/")
        let headers = HTTPCookie.requestHeaderFields(with: try XCTUnwrap(storage.cookies(for: baseURL)))
        XCTAssertEqual(headers["Cookie"], "ke_home=saved-house-key")
    }

    func testPersistsNewHouseCookieIntoKeychainStore() throws {
        let keychain = MemoryHouseKeyStore()
        let store = HouseKeyCookieStore(keychain: keychain)
        let cookie = try XCTUnwrap(
            HouseKeyCookieStore.cookie(value: "fresh-house-key", for: baseURL)
        )
        storage.setCookie(cookie)

        store.persistCookie(from: storage, for: baseURL)

        XCTAssertEqual(keychain.value, "fresh-house-key")
    }

    func testDoesNotPersistAnUnrelatedCookie() throws {
        let keychain = MemoryHouseKeyStore()
        let store = HouseKeyCookieStore(keychain: keychain)
        let unrelated = try XCTUnwrap(HTTPCookie(properties: [
            .name: "another_cookie",
            .value: "not-the-key",
            .domain: baseURL.host!,
            .path: "/",
        ]))
        storage.setCookie(unrelated)

        store.persistCookie(from: storage, for: baseURL)

        XCTAssertNil(keychain.value)
    }

    private func clearCookies() {
        storage.cookies(for: baseURL)?.forEach { storage.deleteCookie($0) }
    }
}
