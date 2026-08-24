import SwiftUI

// MARK: - 主题系统
//
// 🔴 这是全 App 颜色 / 字号 / 圆角 / 间距的唯一来源。
//
// 页面里只准写  Theme.color.bg  这种，
// 不准出现   Color(hex: "1A1F3A")  这类字面量。
//
// 为什么：往后换主题、开"聊天气泡换颜色"的设置项，只改这一份文件。
// 要是颜色写死在几十个页面里，以后得一页一页翻着改。
//
// 建于 2026-08-14。

// MARK: - 皮肤

enum Skin: String, CaseIterable, Identifiable {
    case day    // 浅色 —— 第一版默认（她本人偏好浅色系）
    case night  // 深夜蓝 + 金 —— 跟 App 图标同源

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: return "白天"
        case .night: return "夜里"
        }
    }
}

// MARK: - 色板

struct Palette {
    let bg: Color              // 页面底
    let card: Color            // 卡片底
    let cardElevated: Color    // 需要浮起来的卡片（今天浮上来的回忆、柯先开的口）
    let separator: Color

    let textPrimary: Color     // 正文
    let textSecondary: Color   // 说明、时间戳
    let textOnAccent: Color    // 压在强调色上的字

    let accent: Color          // 金 —— 全 App 唯一的强调色
    let accentSoft: Color      // 淡金，用于描边、分割、次要图标

    let bubbleKe: Color        // 柯说的话
    let bubbleKeText: Color
    let bubbleMe: Color        // 她说的话
    let bubbleMeText: Color
    let systemNoticeSurface: Color
    let systemNoticeText: Color

    // 水晶玻璃：页面只使用这些令牌，不在组件里写颜色。
    let glassTint: Color
    let glassTintStrong: Color
    let glassEdge: Color
    let glassInnerLight: Color
    let glassShadow: Color

    // 卧室模式（由柯触发，不由她按）
    let bedroomBg: Color
    let bedroomAccent: Color
}

// MARK: - 两套皮的实际取值

extension Palette {

    /// 浅色 —— 第一版默认
    static let day = Palette(
        bg:            Color(hex: 0xFBF7F2),
        card:          Color(hex: 0xFFFFFF),
        cardElevated:  Color(hex: 0xFDF6EC),
        separator:     Color(hex: 0xEDE3D6),

        textPrimary:   Color(hex: 0x4C4056),
        textSecondary: Color(hex: 0x766B82),
        textOnAccent:  Color(hex: 0xFFFFFF),

        accent:        Color(hex: 0xC79A4B),   // 金
        accentSoft:    Color(hex: 0xE3CDA1),

        bubbleKe:      Color(hex: 0xFFFFFF),
        bubbleKeText:  Color(hex: 0x4C4056),
        bubbleMe:      Color(hex: 0xF3E4D2),
        bubbleMeText:  Color(hex: 0x4C4056),
        systemNoticeSurface: Color(hex: 0x817A86).opacity(0.13),
        systemNoticeText: Color(hex: 0x625B69),

        glassTint:       Color.white,
        glassTintStrong: Color.white.opacity(0.17),
        glassEdge:       Color.white.opacity(0.72),
        glassInnerLight: Color.white.opacity(0.46),
        glassShadow:     Color(hex: 0x6D5670).opacity(0.14),

        bedroomBg:     Color(hex: 0x2A1D1F),
        bedroomAccent: Color(hex: 0xC79A4B)
    )

    /// 深夜蓝 + 金 —— 跟 App 图标同源
    static let night = Palette(
        bg:            Color(hex: 0x0E1430),
        card:          Color(hex: 0x172046),
        cardElevated:  Color(hex: 0x1E2A5C),
        separator:     Color(hex: 0x27306040),

        textPrimary:   Color(hex: 0xF4F1EA),
        textSecondary: Color(hex: 0x9AA3C4),
        textOnAccent:  Color(hex: 0x0E1430),

        accent:        Color(hex: 0xD9AE5F),   // 金
        accentSoft:    Color(hex: 0x7A6636),

        bubbleKe:      Color(hex: 0x1B2450),
        bubbleKeText:  Color(hex: 0xF4F1EA),
        bubbleMe:      Color(hex: 0x3A2E52),
        bubbleMeText:  Color(hex: 0xF4F1EA),
        systemNoticeSurface: Color.white.opacity(0.12),
        systemNoticeText: Color(hex: 0xC2C7D9),

        glassTint:       Color.white,
        glassTintStrong: Color.white.opacity(0.10),
        glassEdge:       Color.white.opacity(0.40),
        glassInnerLight: Color.white.opacity(0.22),
        glassShadow:     Color.black.opacity(0.22),

        bedroomBg:     Color(hex: 0x120A14),
        bedroomAccent: Color(hex: 0xD9AE5F)
    )
}

