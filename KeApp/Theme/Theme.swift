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

    // 水晶玻璃：页面只使用这些令牌，不在组件里写颜色。
    let glassTint: Color
    let glassTintStrong: Color
    let glassEdge: Color
    let glassInnerLight: Color
    let glassShadow: Color

    // 卧室模式（由柯触发，不由她按）
    let bedroomBg: Color
    let bedroomAccent: Color

    // 玩页飘着的花瓣。风铃本身是水彩图，不需要色值。
    let playPetal: Color
}

enum Morandi {
    static let background: UInt32 = 0xFAF3F4
    static let surface: UInt32 = 0xF3E9EC
    static let ink: UInt32 = 0x594B50
    static let muted: UInt32 = 0x97898E
    static let separator: UInt32 = 0xE7D8DD
    static let rose: UInt32 = 0xBD949E
    static let deepRose: UInt32 = 0xA97F84
    static let paleRose: UInt32 = 0xEEDDE1
    static let mauve: UInt32 = 0xB8A3B0
    static let tea: UInt32 = 0xCDB9AE
    static let sage: UInt32 = 0xA9B5A6
    static let reply: UInt32 = 0xF3E9EC
    static let own: UInt32 = 0xEEDDE1
    static let send: UInt32 = 0xDEC0C7
    static let glass: UInt32 = 0xFCF5F6
}

// MARK: - 两套皮的实际取值

extension Palette {
    static let morandi = Palette(
        bg: Color(hex: Morandi.background), card: Color(hex: Morandi.surface),
        cardElevated: Color(hex: Morandi.reply), separator: Color(hex: Morandi.separator),
        textPrimary: Color(hex: Morandi.ink), textSecondary: Color(hex: Morandi.muted),
        textOnAccent: Color(hex: Morandi.ink), accent: Color(hex: Morandi.rose),
        accentSoft: Color(hex: Morandi.paleRose),
        bubbleKe: Color(hex: Morandi.reply), bubbleKeText: Color(hex: Morandi.ink),
        bubbleMe: Color(hex: Morandi.own), bubbleMeText: Color(hex: Morandi.ink),
        glassTint: Color(hex: Morandi.background),
        glassTintStrong: Color(hex: Morandi.surface).opacity(0.17),
        glassEdge: Color(hex: Morandi.paleRose).opacity(0.72),
        glassInnerLight: Color(hex: Morandi.background).opacity(0.46),
        glassShadow: Color(hex: Morandi.ink).opacity(0.04),
        bedroomBg: Color(hex: Morandi.background), bedroomAccent: Color(hex: Morandi.deepRose),
        playPetal: Color(hex: Morandi.paleRose)
    )



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

        glassTint:       Color.white,
        glassTintStrong: Color.white.opacity(0.17),
        glassEdge:       Color.white.opacity(0.72),
        glassInnerLight: Color.white.opacity(0.46),
        glassShadow:     Color(hex: 0x6D5670).opacity(0.14),

        bedroomBg:     Color(hex: 0x2A1D1F),
        bedroomAccent: Color(hex: 0xC79A4B),

        playPetal:     Color(hex: 0xF2A9B4)
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

        glassTint:       Color.white,
        glassTintStrong: Color.white.opacity(0.10),
        glassEdge:       Color.white.opacity(0.40),
        glassInnerLight: Color.white.opacity(0.22),
        glassShadow:     Color.black.opacity(0.22),

        bedroomBg:     Color(hex: 0x120A14),
        bedroomAccent: Color(hex: 0xD9AE5F),

        playPetal:     Color(hex: 0x8A5A66)
    )
}

// MARK: - 尺寸（也别写死在页面里）

