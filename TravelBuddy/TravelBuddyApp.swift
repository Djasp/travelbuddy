import SwiftUI
import AppKit

@main
struct TravelBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences: AppPreferences
    @StateObject private var monitor: TravelTimeMonitor

    init() {
        let prefs = AppPreferences()
        _preferences = StateObject(wrappedValue: prefs)
        _monitor = StateObject(wrappedValue: TravelTimeMonitor(preferences: prefs))
    }

    var body: some Scene {
        // MenuBarExtra is de hoofd-UI van de app.
        // Omdat LSUIElement=YES staat, is dit het primaire entrypoint voor de gebruiker.
        MenuBarExtra {
            menuContent
        } label: {
            HStack(spacing: 3) {
                Image(systemName: monitor.isDelayed ? "exclamationmark.triangle.fill" : "car.fill")
                Text(monitor.menuBarTitle)
            }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        Text(monitor.travelTimeLine)

        if let baselineLine = monitor.baselineLine {
            Text(baselineLine)
        }
        if let destinationLine = monitor.destinationLine {
            Text(destinationLine)
        }
        if let lastMeasurementLine = monitor.lastMeasurementLine {
            Text(lastMeasurementLine)
        }
        if let errorLine = monitor.lastError {
            Text("⚠️ \(errorLine)")
        }

        Divider()

        Button("Ververs nu") {
            monitor.measureNow()
        }
        .disabled(monitor.isMeasuring)

        Button(monitor.isPaused ? "Hervat" : "Pauzeer") {
            monitor.togglePause()
        }

        Button("Instellingen") {
            appDelegate.openSettingsWindow(preferences: preferences, monitor: monitor)
        }

        Divider()

        Button("Stop TravelBuddy") {
            NSApplication.shared.terminate(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsWindowController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Expliciet als accessory-app draaien:
        // geen Dock-icoon, wel menubalkgedrag.
        NSApp.setActivationPolicy(.accessory)
    }

    func openSettingsWindow(preferences: AppPreferences, monitor: TravelTimeMonitor) {
        settingsWindowController.show(preferences: preferences, monitor: monitor)
    }
}

enum SettingsWindowMetrics {
    static let width: CGFloat = 520
    static let height: CGFloat = 560
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show(preferences: AppPreferences, monitor: TravelTimeMonitor) {
        let rootView = SettingsView(preferences: preferences, monitor: monitor)
            .frame(width: SettingsWindowMetrics.width, height: SettingsWindowMetrics.height)
            .preferredColorScheme(.light)
            .tint(Color(red: 0.09, green: 0.44, blue: 0.88))

        let hosting = NSHostingView(rootView: rootView)

        if let existingWindow = window {
            existingWindow.contentView = hosting
        } else {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: SettingsWindowMetrics.width, height: SettingsWindowMetrics.height),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )

            newWindow.title = "TravelBuddy Instellingen"
            newWindow.center()
            newWindow.isReleasedWhenClosed = false
            newWindow.contentView = hosting
            newWindow.minSize = NSSize(width: SettingsWindowMetrics.width, height: SettingsWindowMetrics.height)
            window = newWindow
        }

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
    }
}
