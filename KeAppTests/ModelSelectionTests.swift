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

    func testQuotaCatalogKeepsUnknownClaudePercentagesAndProviderGPTWindow() throws {
        let data = Data(#"""
        {
          "updatedAt":1788080000,
          "selectedGroup":"claude_1",
          "currentRouteGroup":"claude_2",
          "groups":[
            {
              "id":"claude_1","label":"Claude 1","configured":true,
              "available":false,"status":"cooldown","usedPercent":null,
              "remainingPercent":null,"resetAt":1788087600,"stale":false,
              "source":"circuit_breaker","windows":[]
            },
            {
              "id":"claude_2","label":"Claude 2","configured":true,
              "available":true,"status":"available","usedPercent":null,
              "remainingPercent":null,"resetAt":null,"stale":false,
              "source":"circuit_breaker","windows":[]
            },
            {
              "id":"gpt","label":"GPT","configured":true,
              "available":true,"status":"available","usedPercent":4,
              "remainingPercent":96,"resetAt":1788666713,"stale":false,
              "source":"provider","windows":[
                {
                  "kind":"primary","usedPercent":4,"remainingPercent":96,
                  "windowMinutes":10080,"resetAt":1788666713
                }
              ]
            }
          ]
        }
        """#.utf8)

        let catalog = try JSONDecoder().decode(ChatModelQuotaCatalog.self, from: data)

        XCTAssertEqual(catalog.groups.map(\.id), ["claude_1", "claude_2", "gpt"])
        XCTAssertEqual(catalog.selectedGroup, "claude_1")
        XCTAssertEqual(catalog.currentRouteGroup, "claude_2")
        XCTAssertNil(catalog.groups[0].remainingPercent)
        XCTAssertEqual(catalog.groups[0].resetAt, 1_788_087_600)
        XCTAssertEqual(catalog.groups[2].remainingPercent, 96)
        XCTAssertEqual(catalog.groups[2].windows.first?.windowMinutes, 10_080)
        XCTAssertEqual(catalog.groups[2].windows.first?.remainingPercent, 96)
        XCTAssertFalse(catalog.groups.contains { $0.id == "deepseek" })
    }
}