struct Metrics {
    let reviewSwipeThreshold: CGFloat = 100
    let reviewActionHeight: CGFloat = 66
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
    let messageSideReserve: CGFloat = 28
    let bubbleMaxWidth: CGFloat = 360
    let bubbleHorizontalPadding: CGFloat = 16
    let bubbleVerticalPadding: CGFloat = 12
    let splitBubbleGap: CGFloat = 5
    let thinkingBubbleGap: CGFloat = 4
    let thinkingLineGap: CGFloat = 12
    let thinkingLineWidth: CGFloat = 1
    let thinkingLineHeight: CGFloat = 22
    let thinkingHorizontalPadding: CGFloat = 2
    let glassStrokeWidth: CGFloat = 0.8
    let glassShadowRadius: CGFloat = 12
    let glassShadowY: CGFloat = 6
    let drawerWidth: CGFloat = 310
    let drawerHeaderHeight: CGFloat = 56
    let recentPhotoSize: CGFloat = 68
    let messageImageHeight: CGFloat = 180
    let scrollToLatestRevealDistance: CGFloat = 96

    // 126：浮在内容上的三块圆角玻璃（顶栏 / 输入栏 / 底栏），数值照 blush.css 最后一层
    let chromeHeaderInset: CGFloat = 12      // 顶栏离屏幕左右
    let chromeHeaderTop: CGFloat = 8
    let chromeHeaderHeight: CGFloat = 64
    let chromeHeaderRadius: CGFloat = 30
    let chromeComposerInset: CGFloat = 14    // 输入栏离屏幕左右
    let chromeComposerRadius: CGFloat = 30
    let chromeDockInset: CGFloat = 14        // 底栏离屏幕左右
    let chromeDockHeight: CGFloat = 58
    let chromeDockPadding: CGFloat = 5
    let chromeDockRadius: CGFloat = 32
    let chromeDockItemRadius: CGFloat = 25
    let chromeDockMinBottom: CGFloat = 10    // 没有 Home 条的机器，底栏离底边至少这么多
    let chromeGap: CGFloat = 8               // 输入栏和底栏之间、内容和浮栏之间
    let homeMoonSize: CGFloat = 21
}

// MARK: - 字号
//
// ⚠️ 字重不许过细 —— 太细的无衬线是"性冷淡"，跟这个家不搭。
// 正文一律 .regular 起步，标题用 .medium / .semibold。

struct Typo {
    let chatSize: CGFloat
    var chatTypeface: ChatTypography = ChatTypography.all[0]

    let reviewFact = Font.system(.title2, design: .default).weight(.semibold)
    let reviewBody = Font.system(.body, design: .default)
    let reviewCaption = Font.system(.caption, design: .default)
    let pageTitle   = Font.system(size: 30, weight: .semibold)
    let journalTitle = Font.custom("NotoSerifSC-ExtraLight", size: 34, relativeTo: .largeTitle)
    let journalHeading = Font.custom("NotoSerifSC-ExtraLight", size: 20, relativeTo: .headline)
    let journalBody = Font.custom("NotoSerifSC-ExtraLight", size: 15, relativeTo: .body)
    let journalCaption = Font.custom("NotoSerifSC-ExtraLight", size: 12, relativeTo: .caption)
    let journalQuote = Font.custom("NotoSerifSC-ExtraLight", size: 19, relativeTo: .title3)
    let sectionTitle = Font.system(size: 17, weight: .medium)
    let body        = Font.system(size: 16, weight: .regular)
    let caption     = Font.system(size: 13, weight: .regular)
    let quote       = Font.system(size: 20, weight: .regular)   // "柯先开的口"那张卡
    let numberBig   = Font.system(size: 44, weight: .light)     // 428 天
    // 126：顶栏「柯」跟设计稿一样用宋体（思源宋体 Regular），不再是粗系统字
    let chatHeader  = Font.custom("NotoSerifSC-Regular", size: 21, relativeTo: .title3)
    let chatStatus  = Font.system(size: 10.5, weight: .regular)
    /// 底栏三个字：设计稿 Songti SC 14 / 字距 2.4；App 里没有系统宋体，用自带的思源宋体细体
    let dockLabel   = Font.custom("NotoSerifSC-Light", size: 14, relativeTo: .footnote)
    let dockTracking: CGFloat = 2.4
    let menuIcon    = Font.system(size: 20, weight: .semibold)
    let composerIcon = Font.system(size: 18, weight: .regular)
    let sendIcon    = Font.system(size: 17, weight: .semibold)
    let attachmentIcon = Font.system(size: 19, weight: .regular)
    let copyIcon    = Font.system(size: 11, weight: .regular)
    let receiptIcon = Font.system(size: 10, weight: .semibold)
    let thinkingChevron = Font.system(size: 10, weight: .medium)
    let unavailableIcon = Font.system(size: 28, weight: .medium)
    let scrollToLatestIcon = Font.system(size: 15, weight: .semibold)
    let memorySparkleIcon = Font.system(size: 12, weight: .regular)
    let disclosureIcon = Font.system(size: 13, weight: .regular)
    let anniversaryCountdown = Font.system(size: 26, weight: .light)
    let shiftBadge = Font.system(size: 15, weight: .medium)