// MARK: - 尺寸（也别写死在页面里）

struct Metrics {
    // 圆角：统一偏大，直角冷、圆角暖
    let radiusCard: CGFloat = 18
    let radiusBubble: CGFloat = 20
    let radiusChip: CGFloat = 14

    // 间距
    let gapXS: CGFloat = 4
    let gapS: CGFloat = 8
    let gapM: CGFloat = 14
    let gapL: CGFloat = 20
    let gapXL: CGFloat = 28

    let pagePadding: CGFloat = 18

    // 聊天水晶界面
    let touchTarget: CGFloat = 44
    let headerMinHeight: CGFloat = 70
    let headerTopPadding: CGFloat = 8
    let headerBottomPadding: CGFloat = 9
    let radiusDock: CGFloat = 29
    let radiusComposer: CGFloat = 28
    let radiusAttachmentTray: CGFloat = 24
    let navArtworkSize: CGFloat = 42
    let tabMinimumHeight: CGFloat = 54
    let messageSideReserve: CGFloat = 44
    let bubbleMaxWidth: CGFloat = 318
    // 她 08-19 报的"气泡顶到右边字在左边":20 字太低,中文一句话就超,
    // 大半消息被误判成宽泡(全宽背景+短文字=空旷)。回 56——宽泡只留给真正的长段落。
    let wideMessageCharacterThreshold: Int = 56
    let wideMessageLineThreshold: Int = 3
    let bubbleHorizontalPadding: CGFloat = 16
    let bubbleVerticalPadding: CGFloat = 12
    let splitBubbleGap: CGFloat = 5
    let thinkingBubbleGap: CGFloat = 4
    let thinkingLineGap: CGFloat = 12
    let thinkingLineWidth: CGFloat = 1
    let thinkingHorizontalPadding: CGFloat = 2
    let systemNoticeHorizontalPadding: CGFloat = 14
    let systemNoticeVerticalPadding: CGFloat = 7
    let glassStrokeWidth: CGFloat = 0.8
    let glassShadowRadius: CGFloat = 12
    let glassShadowY: CGFloat = 6
    let drawerWidth: CGFloat = 310
    let drawerHeaderHeight: CGFloat = 56
    let recentPhotoSize: CGFloat = 68
    let messageImageHeight: CGFloat = 180
}

// MARK: - 字号
//
// ⚠️ 字重不许过细 —— 太细的无衬线是"性冷淡"，跟这个家不搭。
// 正文一律 .regular 起步，标题用 .medium / .semibold。

struct Typo {
    let chatSize: CGFloat

    let pageTitle   = Font.system(size: 30, weight: .semibold)
    let sectionTitle = Font.system(size: 17, weight: .medium)
    let body        = Font.system(size: 16, weight: .regular)
    let caption     = Font.system(size: 13, weight: .regular)
    let quote       = Font.system(size: 20, weight: .regular)   // "柯先开的口"那张卡
    let numberBig   = Font.system(size: 44, weight: .light)     // 428 天
    let chatHeader  = Font.system(size: 26, weight: .medium, design: .serif)
    let menuIcon    = Font.system(size: 20, weight: .semibold)
    let composerIcon = Font.system(size: 18, weight: .regular)
    let sendIcon    = Font.system(size: 17, weight: .semibold)
    let attachmentIcon = Font.system(size: 19, weight: .regular)
    let copyIcon    = Font.system(size: 11, weight: .regular)
    let receiptIcon = Font.system(size: 10, weight: .semibold)
    let thinkingChevron = Font.system(size: 10, weight: .medium)
    let systemNotice = Font.system(size: 13, weight: .regular)
    let unavailableIcon = Font.system(size: 28, weight: .medium)
    let memorySparkleIcon = Font.system(size: 12, weight: .regular)
    let disclosureIcon = Font.system(size: 13, weight: .regular)
    let anniversaryCountdown = Font.system(size: 26, weight: .light)
    let shiftBadge = Font.system(size: 15, weight: .medium)

    var bubble: Font {
        Font.system(size: chatSize, weight: .regular, design: .serif)
    }

    var thinking: Font {
        Font.custom("Allura-Regular", size: max(18, chatSize + 2), relativeTo: .body)
    }

    var thinkingBody: Font {
        Font.system(size: max(13, chatSize - 2), weight: .regular, design: .serif)
    }
}

