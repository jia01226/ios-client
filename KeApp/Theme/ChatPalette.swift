import SwiftUI

struct ChatPalette: Identifiable {
    let id: String
    let name: String
    let base: UInt32
    let ink: UInt32
    let accent: UInt32
    let tint: UInt32
    let send: UInt32
    var reply: UInt32 {
        switch id {
        case "champagne": return 0xDCCFBB
        case "oat": return 0xD2CABE
        case "pink": return 0xDDCCD2
        default: return 0xD8C8BE
        }
    }
    static let all: [ChatPalette] = [
        .init(id: "champagne", name: "奶油香槟", base: 0xFFFCF7, ink: 0x40382E, accent: 0xA58E63, tint: 0xE8D6B5, send: 0xE1CFA8),
        .init(id: "rose", name: "焦糖玫瑰", base: 0xFCF7F3, ink: 0x493A35, accent: 0xA0796E, tint: 0xDDBEB0, send: 0xD9B4A5),
        .init(id: "oat", name: "燕麦奶咖", base: 0xFAF8F3, ink: 0x423B33, accent: 0x93816A, tint: 0xD7CAB6, send: 0xD3C2A8),
        .init(id: "pink", name: "雾粉白茶", base: 0xFDF8F9, ink: 0x493B41, accent: 0xA47D8A, tint: 0xE6C6D0, send: 0xDEBCC8),
    ]
}

extension Color {
    init(paletteHex value: UInt32) {
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }
}


extension Palette {
    static func chat(_ choice: ChatPalette) -> Palette {
        let ink = Color(hex: choice.ink)
        let tint = Color(hex: choice.tint)
        return Palette(
            bg: Color(hex: choice.base), card: .white, cardElevated: .white,
            separator: ink.opacity(0.08), textPrimary: ink,
            textSecondary: ink.opacity(0.66), textOnAccent: ink,
            accent: Color(hex: choice.accent), accentSoft: tint,
            bubbleKe: Color(hex: choice.reply), bubbleKeText: ink, bubbleMe: tint, bubbleMeText: ink,
            glassTint: .white, glassTintStrong: .white.opacity(0.12),
            glassEdge: .white.opacity(0.65), glassInnerLight: .white.opacity(0.3),
            glassShadow: ink.opacity(0.06), bedroomBg: Palette.night.bedroomBg,
            bedroomAccent: Palette.night.bedroomAccent
        )
    }
}