    var bubble: Font {
        chatTypeface.font(size: Double(chatSize))
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
    /// 128 她：「明明消息好了，但是还是要等待缓冲」。第一个气泡马上出，后面的隔 0.12 秒一个，
    /// 一句话切得再多，从第一个到最后一个加起来也不超过 0.5 秒（以前每个 0.4 秒，五个要等两秒）
    let splitBubbleInterval: Double = 0.12
    let splitBubbleTotalCap: Double = 0.5

    func splitBubbleInterval(forCount count: Int) -> Double {
        guard count > 1 else { return 0 }
        return min(splitBubbleInterval, splitBubbleTotalCap / Double(count - 1))
    }
    let scrollControlResponse: Double = 0.28
    let scrollControlDampingFraction: Double = 1.0
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

    @AppStorage("app.chatPalette") private var storedPalette = ChatPalette.blushID
    @AppStorage("app.chatTypeface") private var storedTypeface = "regular"

    var chatPalette: ChatPalette {
        get { ChatPalette.all.first { $0.id == storedPalette } ?? ChatPalette.all[0] }
        set { objectWillChange.send(); storedPalette = newValue.id }
    }
    var chatTypeface: ChatTypography {
        get { ChatTypography.all.first { $0.id == storedTypeface } ?? ChatTypography.all[0] }
        set { objectWillChange.send(); storedTypeface = newValue.id }
    }
    var reviewSecondary: Color { color.textPrimary.opacity(0.82) }

    var pageColor: Palette { skin == .night ? .night : .morandi }
    var pageBackground: Color { skin == .night ? effectiveBackground : pageColor.bg }
    var pageAccent: Color { skin == .night ? effectiveAccent : pageColor.accent }

    var sendColor: Color { skin == .night ? color.accentSoft : Color(hex: chatPalette.send) }

    var color: Palette {
        switch skin {
        case .day:   return .chat(chatPalette)
        case .night: return .night
        }
    }

    let wallpaper = ChatWallpaperTokens()
    @Published var lockscreenGlass = UserDefaults.standard.bool(forKey: "app.lockscreenGlass") {
        didSet { UserDefaults.standard.set(lockscreenGlass, forKey: "app.lockscreenGlass") }
    }
    var chatTextPrimary: Color { lockscreenGlass ? wallpaper.foreground : color.textPrimary }
    var chatAccent: Color { lockscreenGlass ? wallpaper.foreground : effectiveAccent }
    var chatTextSecondary: Color { lockscreenGlass ? wallpaper.secondary : color.textSecondary }
    var chatTextShadow: Color { lockscreenGlass ? wallpaper.textShadow : .clear }
    var chatBubbleKeText: Color { lockscreenGlass ? wallpaper.foreground : color.bubbleKeText }
    var chatBubbleMeText: Color { lockscreenGlass ? wallpaper.foreground : color.bubbleMeText }

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

    /// 127：她自己挑的气泡颜色（0xRRGGBB）和浓度（0 = 透明，1 = 实心），我的、柯的各一份
    @Published var bubbleMeHex: UInt32 {
        didSet { UserDefaults.standard.set(Int(bubbleMeHex), forKey: BubbleStyleStore.meColorKey) }
    }
    @Published var bubbleKeHex: UInt32 {
        didSet { UserDefaults.standard.set(Int(bubbleKeHex), forKey: BubbleStyleStore.keColorKey) }
    }
    @Published var bubbleMeDensity: Double {
        didSet { UserDefaults.standard.set(bubbleMeDensity, forKey: BubbleStyleStore.meDensityKey) }
    }
    @Published var bubbleKeDensity: Double {
        didSet { UserDefaults.standard.set(bubbleKeDensity, forKey: BubbleStyleStore.keDensityKey) }
    }

    func bubbleHex(_ side: BubbleSide) -> UInt32 { side == .me ? bubbleMeHex : bubbleKeHex }
    func bubbleDensity(_ side: BubbleSide) -> Double { side == .me ? bubbleMeDensity : bubbleKeDensity }
    func setBubbleHex(_ hex: UInt32, for side: BubbleSide) {
        if side == .me { bubbleMeHex = hex } else { bubbleKeHex = hex }
    }
    func setBubbleDensity(_ value: Double, for side: BubbleSide) {
        let clamped = min(max(value, 0), 1)
        if side == .me { bubbleMeDensity = clamped } else { bubbleKeDensity = clamped }
    }

    private init() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "app.moonlight-pink.migrated.v76") {
            defaults.set("moonlight-pink", forKey: "app.chatPalette")
            defaults.set(true, forKey: "app.moonlight-pink.migrated.v76")
        }
        Self.migrateChatPaletteToBlush(defaults)
        KeGlassClarity.migrate(defaults)
        BubbleStyleStore.migrateToSolid(defaults)
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
        // 128：QQ 那样的圆角，没拖过滑杆的默认 18
        bubbleCornerRadius = min(max(savedRadius ?? 18, 12), 34)
        bubbleMeHex = BubbleStyleStore.loadHex(.me, defaults)
        bubbleKeHex = BubbleStyleStore.loadHex(.ke, defaults)
        bubbleMeDensity = BubbleStyleStore.loadDensity(.me, defaults)
        bubbleKeDensity = BubbleStyleStore.loadDensity(.ke, defaults)

