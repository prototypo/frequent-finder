import AppKit
import Carbon.HIToolbox
import FFCore
import SwiftUI

/// A borderless panel takes keys only if it says it can.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = DeckModel()
    private var panel: OverlayPanel!
    private var lastScroll = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Non-activating: the panel takes keys without making this the active app, which macOS can refuse
        // an app with no Dock icon. The app that was in front stays in front when the panel goes away.
        panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .black
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: RootView().environment(model))

        model.hide = { [weak self] in self?.hide() }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        if !installHotKey() { model.error = "Control-Option-Space is taken by another app. Open this app again to show it." }
        Task {
            // Setup comes before the first show, so a macOS privacy question is not under the overlay.
            await model.setUp()
            watch()
            show()
        }
    }

    /// Opening the app again shows the overlay.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        show()
        return false
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.screens[0]
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        model.reload()
    }

    func hide() {
        panel.orderOut(nil)
        // Opening the app again does make it active; hiding gives the front back to the last app.
        if NSApp.isActive { NSApp.hide(nil) }
    }

    /// True when the event was used.
    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .scrollWheel {
            // Up and down scrolls the middle card's list; sideways moves between cards.
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
            let delta = event.scrollingDeltaX
            // One card per swipe: skip the glide after the fingers lift, and wait between steps.
            if event.momentumPhase.isEmpty, abs(delta) > (event.hasPreciseScrollingDeltas ? 8 : 0.5), Date().timeIntervalSince(lastScroll) > 0.45 {
                lastScroll = Date()
                model.step(delta < 0 ? 1 : -1)
            }
            return true
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        if modifiers == .command, event.keyCode == kVK_ANSI_Q { NSApp.terminate(nil) }
        guard modifiers.isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_LeftArrow: model.step(-1)
        case kVK_RightArrow: model.step(1)
        case kVK_DownArrow: model.move(1)
        case kVK_UpArrow: model.move(-1)
        case kVK_Return, kVK_ANSI_KeypadEnter: model.activate()
        case kVK_Escape: hide()
        case kVK_ANSI_E: model.edit(model.card)
        default: return false
        }
        return true
    }

    /// Reloads when anything in either vault changes. A folder watch would miss a note saved in place.
    private func watch() {
        let callback: FSEventStreamCallback = { _, _, _, _, _, _ in
            MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.model.reload() }
        }
        let paths = [model.vaults.human.path, model.vaults.claude.path] as CFArray
        guard let stream = FSEventStreamCreate(nil, callback, nil, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }
}

/// Control-Option-Space shows or hides the overlay from any app. False when the keys are taken.
// ponytail: fixed keys; read them from a setting when someone needs different ones.
@MainActor
func installHotKey() -> Bool {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.toggle() }
        return noErr
    }, 1, &spec, nil, nil)
    var ref: EventHotKeyRef?
    return RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x4646_444B, id: 1),
                               GetApplicationEventTarget(), 0, &ref) == noErr
}

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    // No Dock icon, the same as the bundle's LSUIElement, so `swift run` behaves like the app.
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}
