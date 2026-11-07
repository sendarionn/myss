@preconcurrency import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var hotKeyConfiguration = HotKeyConfiguration.saved
    private let contextReader = AccessibilityContextReader()
    private let hotKeyManager = HotKeyManager()
    private let model = SearchViewModel()
    private let settingsModel = SettingsModel()
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var firstRunWindow: NSWindow?
    private var statusMenuItem: NSMenuItem?
    private var openMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePanel()
        configureSettingsWindow()
        configureStatusItem()
        registerHotKey(hotKeyConfiguration)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyDidChange(_:)),
            name: .myssHotKeyDidChange,
            object: nil
        )

        if ApplicationPaths.isSearchDataReady {
            Task { await SemanticSearchEngine.shared.prewarm() }
        } else {
            showFirstRunWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
        SemanticSearchEngine.shared.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let backend = SemanticSearchEngine.shared.lifecycleState
        statusMenuItem?.title = "検索バックエンド　\(backend.label)"
        openMenuItem?.title = "myssを開く（\(hotKeyConfiguration.displayName)）"
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

    private func configureSettingsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "myss設定"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: settingsModel))
        settingsWindow = window
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "myss")
        let menu = NSMenu()
        menu.delegate = self
        let openItem = menu.addItem(withTitle: "myssを開く（\(hotKeyConfiguration.displayName)）", action: #selector(openFromMenu), keyEquivalent: "")
        openMenuItem = openItem
        let statusItem = menu.addItem(withTitle: "検索バックエンド　確認中", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        statusMenuItem = statusItem
        menu.addItem(.separator())
        menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        self.statusItem = item
    }

    private func registerHotKey(_ configuration: HotKeyConfiguration) {
        let result = hotKeyManager.register(configuration: configuration) { [weak self] in self?.showPanel() }
        settingsModel.setHotKeyResult(result)
        if case .success = result {
            hotKeyConfiguration = configuration
        } else {
            settingsModel.hotKey = hotKeyConfiguration
        }
    }

    @objc private func hotKeyDidChange(_ notification: Notification) {
        guard let configuration = notification.object as? HotKeyConfiguration else { return }
        registerHotKey(configuration)
    }

    @objc private func openFromMenu() { showPanel() }

    @objc private func openSettings() {
        settingsModel.refreshPermissions()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func showFirstRunWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "myssの準備"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FirstRunView(settings: settingsModel) { [weak window] in
            window?.close()
        })
        window.center()
        window.makeKeyAndOrderFront(nil)
        firstRunWindow = window
        NSApp.activate()
    }

    private func showPanel() {
        let context = AXIsProcessTrusted() ? contextReader.capture() : .empty
        model.begin(with: context)
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