        defaults.set(bubbleOpacity, forKey: "app.bubbleOpacity")
    }

    var font: Typo { Typo(chatSize: CGFloat(chatFontSize), chatTypeface: chatTypeface) }

    /// 126：三页同一张粉白纸。聊天原来的「月光浅粉」是 76 版替所有人写进去的默认值，分不出是不是她挑的；
    /// 只有她也没自己挑过「我们/柯的」纸色时（= 一直用默认），才把聊天一起换成粉白。只换一次。
    /// 她挑过别的聊天配色（香槟、奶咖……）或挑过纸色的，一概不动。
    nonisolated static let blushMigrationKey = "app.blush.migrated.v126"
    nonisolated static func migrateChatPaletteToBlush(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: blushMigrationKey) else { return }
        defaults.set(true, forKey: blushMigrationKey)
        let stored = defaults.string(forKey: "app.chatPalette") ?? "moonlight-pink"
        guard stored == "moonlight-pink", !CamelliaPalette.hasExplicitChoice(in: defaults) else { return }
        defaults.set(ChatPalette.blushID, forKey: "app.chatPalette")
    }

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

@MainActor
enum UsPalette {
    static var paper: Color { PageColors.background }
    static var ink: Color { PageColors.ink }
    static var mutedInk: Color { PageColors.muted }
    static var coral: Color { PageColors.rose }
    static var blush: Color { PageColors.paleRose }
    static var sage: Color { PageColors.sage }
    static var gold: Color { PageColors.tea }
    static var hairline: Color { PageColors.separator }
}

