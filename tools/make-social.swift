// Draws the 1280x640 card GitHub shows when the repo is linked anywhere.
//
// A cropped screenshot does not survive being scaled into a timeline preview,
// and it never says what the project is, so the card is composed: icon,
// wordmark, one line of promise, and the pill in the state that makes the
// point.
//
//   swift tools/make-social.swift        writes docs/social-preview.png
//
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let width = 1280.0
let height = 640.0

let title = "Redline"
let tagline = "Know the moment your Mac starts throttling"
let pillText = "CPU  96%   GPU  74%   RAM  81%   203°F"
let pillBadge = "THROTTLE"

guard let context = CGContext(data: nil, width: Int(width), height: Int(height),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("could not create context") }

// Same dark gradient the icon sits on.
let backdrop = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1),
                                   CGColor(red: 0.05, green: 0.06, blue: 0.07, alpha: 1)] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(backdrop,
                           start: CGPoint(x: 0, y: height),
                           end: CGPoint(x: width, y: 0),
                           options: [])

// A hint of red bleeding up from the corner, so the name is not the only clue.
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [CGColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 0.20),
                               CGColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 0)] as CFArray,
                      locations: [0, 1])!
context.drawRadialGradient(glow,
                           startCenter: CGPoint(x: width * 0.82, y: -60), startRadius: 0,
                           endCenter: CGPoint(x: width * 0.82, y: -60), endRadius: width * 0.55,
                           options: [])

NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

let titleFont = NSFont.systemFont(ofSize: 82, weight: .bold)
let taglineFont = NSFont.systemFont(ofSize: 33, weight: .regular)
let pillFont = NSFont.monospacedSystemFont(ofSize: 34, weight: .medium)
let badgeFont = NSFont.systemFont(ofSize: 22, weight: .bold)

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont, .foregroundColor: NSColor(white: 0.98, alpha: 1)]
let taglineAttrs: [NSAttributedString.Key: Any] = [
    .font: taglineFont, .foregroundColor: NSColor(white: 0.68, alpha: 1)]

let titleString = NSAttributedString(string: title, attributes: titleAttrs)
let taglineString = NSAttributedString(string: tagline, attributes: taglineAttrs)

// Icon and text ride together as one centered group.
let iconSide = 176.0
let gap = 40.0
let textWidth = max(titleString.size().width, taglineString.size().width)
let groupWidth = iconSide + gap + textWidth
let groupLeft = (width - groupWidth) / 2
let groupCenterY = height * 0.60

if let iconData = try? Data(contentsOf: URL(fileURLWithPath: "docs/icon.png")),
   let source = CGImageSourceCreateWithData(iconData as CFData, nil),
   let icon = CGImageSourceCreateImageAtIndex(source, 0, nil) {
    context.interpolationQuality = .high
    context.draw(icon, in: CGRect(x: groupLeft, y: groupCenterY - iconSide / 2,
                                  width: iconSide, height: iconSide))
}

let textLeft = groupLeft + iconSide + gap
titleString.draw(at: NSPoint(x: textLeft, y: groupCenterY + 4))
taglineString.draw(at: NSPoint(x: textLeft + 4, y: groupCenterY - 46))

// The pill, drawn rather than screenshotted so it stays sharp, showing the
// state that is the entire reason this app exists.
let badgeString = NSAttributedString(string: pillBadge, attributes: [
    .font: badgeFont, .foregroundColor: NSColor(red: 1.0, green: 0.35, blue: 0.28, alpha: 1)])
let pillString = NSAttributedString(string: pillText, attributes: [
    .font: pillFont, .foregroundColor: NSColor(white: 0.93, alpha: 1)])

let padding = 44.0
let badgeGap = 26.0
let badgeInset = 14.0
let pillWidth = padding * 2 + pillString.size().width + badgeGap
    + badgeString.size().width + badgeInset * 2
let pillHeight = 92.0
let pillRect = CGRect(x: (width - pillWidth) / 2, y: height * 0.20,
                      width: pillWidth, height: pillHeight)

context.addPath(CGPath(roundedRect: pillRect, cornerWidth: pillHeight / 2,
                       cornerHeight: pillHeight / 2, transform: nil))
context.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.12, alpha: 0.96))
context.fillPath()
context.addPath(CGPath(roundedRect: pillRect, cornerWidth: pillHeight / 2,
                       cornerHeight: pillHeight / 2, transform: nil))
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
context.setLineWidth(2)
context.strokePath()

let textY = pillRect.midY - pillString.size().height / 2
pillString.draw(at: NSPoint(x: pillRect.minX + padding, y: textY))

let badgeWidth = badgeString.size().width + badgeInset * 2
let badgeHeight = 40.0
let badgeRect = CGRect(x: pillRect.minX + padding + pillString.size().width + badgeGap,
                       y: pillRect.midY - badgeHeight / 2,
                       width: badgeWidth, height: badgeHeight)
context.addPath(CGPath(roundedRect: badgeRect, cornerWidth: badgeHeight / 2,
                       cornerHeight: badgeHeight / 2, transform: nil))
context.setFillColor(CGColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 0.22))
context.fillPath()
badgeString.draw(at: NSPoint(x: badgeRect.minX + badgeInset,
                             y: badgeRect.midY - badgeString.size().height / 2))

NSGraphicsContext.current = nil

guard let image = context.makeImage() else { fatalError("could not render") }
let out = URL(fileURLWithPath: "docs/social-preview.png")
guard let dest = CGImageDestinationCreateWithURL(out as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not write \(out.path)") }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("Wrote docs/social-preview.png")
