import Foundation

// 网络层。
//
// ⚠️ 现在是桩。等 `工单板/后端接口清单.md` 出来之后按真实结构对齐：
//    - 路径、方法、参数、返回结构
//    - 鉴权（原生 App 不是浏览器，cookie 那一套要单独处理）
//    - 流式格式（SSE？chunked？—— 解析错了就是一片空白）
//
// 🔴 别让后端迁就这份文件。是这份文件去对齐后端。

enum APIError: Error {
    case badURL
    case badStatus(Int)
    case decoding(Error)
    case transport(Error)
    case notConfigured        // 接口清单还没到
}

actor APIClient {

    static let shared = APIClient()

    /// 从配置读，不写死。等接口清单到位后填。
    private var baseURL: URL?
    private var authToken: String?

    func configure(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.authToken = token
    }

    // MARK: - 发消息

    struct SendResult {
        let reply: String
        let signal: KeSignal?
    }

    /// 发一句话给柯，拿回复。
    ///
    /// 🔴 返回里带的 KeSignal 要交给 Theme.shared.applyServerSignal(bedroom:)
    ///    —— 卧室模式由柯触发，不由她按按钮。
    func send(_ text: String) async throws -> SendResult {
        throw APIError.notConfigured
    }

    /// 流式版本。第一版可以先用非流式跑通，再换这个。
    func stream(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: APIError.notConfigured)
        }
    }

    // MARK: - 推送

    /// 把 APNs 的 device token 上报给 VPS。
    /// 接之前先确认后端在哪儿存 —— 见接口清单第 4 条。
    func registerPushToken(_ token: String) async throws {
        throw APIError.notConfigured
    }

    // MARK: - 其余

    func fetchReminders() async throws -> [Reminder] { throw APIError.notConfigured }
    func fetchTimeline() async throws -> [MemoryCard] { throw APIError.notConfigured }
}