struct GlassTokens {
    let maximumBlurValue: Double = 20
    let fixedSurfaceBlurIntensity: Double = 0.30
    let fixedSurfaceTintOpacity: Double = 0.025
    let accentEdgeOpacity: Double = 0.24
    let scrimOpacity: Double = 0.08
    let sendFillOpacity: Double = 0.72
    let drawerEdgeOpacity: Double = 0.55
    let thinkingLineOpacity: Double = 0.76
}

struct MotionTokens {
    let thinkingResponse: Double = 0.30
    let thinkingDampingFraction: Double = 1.0
}

// MARK: - 对外的门面

@MainActor
final class Theme: ObservableObject {

    static let shared = Theme()

    /// 当前皮肤。第一版默认浅色。
    @AppStorage("app.skin") private var storedSkin: String = Skin.day.rawValue

    /// 用户在设置里选的聊天气泡色（留口，第一版不开放 UI）
    @AppStorage("app.bubbleTint") private var storedBubbleTint: String = ""

    var skin: Skin {
        get { Skin(rawValue: storedSkin) ?? .day }
        set { storedSkin = newValue.rawValue; objectWillChange.send() }
    }

    var color: Palette {
        switch skin {
        case .day:   return .day
        case .night: return .night
        }
    }

    let metric = Metrics()
    let glass = GlassTokens()
    let motion = MotionTokens()

    /// 只控制聊天正文；标题、时间和设置文字保持自己的层级。
    @Published var chatFontSize: Double {
        didSet { UserDefaults.standard.set(chatFontSize, forKey: "app.chatFontSize") }
    }

    @Published var bubbleOpacity: Double {
        didSet { UserDefaults.standard.set(bubbleOpacity, forKey: "app.bubbleOpacity") }
    }

    @Published var glassBlur: Double {
        didSet { UserDefaults.standard.set(glassBlur, forKey: "app.glassBlur") }
    }

    @Published var bubbleCornerRadius: Double {
        didSet { UserDefaults.standard.set(bubbleCornerRadius, forKey: "app.bubbleCornerRadius") }
    }

    private init() {
        let defaults = UserDefaults.standard
        let savedFont = defaults.object(forKey: "app.chatFontSize") as? Double
        let savedOpacity = defaults.object(forKey: "app.bubbleOpacity") as? Double
        let savedBlur = defaults.object(forKey: "app.glassBlur") as? Double
        let savedRadius = defaults.object(forKey: "app.bubbleCornerRadius") as? Double

        chatFontSize = min(max(savedFont ?? 15, 13), 22)

        // 允许真正的 0% 透明；玻璃边缘和模糊仍可独立保留。
        let migratedOpacity = (savedOpacity ?? 0.012) > 0.08
            ? (savedOpacity ?? 0.12) / 10
            : (savedOpacity ?? 0.012)
        bubbleOpacity = min(max(migratedOpacity, 0), 0.06)
        glassBlur = min(max(savedBlur ?? 9, 0), 20)
        bubbleCornerRadius = min(max(savedRadius ?? 20, 12), 34)

        defaults.set(bubbleOpacity, forKey: "app.bubbleOpacity")
    }

    var font: Typo { Typo(chatSize: CGFloat(chatFontSize)) }

    // MARK: 卧室模式
    //
    // 🔴 这个开关由「柯」触发，不由她按。
    // 她只管正常聊天；柯的回复里带状态信号，App 收到后自己切。
    // 手动开关只作为后门保留，不是主路径。
    @Published var isBedroom: Bool = false

    /// 由网络层在收到柯的回复后调用
    func applyServerSignal(bedroom: Bool) {
        guard bedroom != isBedroom else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            isBedroom = bedroom
        }
        // 轻微触感 —— 就是那声「咔哒」
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    /// 页面底色（卧室模式会盖掉当前皮肤）
    var effectiveBackground: Color {
        isBedroom ? color.bedroomBg : color.bg
    }

    var effectiveAccent: Color {
        isBedroom ? color.bedroomAccent : color.accent
    }
}

// MARK: - 工具

extension Color {
    /// 支持 0xRRGGBB 和 0xRRGGBBAA
    init(hex: UInt32) {
        let hasAlpha = hex > 0xFFFFFF
        let r, g, b, a: Double
        if hasAlpha {
            r = Double((hex >> 24) & 0xFF) / 255
            g = Double((hex >> 16) & 0xFF) / 255
            b = Double((hex >> 8) & 0xFF) / 255
            a = Double(hex & 0xFF) / 255
        } else {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
