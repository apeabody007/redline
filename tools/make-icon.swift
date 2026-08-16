// Draws Redline's app icon: a tach sweep with the needle buried in the red.
//
// Every size is drawn natively rather than downsampled from one master, so the
// strokes stay crisp at 16pt where a scaled-down 1024 would turn to mush.
//
//   swift tools/make-icon.swift            writes Resources/Redline.icns
//
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

/// The gauge sweeps 240°, the way a car tachometer does, and the last 60° of
/// it is the redline the app is named for.
let sweepStart = 210.0
let sweepEnd = -30.0
let redlineStart = 30.0
let needleAngle = 3.0

func drawIcon(size: Double) -> CGImage? {
    guard let context = CGContext(data: nil, width: Int(size), height: Int(size),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // macOS leaves a margin around the artwork and rounds it into a squircle.
    let inset = size * 0.098
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = plate.width * 0.225
    let plateShape = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius,
                            transform: nil)

    context.saveGState()
    context.addPath(plateShape)
    context.clip()
    let backdrop = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1),
                                       CGColor(red: 0.05, green: 0.06, blue: 0.07, alpha: 1)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(backdrop,
                               start: CGPoint(x: plate.midX, y: plate.maxY),
                               end: CGPoint(x: plate.midX, y: plate.minY),
                               options: [])
    context.restoreGState()

    // The dial sits slightly high so the needle hub lands on the optical center.
    let center = CGPoint(x: plate.midX, y: plate.midY - plate.height * 0.06)
    let dialRadius = plate.width * 0.31
    let trackWidth = plate.width * 0.095

    context.setLineCap(.round)

    // Unused portion of the sweep.
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.17))
    context.setLineWidth(trackWidth)
    context.addArc(center: center, radius: dialRadius,
                   startAngle: radians(sweepStart), endAngle: radians(sweepEnd),
                   clockwise: true)
    context.strokePath()

    // The redline itself.
    context.setStrokeColor(CGColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1))
    context.setLineWidth(trackWidth)
    context.addArc(center: center, radius: dialRadius,
                   startAngle: radians(redlineStart), endAngle: radians(sweepEnd),
                   clockwise: true)
    context.strokePath()

    // Needle, swung past the redline.
    let needleLength = dialRadius * 1.02
    let tip = CGPoint(x: center.x + cos(radians(needleAngle)) * needleLength,
                      y: center.y + sin(radians(needleAngle)) * needleLength)
    context.setStrokeColor(CGColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1))
    context.setLineWidth(plate.width * 0.062)
    context.move(to: center)
    context.addLine(to: tip)
    context.strokePath()

    // Hub.
    let hub = plate.width * 0.075
    context.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1))
    context.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub,
                                   width: hub * 2, height: hub * 2))
    context.setFillColor(CGColor(red: 0.09, green: 0.10, blue: 0.11, alpha: 1))
    let core = hub * 0.42
    context.fillEllipse(in: CGRect(x: center.x - core, y: center.y - core,
                                   width: core * 2, height: core * 2))

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not create \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/Redline.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The ten entries iconutil expects.
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        guard let image = drawIcon(size: Double(pixels)) else { continue }
        let suffix = scale == 2 ? "@2x" : ""
        write(image, to: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}

let resources = root.appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path,
                     "-o", resources.appendingPathComponent("Redline.icns").path]
try convert.run()
convert.waitUntilExit()
guard convert.terminationStatus == 0 else { exit(convert.terminationStatus) }
print("Wrote Resources/Redline.icns")
