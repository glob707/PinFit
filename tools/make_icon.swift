import AppKit

// Рисует иконку 1024×1024 в PNG: градиентный squircle + картинки.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let rect = NSRect(x: 62, y: 62, width: size - 124, height: size - 124)
let path = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSGradient(colors: [NSColor(red: 1.0, green: 0.36, blue: 0.48, alpha: 1), NSColor(red: 0.72, green: 0.38, blue: 1.0, alpha: 1)])!
    .draw(in: path, angle: -45)
NSGraphicsContext.current?.restoreGraphicsState()

let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
if let sym = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size, flipped: false) { r in
        sym.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    let s = tinted.size
    tinted.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
