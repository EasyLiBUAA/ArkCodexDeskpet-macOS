import AppKit

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: generate-app-icon.swift <source.png> <output.png>")
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: sourceURL) else { fatalError("Cannot load source image") }

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let outer = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 205, yRadius: 205)
NSColor(calibratedRed: 0.075, green: 0.086, blue: 0.098, alpha: 1).setFill()
outer.fill()

let accent = NSBezierPath()
accent.move(to: NSPoint(x: 72, y: 250))
accent.line(to: NSPoint(x: 72, y: 410))
accent.line(to: NSPoint(x: 952, y: 780))
accent.line(to: NSPoint(x: 952, y: 620))
accent.close()
NSGraphicsContext.current?.saveGraphicsState()
outer.addClip()
NSColor(calibratedRed: 0.12, green: 0.62, blue: 0.59, alpha: 1).setFill()
accent.fill()
NSGraphicsContext.current?.restoreGraphicsState()

source.draw(in: NSRect(x: 122, y: 102, width: 780, height: 780), from: .zero, operation: .sourceOver, fraction: 1)

let statusDot = NSBezierPath(ovalIn: NSRect(x: 790, y: 790, width: 92, height: 92))
NSColor(calibratedRed: 0.17, green: 0.82, blue: 0.55, alpha: 1).setFill()
statusDot.fill()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode icon")
}
try png.write(to: outputURL, options: .atomic)
