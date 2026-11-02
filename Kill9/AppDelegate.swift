import AppKit
import CoreText
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let store = PortStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.title = ""
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.toolTip = "Kill9 — Development ports"
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Kill9, development ports")
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView(store: store) { NSApp.terminate(nil) })
        host.sizingOptions = []
        popover.contentViewController = host
        resizePopover()
        store.onLayoutChange = { [weak self] in self?.resizePopover() }
    }

    private static func menuBarIcon() -> NSImage {
        let font = NSFont(name: "Impact", size: 20)
            ?? NSFont.systemFont(ofSize: 20, weight: .heavy)
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        let characters = Array("KILL9".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        var advances = [CGSize](repeating: .zero, count: characters.count)
        CTFontGetGlyphsForCharacters(ctFont, characters, &glyphs, characters.count)
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, glyphs, &advances, glyphs.count)
        let path = CGMutablePath()
        var cursor: CGFloat = 0
        for index in glyphs.indices {
            if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[index], nil) {
                path.addPath(glyphPath, transform: CGAffineTransform(translationX: cursor, y: 0))
            }
            cursor += advances[index].width
        }
        let image = NSImage(size: NSSize(width: 34, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let bounds = path.boundingBoxOfPath
            guard bounds.width > 0, bounds.height > 0 else { return false }
            let scale = min(30 / bounds.width, 12 / bounds.height)
            context.saveGState()
            // Center the visible shape, excluding Impact's baseline/line padding.
            context.translateBy(x: 17, y: 9)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.midX, y: -bounds.midY)
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Kill9"
        return image
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem?.button else { return }
        store.refresh()
        resizePopover()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func resizePopover() {
        popover.contentSize = NSSize(width: ListGeometry.width, height: store.popoverHeight)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
