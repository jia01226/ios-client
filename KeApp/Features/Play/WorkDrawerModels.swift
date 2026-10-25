import Foundation

// 柯手边活计的接口模型（2026-09-19）。原来的工作抽屉页只能从旧 CompanionHubView 进，已删；APIClient.fetchWorkDrawer 还在用。

struct WorkDrawerSummary: Decodable, Sendable {
    let running: Int
    let today: Int
    let last_dispatch: String?
    let last_dispatch_ago: String?
}

struct WorkDrawerRun: Decodable, Sendable {
    let title: String
    let detail: String?
    let status: String?
    let created_at: String?
}

struct WorkDrawerTask: Decodable, Identifiable, Sendable {
    let id: String
    let status: String
    let instruction: String
    let created_at: String?
    let updated_at: String?
    let steps: Int?
    let runs: [WorkDrawerRun]?
}

struct WorkDrawer: Decodable, Sendable {
    let summary: WorkDrawerSummary
    let tasks: [WorkDrawerTask]
}
