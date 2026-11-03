import AppKit
import SwiftUI
import UserNotifications

@main
struct PomoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var engine = Engine.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(engine)
        } label: {
            MenuBarLabel().environment(engine)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        // Logo always visible; countdown appears next to it once a phase is under way.
        if engine.isIdle && engine.phase == .focus {
            Image(nsImage: Logo.menuBar(progress: 0, flowing: false))
        } else {
            HStack(spacing: 4) {
                Image(nsImage: Logo.menuBar(progress: engine.progress, flowing: engine.isRunning))
                Text(engine.isRunning ? engine.clock : "\(engine.clock) ⏸").monospacedDigit()
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var window: NSWindow?
    private var mini: MiniTimerPanel?
    private var miniTimer: Timer?

    private var miniAnimating = false
    private var dockPolicy: NSApplication.ActivationPolicy?
    private var dockBadge: String?

    /// In the Dock and ⌘-Tab (with a minutes-left badge) unless the user prefers menu-bar-only.
    @MainActor private func updateDock() {
        let e = Engine.shared
        let policy: NSApplication.ActivationPolicy = e.settings.showInDock ? .regular : .accessory
        if policy != dockPolicy {
            NSApp.setActivationPolicy(policy)
            dockPolicy = policy
        }
        let badge: String? = (e.settings.showInDock && !e.isIdle) ? "\(Int((e.remaining / 60).rounded(.up)))m" : nil
        if badge != dockBadge {
            NSApp.dockTile.badgeLabel = badge
            dockBadge = badge
        }
    }

    /// The hourglass is shown while a phase is running or paused, unless it is hidden or the main window is in front.
    /// Showing rises + fades in; hiding sinks + fades out, then orders the panel out.
    @MainActor private func updateMini() {
        let e = Engine.shared
        let mainInFront = (window?.isVisible ?? false) && NSApp.isActive && !(window?.isMiniaturized ?? true)
        let want = e.settings.miniTimerOn && !e.isIdle && !mainInFront
        guard !miniAnimating else { return }
        if want {
            if mini == nil {
                mini = MiniTimerPanel(content: MiniTimerView(onOpen: { [weak self] in self?.showWindow() },
                                                             onResize: { [weak self] in self?.mini?.fitContent() }).environment(e))
            }
            guard let m = mini, !m.isVisible else { return }
            m.clampToScreen()
            let home = m.frame
            m.alphaValue = 0
            m.setFrameOrigin(NSPoint(x: home.minX, y: home.minY - 14))
            m.orderFrontRegardless()
            miniAnimating = true
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                m.animator().alphaValue = 1
                m.animator().setFrame(home, display: true)
            }, completionHandler: { [weak self] in MainActor.assumeIsolated { self?.miniAnimating = false } })
        } else if let m = mini, m.isVisible {
            let home = m.frame
            miniAnimating = true
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                m.animator().alphaValue = 0
                m.animator().setFrame(home.offsetBy(dx: 0, dy: -14), display: true)
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    m.orderOut(nil)
                    m.setFrame(home, display: false)   // keep the remembered position
                    m.alphaValue = 1
                    self?.miniAnimating = false
                }
            })
        }
    }

    /// A real window, so opening Pomo from Applications/Spotlight always shows something —
    /// the menu-bar item can be hidden by the notch or by System Settings › Menu Bar.
    @MainActor func showWindow() {
        if window == nil {
            let host = NSHostingController(rootView: PopoverView().environment(Engine.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "Pomo"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("PomoWindow")
            if !w.setFrameUsingName("PomoWindow") { w.center() }
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // Clicking Pomo in Applications while it is already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { showWindow() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Screenshots.isActive { MainActor.assumeIsolated { Screenshots.run() }; return }
        // Show the window on a normal launch, stay quiet when started as a login item.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let asLoginItem = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        MainActor.assumeIsolated { updateDock() }
        if !asLoginItem { MainActor.assumeIsolated { showWindow() } }
        MainActor.assumeIsolated { Engine.shared.onBreakStart = { [weak self] in self?.showWindow() } }
        HotKey.register { MainActor.assumeIsolated { Engine.shared.toggleWidget() } }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.updateMini(); self?.updateDock() } }
        RunLoop.main.add(t, forMode: .common)
        miniTimer = t

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let next = UNNotificationAction(identifier: "START_NEXT", title: "Start next", options: [])
        let more3 = UNNotificationAction(identifier: "EXTEND_3", title: "+3 min more", options: [])
        let more5 = UNNotificationAction(identifier: "EXTEND_5", title: "+5 min more", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "PHASE_END", actions: [more5, more3, next], intentIdentifiers: [], options: [])
        ])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in Engine.shared.notificationsAllowed = granted }
        }
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s) else { return }
        MainActor.assumeIsolated { Engine.shared.handle(url: url) }
    }

    // Show banners even when the popover is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        Task { @MainActor in
            Engine.shared.tick()  // make sure the phase has advanced before acting
            switch action {
            case "START_NEXT": Engine.shared.start()
            // From the banner, "+N" always means more of the phase that just ended, even if clicked late.
            case "EXTEND_3": Engine.shared.extend(minutes: 3, stepBackWithin: 1800)
            case "EXTEND_5": Engine.shared.extend(minutes: 5, stepBackWithin: 1800)
            default: break
            }
        }
        completionHandler()
    }
}
