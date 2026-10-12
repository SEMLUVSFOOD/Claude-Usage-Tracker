import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no window restoration
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSApp.setActivationPolicy(.accessory)
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }

        ProfileManager.shared.loadProfiles()

        let manager = MenuBarManager()
        manager.setup()
        menuBarManager = manager

        // First run: nothing to show yet, so open Settings to add an account
        let profileManager = ProfileManager.shared
        if !profileManager.profiles.contains(where: { profileManager.canFetchUsage(for: $0) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                manager.openSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarManager?.cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}
