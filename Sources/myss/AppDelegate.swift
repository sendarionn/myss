@preconcurrency import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyConfiguration = HotKeyConfiguration.default
    private let contextReader = AccessibilityContextReader()
    private let hotKeyManager = HotKeyManager()
    private let model = SearchViewModel()
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePanel()
        configureStatusItem()
        let registration = hotKeyManager.register(configuration: hotKeyConfiguration) { [weak self] in
            self?.showPanel()
        }
        if case let .failure(error) = registration {
            print("myss: global hotkey unavailable: \(error)")
        }
        requestAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
        SemanticSearchEngine.shared.stop()
    }

    private func configurePanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: SearchPanelView(model: model))
        model.onDismiss = { [weak panel] in panel?.orderOut(nil) }
        self.panel = panel
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "myss")
        let menu = NSMenu()
        menu.addItem(
            withTitle: "検索を開く（\(hotKeyConfiguration.displayName)）",
            action: #selector(openFromMenu),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openFromMenu() { showPanel() }

    private func showPanel() {
        let context = contextReader.capture()
        model.begin(with: context)
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
