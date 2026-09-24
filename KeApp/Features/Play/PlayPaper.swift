import SwiftUI

// MARK: - 飘着的几片花瓣
//
// 底图（PlayPaper）上的花瓣是印死的。这里再叠四片会动的，
// 落在她那张图的空处，跟风铃一个风：慢一点，浮着转。
// 位置是手摆的，不是随机 —— 每次打开都在同一处，不会一进页面就换张脸。

/// 一片花瓣：长叶形，中间一道脉。
struct PetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = CGPoint(x: rect.minX, y: rect.midY)
        let right = CGPoint(x: rect.maxX, y: rect.midY)
        path.move(to: left)
        path.addQuadCurve(to: right, control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.30))
        path.addQuadCurve(to: left, control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.30))
        path.closeSubpath()
        return path
    }
}

struct DriftingPetals: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let petal: Color

    // x, y 是屏幕比例；size 是长边；angle 是躺的角度；drift 是错开的相位。
    private let petals: [(x: CGFloat, y: CGFloat, size: CGFloat, angle: Double, drift: Double)] = [
        (0.30, 0.58, 40, -24, 0.0),
        (0.72, 0.62, 34, 18, 1.7),
        (0.44, 0.74, 30, -12, 3.2),
        (0.63, 0.83, 36, 26, 4.6)
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate

                ForEach(Array(petals.enumerated()), id: \.offset) { _, p in
                    let bob = reduceMotion ? 0 : sin(t * .pi * 2 / 9.0 + p.drift) * 6
                    let tilt = reduceMotion ? 0 : sin(t * .pi * 2 / 11.0 + p.drift) * 4

                    PetalShape()
                        .fill(
                            LinearGradient(colors: [petal.opacity(0.52), petal.opacity(0.26)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .overlay(
                            Capsule()
                                .fill(petal.opacity(0.34))
                                .frame(width: p.size * 0.68, height: 0.7)
                        )
                        .frame(width: p.size, height: p.size * 0.42)
                        .rotationEffect(.degrees(p.angle + tilt))
                        .position(x: w * p.x, y: h * p.y + bob)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
