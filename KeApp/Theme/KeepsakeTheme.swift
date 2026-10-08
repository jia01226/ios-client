import SwiftUI

/// Keep rendered fabric pink in both skins; never fade an opaque cutout toward a pale page.
enum KeepsakeTheme {
    static func artworkTint(night: Bool) -> Color { night ? Color(hex: 0xD9AAB8) : .white }
    static func paperTint(night: Bool) -> Color { night ? Color(hex: 0xEBD0C5) : .white }
    static let paperInk = Color(hex: 0x594440)
    static let paperMutedInk = Color(hex: 0x826765)
    static let signature = Color(hex: 0xA06478)
    static let shadow = Color(hex: 0x55303F)
    static let dim = Color(hex: 0x23151D)
}
