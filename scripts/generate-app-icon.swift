import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDir = root.appendingPathComponent("XcodeApp/Resources", isDirectory: true)
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let outputIcns = resourcesDir.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

struct IconSpec {
    let fileName: String
    let pixels: Int
}

let specs: [IconSpec] = [
    .init(fileName: "icon_16x16.png", pixels: 16),
    .init(fileName: "icon_16x16@2x.png", pixels: 32),
    .init(fileName: "icon_32x32.png", pixels: 32),
    .init(fileName: "icon_32x32@2x.png", pixels: 64),
    .init(fileName: "icon_128x128.png", pixels: 128),
    .init(fileName: "icon_128x128@2x.png", pixels: 256),
    .init(fileName: "icon_256x256.png", pixels: 256),
    .init(fileName: "icon_256x256@2x.png", pixels: 512),
    .init(fileName: "icon_512x512.png", pixels: 512),
    .init(fileName: "icon_512x512@2x.png", pixels: 1024)
]

func drawIcon(size: CGFloat) -> NSImage {
    // Load source PNG
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("XcodeApp/Resources/source-icon.png")
    guard let sourceImage = NSImage(contentsOf: sourceURL),
          let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Failed to load source-icon.png")
    }
    
    // Detect content bounds (non-transparent pixels)
    let width = cgImage.width
    let height = cgImage.height
    guard let dataProvider = cgImage.dataProvider,
          let pixelData = dataProvider.data,
          let data = CFDataGetBytePtr(pixelData) else {
        fatalError("Failed to read pixel data")
    }
    
    var minX = width, maxX = 0, minY = height, maxY = 0
    let bytesPerPixel = cgImage.bitsPerPixel / 8
    let bytesPerRow = cgImage.bytesPerRow
    
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            let alpha = data[offset + 3]
            if alpha > 10 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
    }
    
    // Add small padding
    let padding = 20
    minX = max(0, minX - padding)
    minY = max(0, minY - padding)
    maxX = min(width - 1, maxX + padding)
    maxY = min(height - 1, maxY + padding)
    let contentHeight = maxY - minY + 1
    let contentWidth = maxX - minX + 1
    // Make square by expanding smaller dimension
    let maxDimension = max(contentWidth, contentHeight)
    let xOffset = (maxDimension - contentWidth) / 2
    let yOffset = (maxDimension - contentHeight) / 2
    
    minX = max(0, minX - xOffset)
    minY = max(0, minY - yOffset)
    let squareWidth = min(maxDimension, width - minX)
    let squareHeight = min(maxDimension, height - minY)
    // Crop and resize
    let cropped = NSImage(size: NSSize(width: size, height: size))
    cropped.lockFocus()
    let sourceRect = NSRect(x: minX, y: height - minY - squareHeight, width: squareWidth, height: squareHeight)
    sourceImage.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                     from: sourceRect,
                     operation: .sourceOver,
                     fraction: 1.0)
    cropped.unlockFocus()
    return cropped
}

func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        return nil
    }
    return rep.representation(using: .png, properties: [:])
}

for spec in specs {
    let image = drawIcon(size: CGFloat(spec.pixels))
    guard let data = pngData(from: image) else {
        fatalError("Failed encoding \(spec.fileName)")
    }
    let url = iconsetDir.appendingPathComponent(spec.fileName)
    try data.write(to: url)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputIcns.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    fatalError("iconutil failed")
}
