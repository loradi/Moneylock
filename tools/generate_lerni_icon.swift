import AppKit

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("failed to create bitmap") }

NSGraphicsContext.saveGraphicsState()
guard let gc = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("failed to create graphics context") }
NSGraphicsContext.current = gc
let ctx = gc.cgContext

// Background: diagonal gradient, deep indigo -> violet
let colors = [
    NSColor(calibratedRed: 0x37/255.0, green: 0x30/255.0, blue: 0xA3/255.0, alpha: 1).cgColor,
    NSColor(calibratedRed: 0x7C/255.0, green: 0x3A/255.0, blue: 0xED/255.0, alpha: 1).cgColor,
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                        start: CGPoint(x: 0, y: CGFloat(size)),
                        end: CGPoint(x: CGFloat(size), y: 0),
                        options: [])

// Brain mark: Apple's own "brain.fill" SF Symbol, tinted white — a real,
// professionally drawn brain glyph beats hand-rolled bezier anatomy.
let cx = CGFloat(size) / 2
let sizeConfig = NSImage.SymbolConfiguration(pointSize: 500, weight: .regular)
let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
let symbolConfig = sizeConfig.applying(colorConfig)
guard let brainSymbol = NSImage(systemSymbolName: "brain.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig) else {
    fatalError("brain.fill SF Symbol not available")
}
let brainSize = brainSymbol.size
let brainCenterY: CGFloat = 640
let brainRect = NSRect(x: cx - brainSize.width / 2, y: brainCenterY - brainSize.height / 2,
                        width: brainSize.width, height: brainSize.height)
brainSymbol.draw(in: brainRect, from: .zero, operation: .sourceOver, fraction: 1.0)

// Wordmark: "Lerni" in bold white sans-serif, lower third.
let text = "Lerni"
let font = NSFont.systemFont(ofSize: 190, weight: .bold)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
]
let attrString = NSAttributedString(string: text, attributes: attrs)
let textSize = attrString.size()
let textRect = NSRect(x: cx - textSize.width / 2, y: 190, width: textSize.width, height: textSize.height)
attrString.draw(in: textRect)

NSGraphicsContext.restoreGraphicsState()

// Flatten onto an opaque, alpha-free bitmap — App Store icons must not carry
// an alpha channel even when every pixel is already fully opaque.
guard let sourceImage = bitmap.cgImage else { fatalError("failed to get CGImage") }
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let flatCtx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("failed to create flat context") }
flatCtx.draw(sourceImage, in: CGRect(x: 0, y: 0, width: size, height: size))
guard let flatImage = flatCtx.makeImage() else { fatalError("failed to flatten image") }
let flatBitmap = NSBitmapImageRep(cgImage: flatImage)

guard let png = flatBitmap.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}
try! png.write(to: URL(fileURLWithPath: "/tmp/lerni-icon.png"))
print("wrote /tmp/lerni-icon.png")