@MainActor
enum PageColors {
    static var background: Color { Theme.shared.skin == .day ? Color(hex: Morandi.background) : Color(red: 0.992, green: 0.982, blue: 0.955) }
    static var ink: Color { Theme.shared.skin == .day ? Color(hex: Morandi.ink) : Color(red: 0.25, green: 0.20, blue: 0.24) }
    static var muted: Color { Theme.shared.skin == .day ? Color(hex: Morandi.muted) : Color(red: 0.52, green: 0.46, blue: 0.45) }
    static var rose: Color { Theme.shared.skin == .day ? Color(hex: Morandi.rose) : Color(red: 0.91, green: 0.43, blue: 0.40) }
    static var paleRose: Color { Theme.shared.skin == .day ? Color(hex: Morandi.paleRose) : Color(red: 0.96, green: 0.71, blue: 0.68) }
    static var sage: Color { Theme.shared.skin == .day ? Color(hex: Morandi.sage) : Color(red: 0.49, green: 0.59, blue: 0.45) }
    static var tea: Color { Theme.shared.skin == .day ? Color(hex: Morandi.tea) : Color(red: 0.78, green: 0.57, blue: 0.27) }
    static var separator: Color { Theme.shared.skin == .day ? Color(hex: Morandi.separator) : Color(red: 0.88, green: 0.72, blue: 0.48) }
    static var mauve: Color { Theme.shared.skin == .day ? Color(hex: Morandi.mauve) : Color(red: 0.66, green: 0.45, blue: 0.57) }
    static var ink2: Color { Theme.shared.skin == .day ? Color(hex: Morandi.ink) : Color(hex: 0x302D28) }
    static var background2: Color { Theme.shared.skin == .day ? Color(hex: Morandi.background) : Color(hex: 0xFFFCF7) }
    static var muted2: Color { Theme.shared.skin == .day ? Color(hex: Morandi.muted) : Color(hex: 0x77716A) }
    static var tea2: Color { Theme.shared.skin == .day ? Color(hex: Morandi.tea) : Color(hex: 0xA4826B) }
    static var tea3: Color { Theme.shared.skin == .day ? Color(hex: Morandi.tea) : Color(hex: 0x947055) }
    static var tea4: Color { Theme.shared.skin == .day ? Color(hex: Morandi.tea) : Color(hex: 0xB78D68) }
    static var tea5: Color { Theme.shared.skin == .day ? Color(hex: Morandi.tea) : Color(hex: 0x947343) }
    static var tea6: Color { Theme.shared.skin == .day ? Color(hex: Morandi.tea) : Color(hex: 0xD3A04A) }
    static var tea7: Color { Theme.shared.skin == .day ? Color(hex: Morandi.tea) : Color(hex: 0xB8721F) }
    static var calendarText: Color { Theme.shared.skin == .day ? Color(hex: Morandi.ink) : .white }
}

// Shared measurements for the calendar, shift library and line-drawn mountain hut.
enum JournalLayout {
    static let gutter: CGFloat = 24
    static let gap: CGFloat = 20
    static let smallGap: CGFloat = 10
    static let inset: CGFloat = 14
    static let radius: CGFloat = 16
    static let line: CGFloat = 0.8
    static let objectWidth: CGFloat = 86
    static let drawingWidth: CGFloat = 60
    static let drawingHeight: CGFloat = 52
    static let letterHeight: CGFloat = 130
    static let sceneRatio: CGFloat = 0.92
    static let hutCord: CGFloat = 155
    static let hutTop: CGFloat = 130
    static let shiftChoicesHeight: CGFloat = 260
}

