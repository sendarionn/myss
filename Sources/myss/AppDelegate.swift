@preconcurrency import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var hotKeyConfiguration = HotKeyConfiguration.saved
    private let contextReader = AccessibilityContextReader()
    private let hotKeyManager = HotKeyManager()
    private let model = AssistantViewModel()
    private let settingsModel = SettingsModel()
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var firstRunWindow: NSWindow?
    private var statusMenuItem: NSMenuItem?
    private var openMenuItem: NSMenuItem?
    private var isCapturingContext = false

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

        if !UserDefaults.standard.bool(forKey: FirstRunView.completedKey) || !LanguageAssistant.shared.hasAPIKey {
            showFirstRunWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusMenuItem?.title = LanguageAssistant.shared.hasAPIKey ? "AI　設定済み" : "AI　未設定"
        openMenuItem?.title = "myssを開く（\(hotKeyConfiguration.displayName)）"
    }

    private func configurePanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 460),
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
        panel.contentView = NSHostingView(rootView: AssistantPanelView(model: model))
        model.onDismiss = { [weak panel] in panel?.orderOut(nil) }
        model.onOpenSettings = { [weak self, weak panel] in
            panel?.orderOut(nil)
            self?.openSettings()
        }
        self.panel = panel
    }

    private func configureSettingsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
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
        item.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "myss")
        let menu = NSMenu()
        menu.delegate = self
        let openItem = menu.addItem(withTitle: "myssを開く（\(hotKeyConfiguration.displayName)）", action: #selector(openFromMenu), keyEquivalent: "")
        openMenuItem = openItem
        let statusItem = menu.addItem(withTitle: "AI　確認中", action: nil, keyEquivalent: "")
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
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
        // 元アプリが前面にあるうちに選択文字列を取得してからパネルを出す　取得中の連続起動は無視する
        guard !isCapturingContext else { return }
        isCapturingContext = true
        Task { @MainActor in
            let context = AXIsProcessTrusted() ? await contextReader.capture() : .empty
            isCapturingContext = false
            model.begin(with: context)
            panel?.center()
            panel?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }
}
