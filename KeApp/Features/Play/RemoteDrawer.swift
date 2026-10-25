import Foundation

// 柯的抽屉里的东西（服务器返回）。KeDrawerPage 在用；原来同文件的旧 DrawerView 页已删。
struct RemoteDrawer: Decodable, Sendable {
    let sealed: Bool
    let outside: [Item]
    struct Item: Decodable, Identifiable, Sendable {
        let id: Int
        let title: String
        let teaser: String
        let content: String
        let visibility: String
        let created_at: String
        /// 110：note 便签 / pixel 像素小画 / 其他是原来藏着锁着的那种
        var kind: String? = nil
        var released_at: String? = nil
    }
}