// 朋友圈与提醒的原生布局令牌。
enum MomentsTheme {
    static let unreadColor = Color(hex: 0xC75C70)
    static let coverHeight: CGFloat = 220
    static let coverCaptionOpacity: Double = 0.96
    static let coverArtworkSize: CGFloat = 290
    static let profileAvatarSize: CGFloat = 68
    static let avatarSize: CGFloat = 44
    static let maximumWidth: CGFloat = 680
    static let imageHeight: CGFloat = 230
    static let editorHeight: CGFloat = 180
    static let draftImageHeight: CGFloat = 180
    static let profileOverlap: CGFloat = -28
    static let dotSize: CGFloat = 8
}

enum NotesTheme {
    static let gap: CGFloat = 16
    static let smallGap: CGFloat = 10
    static let compactGap: CGFloat = 8
    static let inset: CGFloat = 20
    static let pageInset: CGFloat = 24
    static let controlHeight: CGFloat = 44
    static let cardMinHeight: CGFloat = 128
    static let drawerCardMinHeight: CGFloat = 88
    static let cardInset: CGFloat = 16
    static let drawerCardInset: CGFloat = 12
    static let foldSize: CGFloat = 16
    static let titleSize: CGFloat = 17
    static let captionSize: CGFloat = 13
    static let authorSize: CGFloat = 14
    static let bodySize: CGFloat = 17
    static let readerSize: CGFloat = 22
    static let scriptSize: CGFloat = 25
    static let largeScriptSize: CGFloat = 32
    static let lineSpacing: CGFloat = 4
    static let ruleWidth: CGFloat = 16
    static let ruleHeight: CGFloat = 0.5
    static let cardOpacity: Double = 0.76
    static let ruleOpacity: Double = 0.55
    static let foldOpacity: Double = 0.23
    static let shadowOpacity: Double = 0.14
    static let shadowRadius: CGFloat = 3
    static let shadowOffset: CGFloat = 3
    static let readerShadowRadius: CGFloat = 18
    static let readerShadowOffset: CGFloat = 8
    static let archiveDuration: Double = 0.28
}

// Build 88：照片聊天背景与锁屏玻璃的视觉令牌。
struct ChatWallpaperTokens {
    let foreground = Color.white
    let secondary = Color.white.opacity(0.7)
    let textShadow = Color.black.opacity(0.25)
    let shade = Color.black
    let textShadowRadius: CGFloat = 2
    let textShadowY: CGFloat = 1
    let blurRange = 0.0...20.0
    let dimRange = 0.0...0.4
    let defaultDim = 0.1
    let editorGap: CGFloat = 12
    let editorPadding: CGFloat = 16
    let editorRadius: CGFloat = 18
    let editorPreviewHeight: CGFloat = 420
    let editorZoom: CGFloat = 6
}

struct ChatLegibility: ViewModifier {
    @EnvironmentObject private var theme: Theme
    func body(content: Content) -> some View {
        // 127：只有照片壁纸才要字影。平时原样返回——以前每个气泡的字都挂一层透明的影子，滑动时白白多一道离屏
        if theme.lockscreenGlass {
            content.shadow(color: theme.chatTextShadow,
                           radius: theme.wallpaper.textShadowRadius,
                           y: theme.wallpaper.textShadowY)
        } else {
            content
        }
    }
}

extension Theme {
    /// 128：聊天里「夜里日记」卡的底（平的一块浅纸，墨色字在夜里也看得清）
    var nightCardPaper: Color { Color(hex: 0xFFFDFB) }
}

/// 128：气泡里的字：照片壁纸上气泡又很透才要字影；平的实心气泡上不要
struct BubbleTextLegibility: ViewModifier {
    @EnvironmentObject private var theme: Theme
    func body(content: Content) -> some View {
        if theme.bubbleTextNeedsShadow {
            content.shadow(color: theme.chatTextShadow,
                           radius: theme.wallpaper.textShadowRadius,
                           y: theme.wallpaper.textShadowY)
        } else {
            content
        }
    }
}

