import AppKit
import SwiftUI
import ServiceManagement

final class PanelModel: ObservableObject {
    let speaker = Speaker()
    init() {
        speaker.changed = { [weak self] in self?.objectWillChange.send() }
    }
}

final class LoginPreference: ObservableObject {
    private let service = SMAppService.mainApp
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var message: String?
    func refresh() { status = service.status }
    func set(_ enabled: Bool) {
        message = nil
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch { message = error.localizedDescription }
        refresh()
    }
}

enum VolumeStyle: String {
    case slider, dial
    static let key = "volumeControlStyle"
}

struct SettingsPanel: View {
    @AppStorage(VolumeStyle.key) private var style: VolumeStyle = .slider
    @ObservedObject var login: LoginPreference
    let advanced: () -> Void
    @AppStorage("keepSpeakerConnected") private var keepConnected = true
    let connectionChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { login.status == .enabled || login.status == .requiresApproval }, set: login.set)) {
                Text("Open at login").font(.headline)
            }.toggleStyle(.switch)
            Text("Show Volufier in the menu bar when you log in to this Mac.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if login.status == .requiresApproval {
                Text("Allow Volufier in Login Items to finish enabling startup.").font(.callout)
            }
            if let message = login.message { Text(message).font(.callout).foregroundStyle(.red) }
            if login.status == .requiresApproval || login.message != nil {
                Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            Divider()
            HStack {
                Text("Volume control")
                Spacer()
                Picker("Volume control", selection: $style) {
                    Text("Slider").tag(VolumeStyle.slider)
                    Text("Dial").tag(VolumeStyle.dial)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 145)
            }
            Toggle("Keep speakers connected", isOn: $keepConnected).toggleStyle(.switch)
                .onChange(of: keepConnected, perform: connectionChanged)
            Button("Advanced", action: advanced)
            Divider()
            HStack { Spacer(); Button("Quit App") { NSApp.terminate(nil) } }
        }
        .padding(20).frame(width: 345)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in login.refresh() }
    }
}


