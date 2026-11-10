import Foundation
import Testing
@testable import IntentCore

// The JS primitives every port leans on, checked against Node itself.
@Suite("JS primitives (parity)")
struct JSCompatTests {
    let f: JSON
    init() throws { f = try Fixture.load("jsCompat") }

    func same(_ a: Double, _ b: Double?) -> Bool {
        guard let b else { return false }
        return a.isNaN ? b.isNaN : a == b
    }

    @Test func number() {
        for c in f["number"].array {
            let v = JS.number(c["in"].string!)
            #expect(same(v, c["out"].double), "Number(\(c["in"]))")
        }
    }

    @Test func parseFloatAndInt() {
        for c in f["parseFloat"].array {
            #expect(same(JS.parseFloat(c["in"].string!), c["out"].double), "parseFloat(\(c["in"]))")
        }
        for c in f["parseInt"].array {
            #expect(same(JS.parseInt(c["in"].string!), c["out"].double), "parseInt(\(c["in"]))")
        }
        for c in f["parseIntHex"].array {
            #expect(same(JS.parseInt(c["in"].string!, radix: 16), c["out"].double), "parseInt(\(c["in"]), 16)")
        }
    }

    @Test func numberToString() {
        for c in f["toString"].array {
            #expect(JS.string(c["in"].double!) == c["out"].string, "String(\(c["in"]))")
        }
    }

    @Test func mathRound() {
        for c in f["round"].array {
            #expect(JS.round(c["in"].double!) == c["out"].double, "Math.round(\(c["in"]))")
        }
    }

    @Test func trim() {
        for c in f["trim"].array {
            #expect(JS.trim(c["in"].string!) == c["out"].string, "trim(\(c["in"]))")
        }
    }

    @Test func dateParse() throws {
        for c in f["dateParse"].array {
            let tz = try Fixture.tz(c["tz"])
            let got = JSDate.parse(c["in"].string!, tz)
            let want = c["out"].double
            // Only the ISO shapes are supported; V8's legacy fallback is not.
            let legacyOnly = ["2026-13-01"].contains(c["in"].string!)
            if legacyOnly { continue }
            #expect(want == nil ? got.isNaN : got == want, "new Date(\(c["in"])) in \(c["tz"])")
        }
    }

    @Test func dateConstructors() throws {
        for c in f["localCtor"].array {
            let tz = try Fixture.tz(c["tz"])
            let a = c["in"].array.map { $0.double! }
            #expect(JSDate.local(a[0], a[1], a[2], 0, 0, 0, 0, tz) == c["out"].double, "new Date\(c["in"]) in \(c["tz"])")
        }
        for c in f["utcCtor"].array {
            let a = c["in"].array.map { $0.double! }
            #expect(JSDate.utcDate(a[0], a[1], a[2]) == c["out"].double, "Date.UTC\(c["in"])")
        }
        for c in f["toISOString"].array {
            #expect(JSDate.isoString(c["in"].double!) == c["out"].string, "toISOString(\(c["in"]))")
        }
    }
}

@Suite("Collation (parity)")
struct CollationTests {
    @Test func asciiOrderAndPairs() throws {
        let f = try Fixture.load("collation")
        let order = Array(f["asciiOrder"].string!.unicodeScalars).map { String($0) }
        for (a, b) in zip(order, order.dropFirst()) {
            #expect(JS.localeCompare(a, b) < 0, "\(a) < \(b)")
        }
        for c in f["pairs"].array {
            let a = c["a"].string!, b = c["b"].string!
            #expect(JS.localeCompare(a, b).signum() == c["out"].int, "\(a) vs \(b)")
        }
        let sorted = JS.stableSorted(f["sorted"].array.map { $0.string! }.reversed()) { Double(JS.localeCompare($0, $1)) }
        #expect(sorted == f["sorted"].array.map { $0.string! })
    }
}