// Build 91: approved grey-purple tarot table. All visual values live here.
enum TarotTableStyle {
    static let ink = Color(red: 0.98, green: 0.94, blue: 0.92)
    static let pearl = Color(red: 0.88, green: 0.77, blue: 0.69)
    static let cloth = Color(red: 0.46, green: 0.40, blue: 0.51)
    static let shadow = Color.black.opacity(0.22)
    static let panel = Color.white.opacity(0.09)
    static let border = pearl.opacity(0.55)
    static let muted = ink.opacity(0.76)
    static let nightShade = Color.black.opacity(0.10)
    /// 122：选了「夜里」牌阵，桌布再暗一层——灯关小一点，不换布、不换牌背
    static let nightSpreadShade = Color.black.opacity(0.22)
    static let gap: CGFloat = 12
    static let smallGap: CGFloat = 6
    static let padding: CGFloat = 20
    static let controlHeight: CGFloat = 44
    static let radius: CGFloat = 8
    static let cardRadius: CGFloat = 4
    static let hairline: CGFloat = 0.7
    static let shadowRadius: CGFloat = 4
    static let shadowY: CGFloat = 3
    static let title = Moonlight.serif(24)
    static let body = Moonlight.serif(16)
    static let caption = Moonlight.serif(13)
    static let tiny = Moonlight.serif(10)
    static let cardAspect: CGFloat = 0.58
    static let stackCardWidth: CGFloat = 0.22
    static let shuffleSeparation: CGFloat = 0.10
    static let stackY: CGFloat = 0.30
    static let slotBorder = border.opacity(0.55)
    static let fanHitHeight: CGFloat = 0.60
    // 120：她说牌太小、老点到旁边那张。牌放大一点（0.105→0.115），抬起的那张多探出来一点（0.045→0.06），
    // 一眼看得出是哪张、第二下也好点；半径不动，两头抬起的牌照样不出屏幕。
    static let fanCardWidth: CGFloat = 0.115
    static let fanRadius: CGFloat = 0.32
    static let fanBottom: CGFloat = 0.105
    static let previewLift: CGFloat = 0.06
    /// 120：手指按在牌头外、牌尾外这么多点以内，也算按在这张上（只往长边方向放，不改变哪张在上面）
    static let fanTouchSlop: CGFloat = 10
    /// 120：抬起的那张四周再多给这么多点：第二下点在它边上也算点中它，不会换成旁边那张
    static let liftedTouchSlop: CGFloat = 8
    /// 120：手指滑过之后这么久以内报上来的「点」不算点（滑完抬手不顺手把牌放上桌）
    static let tapAfterSlide = 0.2
    static let stageHeight: CGFloat = 1.13
    static let singleStageHeight: CGFloat = 1.24
    static let singleSlotY: CGFloat = 0.31
    static let singleCardLabelY: CGFloat = 0.60
    static let celticStageHeight: CGFloat = 1.65
    static let slotWidth: CGFloat = 0.255
    static let singleSlotWidth: CGFloat = 0.29
    static let celticSlotWidth: CGFloat = 0.14
    static let slotY: CGFloat = 0.27
    static let slotLabelY: CGFloat = 0.018
    static let cardLabelY: CGFloat = 0.535
    static let celticX: [CGFloat] = [0.33, 0.33, 0.33, 0.13, 0.33, 0.54, 0.83, 0.83, 0.83, 0.83]
    static let celticY: [CGFloat] = [0.50, 0.50, 0.81, 0.50, 0.19, 0.50, 0.94, 0.68, 0.42, 0.16]
    static let liftDuration = 0.22
    static let moveDuration = 0.48
    static let shuffleDuration = 0.34
    static let unfoldDuration = 0.8
    static let flipDuration = 0.48
}
