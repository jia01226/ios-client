import Foundation

// 97 的记忆星河留下的小随机数：同一颗种子永远给同一串数。旧星河页已删，「柯的」山茶落花还在用它。
struct GalaxyRandom {
    private var state: UInt32
    init(seed: UInt32) { state = seed }
    static func hash(_ text: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for byte in text.utf8 { h ^= UInt32(byte); h = h &* 16_777_619 }
        return h
    }
    mutating func next() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296
    }
    mutating func normal() -> Double { sqrt(-2 * log(max(0.00001, next()))) * cos(next() * 2 * .pi) }
}
