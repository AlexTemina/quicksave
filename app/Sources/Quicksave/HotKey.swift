import AppKit
import Carbon.HIToolbox
import SwiftUI

/// System-wide shortcut (⌃⌥F1 by default, changeable in Settings): brings Quicksave to the front from any app. The window glows each time, so it is easy to spot on a big screen.
/// Carbon hot keys need no Accessibility permission, but they cannot tell left from right modifiers.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    /// Opens the main window when it has been closed. Set by a view that is always alive (the menu bar label).
    var openMain: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// The shortcut as saved in Settings. Setting it saves it and swaps the live registration.
    var combo: HotKeyCombo {
        get { Database.shared.value("globalHotKey", as: HotKeyCombo.self) ?? .default }
        set { Database.shared.setValue("globalHotKey", newValue); registerKey() }
    }

    func register() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in GlobalHotKey.shared.fire() }
            return noErr
        }, 1, &spec, nil, &handler)
        registerKey()
    }

    private func registerKey() {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        let c = combo
        let id = EventHotKeyID(signature: OSType(0x5153_4B59), id: 1) // "QSKY"
        RegisterEventHotKey(c.keyCode, c.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
    }

    private func fire() {
        if NSApp.isActive, let w = mainWindow, w.isVisible, w.isKeyWindow {
            WindowGlow.flash(around: w)
            return
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let w = mainWindow, w.isVisible || w.isMiniaturized {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
            WindowGlow.flash(around: w)
        } else {
            openMain?()
        }
    }
}

/// Wires the hot key to SwiftUI's openWindow. Attach to a view that lives as long as the app.
struct HotKeyInstaller: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            GlobalHotKey.shared.openMain = { openWindow(id: "main") }
            GlobalHotKey.shared.register()
        }
    }
}

/// A borderless, click-through window laid over the main window that draws a glowing frame and fades out.
@MainActor
enum WindowGlow {
    private static var current: NSWindow?

    static func flash(around target: NSWindow) {
        current?.orderOut(nil)
        let pad: CGFloat = 24
        let frame = target.frame.insetBy(dx: -pad, dy: -pad)
        let glow = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        glow.isOpaque = false
        glow.backgroundColor = .clear
        glow.hasShadow = false
        glow.ignoresMouseEvents = true
        glow.level = .floating
        glow.isReleasedWhenClosed = false
        glow.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        glow.contentView = NSHostingView(rootView: GlowFrame(pad: pad))
        glow.alphaValue = 0
        glow.orderFront(nil)
        current = glow

        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; glow.animator().alphaValue = 1 }) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.7; glow.animator().alphaValue = 0 }) {
                    Task { @MainActor in
                        glow.orderOut(nil)
                        if current === glow { current = nil }
                    }
                }
            }
        }
    }
}

private struct GlowFrame: View {
    let pad: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        shape
            .strokeBorder(Theme.Palette.summonGlow, lineWidth: 4)
            .padding(pad - 2)
            .shadow(color: Theme.Palette.summonGlow.opacity(0.9), radius: 10)
            .shadow(color: Theme.Palette.summonGlow.opacity(0.6), radius: 20)
    }
}

/// A function key plus modifiers. Left and right modifiers count the same.
struct HotKeyCombo: Codable, Equatable {
    var control = true
    var option = true
    var command = false
    var shift = false
    /// 1...12 for F1...F12.
    var functionKey = 1

    static let `default` = HotKeyCombo()

    private static let fKeyCodes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                                    kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]

    var keyCode: UInt32 { UInt32(Self.fKeyCodes[max(1, min(12, functionKey)) - 1]) }

    var carbonModifiers: UInt32 {
        var m = 0
        if control { m |= controlKey }
        if option { m |= optionKey }
        if command { m |= cmdKey }
        if shift { m |= shiftKey }
        return UInt32(m)
    }

    var label: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + "F\(functionKey)"
    }
}
