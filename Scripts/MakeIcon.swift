// Generuje Resources/AppIcon.icns: biały trójkąt na ciemnym zaokrąglonym tle
// (jak ikona powiadomień w makietach). Wymaga tylko CLT (AppKit + iconutil).
//
// Uruchamiaj z katalogu głównego repo: `swift Scripts/MakeIcon.swift`.
import AppKit

// Rozmiar w pikselach → nazwy w iconsecie. iconutil przyjmuje wyłącznie kanoniczny
// zestaw nazw: pliki spoza niego (np. icon_64x64.png) po cichu wypadają z .icns,
// dlatego ten sam bitmap zapisujemy pod nazwą 1x i @2x tam, gdzie się pokrywają.
let plan: [(pixels: Int, names: [String])] = [
    (16, ["icon_16x16"]),
    (32, ["icon_16x16@2x", "icon_32x32"]),
    (64, ["icon_32x32@2x"]),
    (128, ["icon_128x128"]),
    (256, ["icon_128x128@2x", "icon_256x256"]),
    (512, ["icon_256x256@2x", "icon_512x512"]),
    (1024, ["icon_512x512@2x"]),
]

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (size, names) in plan {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
        let bg = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.06, dy: s * 0.06),
                              xRadius: s * 0.22, yRadius: s * 0.22)
        NSColor(srgbRed: 28/255, green: 28/255, blue: 30/255, alpha: 1).setFill()
        bg.fill()
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: rect.midX, y: rect.maxY - s * 0.30))
        tri.line(to: NSPoint(x: rect.maxX - s * 0.26, y: rect.minY + s * 0.30))
        tri.line(to: NSPoint(x: rect.minX + s * 0.26, y: rect.minY + s * 0.30))
        tri.close()
        NSColor.white.setFill()
        tri.fill()
        return true
    }
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("nie udało się narysować ikony \(size)")
    }
    for name in names {
        try png.write(to: iconset.appendingPathComponent("\(name).png"))
    }
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
try? fm.createDirectory(at: root.appendingPathComponent("Resources"),
                        withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "OK: \(out.path)" : "BŁĄD iconutil")
exit(task.terminationStatus)
