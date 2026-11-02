import Foundation

// Small, exact re-implementations of the JavaScript primitives the web app's logic
// leans on. Each one exists because the obvious Swift spelling behaves differently:
//
// - `Math.round` rounds .5 toward +infinity; Swift's `.rounded()` rounds away from zero.
// - Template literals print numbers the JS way (`80`, not `80.0`; `1e-7`, not `1e-07`).
// - `Number("...")` and `parseFloat("...")` accept different grammars than `Double(_:)`.
// - `localeCompare` is ICU collation, not code-point order.
// - `Array.prototype.sort` is stable.
//
// Everything here is internal to IntentCore except where a caller outside needs it.

enum JS {
    // MARK: Math

    /// `Math.round`: halves go toward +infinity (`Math.round(-2.5) == -2`).
    static func round(_ x: Double) -> Double {
        guard x.isFinite else { return x }
        let down = x.rounded(.down)
        return x - down >= 0.5 ? down + 1 : down
    }

    /// `Math.max` over two numbers, NaN-propagating.
    static func max(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN { return .nan }
        return Swift.max(a, b)
    }

    // MARK: Number -> string

    /// `String(n)` / `${n}` for a JS number.
    static func string(_ x: Double) -> String {
        if x.isNaN { return "NaN" }
        if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
        if x == 0 { return "0" }
        let negative = x < 0
        // Swift's description is the shortest round-tripping digit string, like JS's.
        // Re-lay those digits out with ECMAScript's Number::toString rules.
        let desc = "\(Swift.abs(x))"
        var mantissa = desc
        var exp10 = 0
        if let e = desc.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = String(desc[..<e])
            exp10 = Int(desc[desc.index(after: e)...]) ?? 0
        }
        var intPart = mantissa
        var fracPart = ""
        if let dot = mantissa.firstIndex(of: ".") {
            intPart = String(mantissa[..<dot])
            fracPart = String(mantissa[mantissa.index(after: dot)...])
        }
        var digits = intPart + fracPart
        // n: position of the decimal point relative to the digit string.
        var n = intPart.count + exp10
        while digits.hasPrefix("0") && digits.count > 1 {
            digits.removeFirst()
            n -= 1
        }
        while digits.hasSuffix("0") && digits.count > 1 { digits.removeLast() }
        let k = digits.count
        var out: String
        if k <= n && n <= 21 {
            out = digits + String(repeating: "0", count: n - k)
        } else if 0 < n && n <= 21 {
            let i = digits.index(digits.startIndex, offsetBy: n)
            out = String(digits[..<i]) + "." + String(digits[i...])
        } else if -6 < n && n <= 0 {
            out = "0." + String(repeating: "0", count: -n) + digits
        } else {
            let e = n - 1
            let first = String(digits.prefix(1))
            let rest = String(digits.dropFirst())
            out = first + (rest.isEmpty ? "" : "." + rest) + "e" + (e >= 0 ? "+" : "-") + String(Swift.abs(e))
        }
        return negative ? "-" + out : out
    }

    static func string(_ x: Int) -> String { String(x) }

    /// `n.toLocaleString("en-US")` for the integer field limits: comma grouping.
    static func groupedEnUS(_ x: Double) -> String {
        guard x.isFinite, x == x.rounded() else { return string(x) }
        let negative = x < 0
        var digits = string(Swift.abs(x))
        var groups: [String] = []
        while digits.count > 3 {
            groups.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        groups.insert(digits, at: 0)
        return (negative ? "-" : "") + groups.joined(separator: ",")
    }

    // MARK: String -> number

    /// JS `String.prototype.trim` whitespace (WhiteSpace + LineTerminator).
    static func isWhitespace(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        case 0x2000...0x200A:
            return true
        default:
            return false
        }
    }

    static func trim(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end && isWhitespace(scalars[start]) { start += 1 }
        while end > start && isWhitespace(scalars[end - 1]) { end -= 1 }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars[start..<end])
        return String(out)
    }

    /// 0-9 / a-f / A-F only. (`Character.hexDigitValue` also takes fullwidth forms,
    /// which JS's parsers don't.)
    private static func asciiHexValue(_ c: Character) -> Int? {
        guard let a = c.asciiValue else { return nil }
        switch a {
        case 48...57: return Int(a - 48)
        case 65...70: return Int(a - 55)
        case 97...102: return Int(a - 87)
        default: return nil
        }
    }

    private static func isASCIIDigit(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return a >= 48 && a <= 57
    }

    /// Matches `^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?` at the start of `s` and
    /// returns the length of the match (0 when there is no number).
    private static func decimalPrefixLength(_ chars: [Character]) -> Int {
        var i = 0
        if i < chars.count, chars[i] == "+" || chars[i] == "-" { i += 1 }
        let intStart = i
        while i < chars.count, isASCIIDigit(chars[i]) { i += 1 }
        let intDigits = i - intStart
        var fracDigits = 0
        if i < chars.count, chars[i] == "." {
            var j = i + 1
            while j < chars.count, isASCIIDigit(chars[j]) { j += 1 }
            fracDigits = j - i - 1
            if intDigits > 0 || fracDigits > 0 { i = j }
        }
        if intDigits == 0 && fracDigits == 0 { return 0 }
        if i < chars.count, chars[i] == "e" || chars[i] == "E" {
            var j = i + 1
            if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
            let expStart = j
            while j < chars.count, isASCIIDigit(chars[j]) { j += 1 }
            if j > expStart { i = j }
        }
        return i
    }

    private static func decimalValue(_ text: String) -> Double {
        // Swift's Double(_:) doesn't take "5." or ".5" in every toolchain; normalise.
        var t = text
        if t.hasSuffix(".") { t += "0" }
        if let dot = t.firstIndex(of: "."), dot == t.startIndex || !isASCIIDigit(t[t.index(before: dot)]) {
            t.insert("0", at: dot)
        }
        if let e = t.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            let before = t[..<e]
            if before.hasSuffix(".") { t.insert("0", at: e) }
        }
        return Double(t) ?? .nan
    }

    /// `Number(string)`.
    static func number(_ s: String) -> Double {
        let t = trim(s)
        if t.isEmpty { return 0 }
        switch t {
        case "Infinity", "+Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: break
        }
        let lower = t.lowercased()
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where lower.hasPrefix(prefix) {
            let body = lower.dropFirst(2)
            guard !body.isEmpty else { return .nan }
            var value = 0.0
            for c in body {
                guard let d = asciiHexValue(c), d < radix else { return .nan }
                value = value * Double(radix) + Double(d)
            }
            return value
        }
        let chars = Array(t)
        let len = decimalPrefixLength(chars)
        guard len == chars.count else { return .nan }
        return decimalValue(t)
    }

    /// `parseFloat(string)`.
    static func parseFloat(_ s: String) -> Double {
        var chars = Array(s.unicodeScalars)
        while let f = chars.first, isWhitespace(f) { chars.removeFirst() }
        let str = String(String.UnicodeScalarView(chars))
        let c = Array(str)
        var signLen = 0
        if let f = c.first, f == "+" || f == "-" { signLen = 1 }
        if c.count >= signLen + 8, String(c[signLen..<(signLen + 8)]) == "Infinity" {
            return signLen == 1 && c[0] == "-" ? -.infinity : .infinity
        }
        let len = decimalPrefixLength(c)
        guard len > 0 else { return .nan }
        return decimalValue(String(c[0..<len]))
    }

    /// `parseInt(string, radix)` for radix 10 or 16, as a Double (NaN when no digits).
    /// A nil radix is JS's default: hex after a "0x" prefix, else decimal.
    static func parseInt(_ s: String, radix explicitRadix: Int? = nil) -> Double {
        var chars = Array(s.unicodeScalars)
        while let f = chars.first, isWhitespace(f) { chars.removeFirst() }
        var negative = false
        if let f = chars.first, f == "+" || f == "-" {
            negative = f == "-"
            chars.removeFirst()
        }
        var radix = explicitRadix ?? 10
        if explicitRadix == nil || explicitRadix == 16, chars.count >= 2, chars[0] == "0", chars[1] == "x" || chars[1] == "X" {
            chars.removeFirst(2)
            radix = 16
        }
        var value = 0.0
        var any = false
        for u in chars {
            guard let d = asciiHexValue(Character(u)), d < radix else { break }
            value = value * Double(radix) + Double(d)
            any = true
        }
        guard any else { return .nan }
        return negative ? -value : value
    }

    /// `ToInt32` - what `>>` and `&` do to their operands.
    static func toInt32(_ x: Double) -> Int32 {
        guard x.isFinite else { return 0 }
        let t = x < 0 ? (-x).rounded(.down) * -1 : x.rounded(.down)
        let m = t.truncatingRemainder(dividingBy: 4_294_967_296)
        let u = m < 0 ? m + 4_294_967_296 : m
        return Int32(truncatingIfNeeded: UInt32(u))
    }

    // MARK: Strings

    /// `str.toLowerCase()` / `toUpperCase()` - Swift's full Unicode mappings match JS's.
    static func lower(_ s: String) -> String { s.lowercased() }

    /// UTF-16 length, which is what JS `.length` counts.
    static func length(_ s: String) -> Int { s.utf16.count }

    // MARK: Sorting

    /// `Array.prototype.sort` with a comparator: stable.
    static func stableSorted<T>(_ items: [T], by compare: (T, T) -> Double) -> [T] {
        items.enumerated()
            .sorted { a, b in
                let c = compare(a.element, b.element)
                if c < 0 { return true }
                if c > 0 { return false }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    // MARK: Collation

    // ICU root collation (what `localeCompare` does for English text) over printable
    // ASCII: whitespace, then punctuation and symbols, then digits, then letters
    // case-insensitively - with lowercase before uppercase only as a tie-break once
    // the whole string compares equal ignoring case. The order string is copied from
    // Node's own sort of the ASCII range; the fixture generator re-checks it.
    private static let primaryOrder: [UInt8: Int] = {
        let order = "\t _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789abcdefghijklmnopqrstuvwxyz"
        var map: [UInt8: Int] = [:]
        for (i, c) in order.utf8.enumerated() { map[c] = i + 1 }
        for c in UInt8(ascii: "A")...UInt8(ascii: "Z") { map[c] = map[c + 32] }
        return map
    }()

    /// `a.localeCompare(b)`: negative, zero or positive.
    static func localeCompare(_ a: String, _ b: String) -> Int {
        let ua = Array(a.unicodeScalars)
        let ub = Array(b.unicodeScalars)
        let asciiOnly = ua.allSatisfy { $0.isASCII } && ub.allSatisfy { $0.isASCII }
        guard asciiOnly else {
            // Outside ASCII there is no attempt at real collation: plain scalar order.
            for (x, y) in zip(ua, ub) where x != y { return x.value < y.value ? -1 : 1 }
            return ua.count == ub.count ? 0 : (ua.count < ub.count ? -1 : 1)
        }
        // Control characters are ignorable at every level.
        func weights(_ scalars: [Unicode.Scalar]) -> [(UInt8, Int)] {
            scalars.compactMap { u in
                let byte = UInt8(u.value)
                return primaryOrder[byte].map { (byte, $0) }
            }
        }
        let pa = weights(ua)
        let pb = weights(ub)
        for (x, y) in zip(pa, pb) where x.1 != y.1 { return x.1 < y.1 ? -1 : 1 }
        if pa.count != pb.count { return pa.count < pb.count ? -1 : 1 }
        // Tertiary: lowercase sorts before uppercase.
        for (x, y) in zip(pa, pb) where x.0 != y.0 {
            let xUpper = x.0 >= 65 && x.0 <= 90
            return xUpper ? 1 : -1
        }
        return 0
    }
}