final class VolumeWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    var dismiss: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismiss?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = PanelModel()
    private let login = LoginPreference()
    private var volumeWindow: VolumeWindow?
    private var settingsWindow: NSWindow?
    private var advanced = false
    private let menu = NSMenu()
    private var item: NSStatusItem!
    private var localClicks: Any?
    private var globalClicks: Any?
    private var iconRect = NSRect.zero
    private var keepConnected: Bool { UserDefaults.standard.bool(forKey: "keepSpeakerConnected") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["keepSpeakerConnected": true])
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "hifispeaker.2", accessibilityDescription: "Volufier")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Volufier"
            button.setAccessibilityLabel("Volufier")
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(toggle)
        }
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        if keepConnected { model.speaker.ensureConnection(advanced: false) }
    }

    private func syncConnection() {
        if keepConnected || advanced || volumeWindow?.isVisible == true {
            model.speaker.ensureConnection(advanced: advanced)
        } else { model.speaker.stop() }
    }

    private func anchor(click: NSPoint?) -> (screen: NSScreen, icon: NSRect)? {
        guard let b = item.button, let window = b.window else { return nil }
        let original = window.convertToScreen(b.convert(b.bounds, to: nil))
        let pointer = click ?? NSPoint(x: original.midX,y: original.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? window.screen else { return nil }
        let bottom = menuBarBottom(on: screen)
        if screen.frame.contains(NSPoint(x: original.midX, y: original.midY)),
           click == nil || original.insetBy(dx: -2, dy: -2).contains(pointer) {
            return (screen, NSRect(x: original.minX, y: bottom, width: original.width, height: screen.frame.maxY - bottom))
        }
        // AppKit can report the primary status window for a click on a mirrored menu bar.
        return (screen, NSRect(x: pointer.x - original.width / 2, y: bottom,
                               width: original.width, height: screen.frame.maxY - bottom))
    }

    private func menuBarBottom(on screen: NSScreen) -> CGFloat {
        // The BenQ and the notched internal display have different menu-bar heights.
        // Window bounds and layer are sufficient; window titles are unnecessary.
        if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let display = CGDisplayBounds(id.uint32Value)
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            for w in windows {
                guard (w[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)),
                      let d = w[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: d),
                      abs(rect.minX - display.minX) < 1, abs(rect.minY - display.minY) < 1,
                      abs(rect.width - display.width) < 2, (18...60).contains(rect.height) else { continue }
                return screen.frame.maxY - rect.height
            }
        }
        let inset = screen.frame.maxY - screen.visibleFrame.maxY
        return screen.frame.maxY - ((18...60).contains(inset) ? inset : max(NSStatusBar.system.thickness, screen.safeAreaInsets.top))
    }

    private func showVolume(click: NSPoint?) {
        guard let a = anchor(click: click) else { return }
        let dial = UserDefaults.standard.string(forKey: VolumeStyle.key) == VolumeStyle.dial.rawValue
        let host: NSViewController = dial ? NSHostingController(rootView: DialPanel(model: model))
                                         : NSHostingController(rootView: VolumePanel(model: model))
        let size = host.view.fittingSize
        let frame = MenuPlacement.volumeFrame(size: size, horizontal: a.icon.midX, barBottom: a.icon.minY, screen: a.screen.frame)
        let panel = VolumeWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentViewController = host
        panel.appearance = dial ? NSAppearance(named: .vibrantDark) : nil
        panel.dismiss = { [weak self] in self?.hideVolume() }
        panel.setFrame(frame, display: false)
        volumeWindow = panel
        iconRect = a.icon
        panel.makeKeyAndOrderFront(nil)
        syncConnection()
        model.speaker.refreshLevel()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClicks = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            if e.window !== self?.volumeWindow && e.window !== self?.item.button?.window { self?.hideVolume() }
            return e
        }
        globalClicks = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            guard let self, !self.iconRect.contains(NSEvent.mouseLocation) else { return }
            self.hideVolume()
        }
    }

    private func hideVolume() {
        if let monitor = localClicks { NSEvent.removeMonitor(monitor); localClicks = nil }
        if let monitor = globalClicks { NSEvent.removeMonitor(monitor); globalClicks = nil }
        guard let window = volumeWindow else { return }
        window.orderOut(nil)
        volumeWindow = nil
        syncConnection()
    }

    @objc private func toggle() {
        let point = NSEvent.mouseLocation
        if let e = NSApp.currentEvent, e.type == .rightMouseUp || e.modifierFlags.contains(.control) {
            hideVolume()
            guard let a = anchor(click: point) else { return }
            let top = MenuPlacement.menuTop(click: point, barBottom: a.icon.minY, width: menu.size.width, screen: a.screen.frame)
            menu.popUp(positioning: nil, at: top, in: nil)
        } else if volumeWindow?.isVisible == true, iconRect.contains(point) {
            hideVolume()
        } else {
            hideVolume(); showVolume(click: point)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settingsWindow?.isVisible == true { settingsWindow?.makeKeyAndOrderFront(nil) }
        else if volumeWindow == nil { showVolume(click: nil) }
        return true
    }

    @objc private func showSettings() {
        hideVolume()
        advanced = false
        syncConnection()
        login.refresh()
        let root = SettingsPanel(login: login, advanced: showAdvanced, connectionChanged: { [weak self] _ in self?.syncConnection() })
        presentSettings(NSHostingController(rootView: root), title: "Volufier Settings")
    }

    private func showAdvanced() {
        advanced = true
        syncConnection()
        let root = VStack(spacing: 0) {
            HStack {
                Button(action: showSettings) { Label("Back", systemImage: "chevron.left") }
                    .keyboardShortcut("[", modifiers: .command)
                Spacer()
            }.padding(.horizontal,16).padding(.vertical,8)
            Divider()
            AdvancedPanel(model: model)
        }.frame(width: 540,height: 650)
        presentSettings(NSHostingController(rootView: root), title: "Advanced")
    }

    private func presentSettings(_ host: NSViewController, title: String) {
        let window = settingsWindow ?? NSWindow(contentRect: .zero, styleMask: [.titled,.closable],
                                                 backing: .buffered, defer: false)
        let previous = window.frame
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = host
        window.setContentSize(host.view.fittingSize)
        if settingsWindow == nil { window.center() }
        else if let screen = window.screen {
            let frame = window.frame
            let top = min(screen.visibleFrame.maxY,max(previous.maxY,screen.visibleFrame.minY + frame.height))
            let x = max(screen.visibleFrame.minX,min(previous.midX-frame.width/2,screen.visibleFrame.maxX-frame.width))
            window.setFrameTopLeftPoint(NSPoint(x: x,y: top))
        }
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ n: Notification) {
        if let w = n.object as? NSWindow, w === settingsWindow {
            settingsWindow = nil; advanced = false; syncConnection()
        }
    }
    func applicationWillTerminate(_ notification: Notification) { model.speaker.stop() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
