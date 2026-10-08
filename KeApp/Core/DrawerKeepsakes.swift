import Foundation

/// Only these projections enter the view tree. A teaser has no title or content field.
struct DrawerLetter: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let content: String
    let createdAt: String
}

struct DrawerTeaser: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
}

struct DrawerKeepsakes: Equatable, Sendable {
    var letters: [DrawerLetter] = []
    var teasers: [DrawerTeaser] = []
    var isEmpty: Bool { letters.isEmpty && teasers.isEmpty }
    var visibleCount: Int { letters.count + teasers.count }

    init() {}
    init(_ remote: RemoteDrawer) {
        var seen = Set<Int>()
        for item in remote.outside {
            guard item.visibility == "released" || item.visibility == "teaser" else { continue }
            guard seen.insert(item.id).inserted else { continue }
            if item.visibility == "released" {
                letters.append(DrawerLetter(id: item.id, title: item.title, content: item.content, createdAt: item.created_at))
            } else {
                teasers.append(DrawerTeaser(id: item.id, text: item.teaser))
            }
        }
    }
}

enum DrawerDate {
    static func label(_ raw: String) -> String {
        guard let date = CompanionDate.parse(raw) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = CompanionDate.calendar
        formatter.timeZone = CompanionDate.calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

/// Translation is absolute from the drag's starting point; don't count it twice on release.
enum DrawerTravel {
    static func progress(start: CGFloat, translation: CGFloat, distance: CGFloat) -> CGFloat {
        min(1, max(0, start + translation / max(1, distance)))
    }
    static func target(start: CGFloat, predictedTranslation: CGFloat, distance: CGFloat) -> CGFloat {
        progress(start: start, translation: predictedTranslation, distance: distance) >= 0.5 ? 1 : 0
    }
}
