import AppKit
import SwiftUI
// Renders the app icon set + previews of the hourglass at several sand levels (run with Sources/Logo.swift).
@MainActor func png(_ view: some View, _ px: Int, _ path: String) {
    let r = ImageRenderer(content: view.frame(width: CGFloat(px), height: CGFloat(px)))
    r.scale = 1
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
struct IconView: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.18)
                    .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.27), Color(red: 0.08, green: 0.09, blue: 0.15)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(s * 0.09)
                HourglassView(progress: 0.42, color: Color(white: 0.93), sand: Color(red: 0.98, green: 0.72, blue: 0.32), flowing: true)
                    .frame(width: s * 0.46, height: s * 0.6)
            }
        }
    }
}
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out + "/AppIcon.iconset", withIntermediateDirectories: true)
MainActor.assumeIsolated {
    for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),
                       ("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
        png(IconView(), px, "\(out)/AppIcon.iconset/icon_\(name).png")
    }
    let strip = HStack(spacing: 24) {
        ForEach([0.0, 0.3, 0.6, 0.95], id: \.self) { p in
            HourglassView(progress: p, color: .primary.opacity(0.75), sand: Color(red: 0.96, green: 0.38, blue: 0.31), flowing: true)
                .frame(width: 60, height: 80)
        }
    }.padding(20).background(Color.white)
    let r = ImageRenderer(content: strip); r.scale = 2
    if let t = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: t) {
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/levels.png"))
    }
}
