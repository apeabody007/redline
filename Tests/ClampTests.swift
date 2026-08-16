import Foundation

// A 13-inch Air: 1710x1112 panel, 40pt menu bar, 61pt Dock.
let screen = CGRect(x: 0, y: 61, width: 1710, height: 1011)
let pill = CGSize(width: 280, height: 29)

var failures = 0
func check(_ name: String, _ start: CGPoint, _ expected: CGPoint) {
    let got = clamped(CGRect(origin: start, size: pill), into: screen).origin
    let ok = abs(got.x - expected.x) < 0.01 && abs(got.y - expected.y) < 0.01
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name.padding(toLength: 34, withPad: " ", startingAt: 0)) " +
          "(\(Int(start.x)),\(Int(start.y))) -> (\(Int(got.x)),\(Int(got.y)))" +
          (ok ? "" : "  expected (\(Int(expected.x)),\(Int(expected.y)))"))
}

check("dragged off the left edge",     CGPoint(x: -100, y: 500),  CGPoint(x: 0, y: 500))
check("dragged off the right edge",    CGPoint(x: 1600, y: 500),  CGPoint(x: 1430, y: 500))
check("dragged under the Dock",        CGPoint(x: 400, y: -50),   CGPoint(x: 400, y: 61))
check("dragged under the menu bar",    CGPoint(x: 400, y: 1100),  CGPoint(x: 400, y: 1043))
check("off both left and bottom",      CGPoint(x: -100, y: -50),  CGPoint(x: 0, y: 61))
check("off both right and top",        CGPoint(x: 9999, y: 9999), CGPoint(x: 1430, y: 1043))
check("already inside, must not move", CGPoint(x: 715, y: 900),   CGPoint(x: 715, y: 900))
check("flush against left edge",       CGPoint(x: 0, y: 61),      CGPoint(x: 0, y: 61))
check("one point past the right edge", CGPoint(x: 1431, y: 500),  CGPoint(x: 1430, y: 500))

// A screen narrower than the pill, e.g. a tiny external display.
let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
let pinned = clamped(CGRect(x: -500, y: -500, width: 280, height: 29), into: tiny).origin
let tinyOK = pinned == CGPoint(x: 0, y: 0)
if !tinyOK { failures += 1 }
print("\(tinyOK ? "PASS" : "FAIL")  screen narrower than the pill        -> (\(Int(pinned.x)),\(Int(pinned.y)))")

print(failures == 0 ? "\nall \(9 + 1) cases pass" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
