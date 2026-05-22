import AppKit
import SwiftUI

@main
struct JamfMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Jamf Mapper") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button(state.graph.nodes.isEmpty ? "Crawl Jamf Objects" : "Refresh Jamf Objects") {
                    Task { await state.recrawlSelectedConnection() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(state.selectedConnection == nil || state.isCrawling)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(width: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIconFactory.makeIcon()
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum AppIconFactory {
    static func makeIcon(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSColor.clear.setFill()
        rect.fill()

        let markRect = rect.insetBy(dx: size * 0.04, dy: size * 0.04)
        let radius = size * 0.18
        let path = NSBezierPath(roundedRect: markRect, xRadius: radius, yRadius: radius)
        let gradient = NSGradient(colors: [
            NSColor.systemTeal,
            NSColor.systemBlue
        ])
        gradient?.draw(in: path, angle: -35)

        drawNodeMark(in: rect, size: size)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawNodeMark(in rect: NSRect, size: CGFloat) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let spread = size * 0.19
        let topLeft = NSPoint(x: center.x - spread, y: center.y + spread * 0.62)
        let topRight = NSPoint(x: center.x + spread, y: center.y + spread * 0.62)
        let bottom = NSPoint(x: center.x, y: center.y - spread * 0.95)
        let strokeWidth = max(4, size * 0.028)
        let nodeRadius = max(8, size * 0.047)

        NSColor.white.setStroke()

        let line = NSBezierPath()
        line.lineWidth = strokeWidth
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        line.move(to: topLeft)
        line.line(to: topRight)
        line.line(to: bottom)
        line.line(to: topLeft)
        line.stroke()

        for point in [topLeft, topRight, bottom] {
            let nodeRect = NSRect(
                x: point.x - nodeRadius,
                y: point.y - nodeRadius,
                width: nodeRadius * 2,
                height: nodeRadius * 2
            )
            let node = NSBezierPath(ovalIn: nodeRect)
            NSColor(red: 0.04, green: 0.16, blue: 0.20, alpha: 0.92).setFill()
            node.fill()
            NSColor.white.setStroke()
            node.lineWidth = strokeWidth * 0.72
            node.stroke()
        }
    }
}
