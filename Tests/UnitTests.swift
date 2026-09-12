import Foundation

// A 13-inch Air. The pill is bounded by the whole display rather than the
// usable area, and only horizontally: it is meant to be parkable in the menu
// bar or over the Dock.
let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
let pill = CGSize(width: 280, height: 29)

var failures = 0
func check(_ name: String, _ start: CGPoint, _ expected: CGPoint) {
    let got = clampedHorizontally(CGRect(origin: start, size: pill), into: screen).origin
    let ok = abs(got.x - expected.x) < 0.01 && abs(got.y - expected.y) < 0.01
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name.padding(toLength: 36, withPad: " ", startingAt: 0)) " +
          "(\(Int(start.x)),\(Int(start.y))) -> (\(Int(got.x)),\(Int(got.y)))" +
          (ok ? "" : "  expected (\(Int(expected.x)),\(Int(expected.y)))"))
}

check("pulled off the left edge",        CGPoint(x: -100, y: 500),  CGPoint(x: 0, y: 500))
check("pushed off the right edge",       CGPoint(x: 1600, y: 500),  CGPoint(x: 1430, y: 500))
check("one point past the right edge",   CGPoint(x: 1431, y: 500),  CGPoint(x: 1430, y: 500))
check("already inside, must not move",   CGPoint(x: 715, y: 900),   CGPoint(x: 715, y: 900))
check("flush against the left edge",     CGPoint(x: 0, y: 400),     CGPoint(x: 0, y: 400))

// Vertical is free by design. These must pass through untouched.
check("parked up in the menu bar",       CGPoint(x: 400, y: 1090),  CGPoint(x: 400, y: 1090))
check("parked down over the Dock",       CGPoint(x: 400, y: 4),     CGPoint(x: 400, y: 4))
check("above the top edge, left alone",  CGPoint(x: 400, y: 9999),  CGPoint(x: 400, y: 9999))
check("below the bottom, left alone",    CGPoint(x: 400, y: -500),  CGPoint(x: 400, y: -500))
check("off the left, high up",           CGPoint(x: -100, y: 1090), CGPoint(x: 0, y: 1090))
check("off the right and far below",     CGPoint(x: 9999, y: -500), CGPoint(x: 1430, y: -500))

// A display narrower than the pill: pin to the left edge, leave y alone.
let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
let pinned = clampedHorizontally(CGRect(x: -500, y: -500, width: 280, height: 29), into: tiny).origin
let tinyOK = pinned == CGPoint(x: 0, y: -500)
if !tinyOK { failures += 1 }
print("\(tinyOK ? "PASS" : "FAIL")  display narrower than the pill       -> (\(Int(pinned.x)),\(Int(pinned.y)))")


// Memory pressure: the raw sysctl value maps to a verdict. 3 is not a level
// macOS defines, and an unknown value must read as normal rather than invent
// an alarm nobody can act on.
func checkPressure(_ raw: Int32, _ expected: MemoryPressure, _ note: String) {
    let got = MemoryPressure.from(raw)
    let ok = got == expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  pressure \(String(raw).padding(toLength: 4, withPad: " ", startingAt: 0)) -> " +
          "\(got.label.padding(toLength: 9, withPad: " ", startingAt: 0)) \(note)")
}

checkPressure(1, .normal,   "macOS: normal")
checkPressure(2, .warning,  "macOS: warning")
checkPressure(4, .critical, "macOS: critical")
checkPressure(3, .normal,   "undefined, must not invent alarm")
checkPressure(0, .normal,   "undefined, must not invent alarm")

// The history window behind the menu bar sparklines. It has to drop the oldest
// reading once it is full, or three minutes of traces would grow without end.
func checkWindow(_ name: String, _ start: [Int], _ value: Int, _ limit: Int, _ expected: [Int]) {
    let got = appending(value, to: start, limit: limit)
    let ok = got == expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name.padding(toLength: 36, withPad: " ", startingAt: 0)) " +
          "\(got)" + (ok ? "" : "  expected \(expected)"))
}

checkWindow("first reading into an empty window", [],        1, 3, [1])
checkWindow("still filling, nothing dropped",     [1, 2],    3, 3, [1, 2, 3])
checkWindow("full, oldest falls off the back",    [1, 2, 3], 4, 3, [2, 3, 4])
checkWindow("over-long window trimmed to fit",    [1, 2, 3], 4, 2, [3, 4])
checkWindow("a window of one keeps only the new", [1],       2, 1, [2])
checkWindow("limit of zero keeps nothing",        [1, 2],    3, 0, [])

// Core tiers. The fastest tier (perflevel0) sits at the END of the flat
// host_processor_info array, verified on an M5 Pro by pegging cores and
// watching which indices lit up.
func checkTiers(_ counts: [Int], _ total: Int, _ expected: [Range<Int>]?, _ note: String) {
    let got = tierRanges(coreCounts: counts, totalCores: total)
    let ok = got == expected
    if !ok { failures += 1 }
    let shown = got.map { $0.map { "\($0.lowerBound)..<\($0.upperBound)" }.joined(separator: " ") } ?? "nil"
    print("\(ok ? "PASS" : "FAIL")  tiers \(counts) of \(total) -> \(shown)  \(note)")
}

checkTiers([6, 12], 18, [12..<18, 0..<12], "M5 Pro: 6 fastest last, 12 first")
checkTiers([4, 4], 8, [4..<8, 0..<4], "M2 Air: 4 performance last")
checkTiers([8], 8, [0..<8], "single tier fills the array")
checkTiers([6, 12], 16, nil, "counts do not sum: refuse to guess")
checkTiers([], 8, nil, "no tiers reported")
checkTiers([0, 8], 8, nil, "a zero-core tier is nonsense")
print(failures == 0 ? "\nall \(23 + 6) cases pass" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
