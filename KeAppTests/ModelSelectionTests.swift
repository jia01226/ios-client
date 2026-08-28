import XCTest
@testable import KeApp

final class ModelSelectionTests: XCTestCase {
    func testCatalogDecodesFourOrderedProviderGroups() throws {
        let data = Data(#"""
        {
          "models":["claude-subscription-opus-5","claude2-subscription-opus-5","codex-subscription:gpt-5.6-terra","deepseek-v4-pro"],
          "default":"claude2-subscription-opus-5",
          "options":[
            {"id":"deepseek-v4-pro","provider":"deepseek","label":"V4 Pro","group":"deepseek","available":true},
            {"id":"claude2-subscription-opus-5","provider":"claude_subscription","label":"Opus 5","group":"claude_2","available":true},
            {"id":"claude-subscription-opus-5","provider":"claude_subscription","label":"Opus 5","group":"claude_1","available":true},
            {"id":"codex-subscription:gpt-5.6-terra","provider":"codex_subscription","label":"GPT-5.6 Terra","group":"gpt","available":true}
          ],
          "groups":[
            {"id":"claude_1","label":"Claude 1","available":true,"configured":true,"message":""},
            {"id":"claude_2","label":"Claude 2","available":true,"configured":true,"message":""},
            {"id":"gpt","label":"GPT","available":true,"configured":true,"message":""},
            {"id":"deepseek","label":"DPSK","available":true,"configured":true,"message":""}
          ]
        }
        """#.utf8)

        let catalog = try JSONDecoder().decode(ChatModelCatalog.self, from: data)
        let sections = ChatModelSection.make(
            options: catalog.options,
            groups: catalog.groups ?? []
        )

        XCTAssertEqual(sections.map(\.id), ["claude_1", "claude_2", "gpt", "deepseek"])
        XCTAssertEqual(sections.map(\.title), ["Claude 1", "Claude 2", "GPT", "DPSK"])
        XCTAssertEqual(sections.map { $0.options.count }, [1, 1, 1, 1])
        XCTAssertEqual(sections[1].options.first?.id, "claude2-subscription-opus-5")
    }

    func testLegacyProviderNamesStillLandInTheNewFourGroups() {
        let options = [
            ChatModelOption(
                id: "old-claude", provider: "claude_subscription", label: nil,
                description: nil, group: "claude_subscription_backup", family: nil,
                available: true
            ),
            ChatModelOption(
                id: "old-codex", provider: "codex_subscription", label: nil,
                description: nil, group: "codex_subscription", family: nil,
                available: true
            ),
        ]

        let sections = ChatModelSection.make(options: options)

        XCTAssertEqual(sections[0].options.map(\.id), ["old-claude"])
        XCTAssertEqual(sections[2].options.map(\.id), ["old-codex"])
        XCTAssertEqual(sections[1].statusMessage, "尚未接入")
        XCTAssertEqual(sections[3].statusMessage, "尚未接入")
    }

    func testUnavailableAccountKeepsItsCollapsibleSectionAndStatus() {
        let groups = [
            ChatModelGroup(
                id: "claude_2", label: "Claude 2", available: false,
                configured: true, message: "额度冷却中"
            )
        ]
        let option = ChatModelOption(
            id: "claude2-subscription-opus-5", provider: "claude_subscription",
            label: "Opus 5", description: nil, group: "claude_subscription",
            family: "claude_2", available: false
        )

        let section = ChatModelSection.make(options: [option], groups: groups)[1]

        XCTAssertFalse(section.isAvailable)
        XCTAssertEqual(section.statusMessage, "额度冷却中")
        XCTAssertFalse(section.options[0].isAvailable)
    }
}
