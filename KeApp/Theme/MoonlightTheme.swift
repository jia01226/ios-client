import SwiftUI
import UIKit

/// Art and native controls share these tokens; chat and the night palette stay independent.
enum Moonlight {
    static func serif(_ size: CGFloat) -> Font {
        .custom("NotoSerifSC-ExtraLight", size: size, relativeTo: .body)
    }
    static func script(_ size: CGFloat) -> Font {
        .custom("Allura-Regular", size: size, relativeTo: .body)
    }
    static func numeral(_ size: CGFloat) -> Font {
        .custom("BodoniSvtyTwoITCTT-Book", size: size, relativeTo: .title)
    }
    static let pearl = Color(hex: 0xFCF7F3)
    static let rosePaper = Color(hex: 0xF1E1E4)
    static let lavenderPaper = Color(hex: 0xEAE5EB)
    static let deepRose = Color(hex: Morandi.deepRose)
    static let ink = Color(hex: Morandi.ink)
    static let lacquer = UIColor(red: 0.87, green: 0.72, blue: 0.73, alpha: 1)
    static let lacquerInside = UIColor(red: 0.75, green: 0.59, blue: 0.61, alpha: 1)
    static let pearlMetal = UIColor(red: 0.96, green: 0.88, blue: 0.84, alpha: 1)
    static let paper = UIColor(red: 0.98, green: 0.95, blue: 0.91, alpha: 1)
    static let light = UIColor.white
    static let clear = UIColor.clear
}

struct MoonlightHeader: View {
    @EnvironmentObject private var theme: Theme
    let title: String
    var subtitle: String? = nil
    var artwork: String = "KeMoonCamellia"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Moonlight.serif(43))
            if let subtitle { Text(subtitle).font(Moonlight.serif(14)).foregroundStyle(theme.pageColor.textSecondary) }
        }
        .foregroundStyle(theme.pageColor.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .background(alignment: .topTrailing) {
            Image(artwork).resizable().scaledToFit().frame(width: 242)
                .opacity(theme.skin == .day ? 0.74 : 0.14)
                .offset(x: 88, y: -76).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct MoonCrescent: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.76, y: 0))
        p.addCurve(to: CGPoint(x: rect.width * 0.94, y: rect.height * 0.78), control1: CGPoint(x: rect.width * 0.04, y: rect.height * 0.15), control2: CGPoint(x: rect.width * 0.28, y: rect.height * 0.86))
        p.addCurve(to: CGPoint(x: rect.width * 0.76, y: 0), control1: CGPoint(x: rect.width * 0.12, y: rect.height * 1.42), control2: CGPoint(x: -rect.width * 0.27, y: rect.height * 0.28))
        return p
    }
}
