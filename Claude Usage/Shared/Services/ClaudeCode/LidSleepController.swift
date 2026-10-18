//
//  LidSleepController.swift
//  Claude Usage
//
//  Keeps a MacBook awake with the lid closed while keep-awake is holding.
//
//  macOS always sleeps on lid close (unless on power with an external
//  display); only `pmset -a disablesleep 1` prevents that, and it needs root.
//  With the user's one-time admin approval, a sudoers rule lets the app run
//  exactly `pmset -a disablesleep 1` and `pmset -a disablesleep 0` without a
//  password. The app turns it on only while keeping awake and always back off.
//

import AppKit
import IOKit.ps

enum LidSleepController {
    private static let rulePath = "/etc/sudoers.d/claude-usage-lid"
    private static let pmset = "/usr/bin/pmset"
    /// Never keep the Mac awake with the lid closed on battery below this
    static let minimumBatteryPercent = 20

    /// Last state the app set; nil = unknown (not touched yet this launch)
    private static var appliedDisabled: Bool?

    // MARK: - Permission

    /// Whether the sudoers rule is installed
    static var isPermissionInstalled: Bool {
        FileManager.default.fileExists(atPath: rulePath)
    }

    /// Installs the rule after the macOS admin password prompt. The rule is
    /// validated with visudo before it's moved into place: a broken sudoers
    /// file would break sudo for the whole Mac. Returns an error, nil on success.
    static func installPermission() -> String? {
        let user = NSUserName()
        guard user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            return "Unsupported user name."
        }
        let rule = "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 1, \(pmset) -a disablesleep 0"
        let script = "f=$(/usr/bin/mktemp) && printf '%s\\n' '\(rule)' > $f && /usr/sbin/visudo -cf $f "
            + "&& /usr/bin/install -m 0440 -o root -g wheel $f \(rulePath); rc=$?; /bin/rm -f $f; exit $rc"
        return runAsAdmin(script, prompt: "Claude Usage wants permission to keep your Mac awake with the lid closed.")
    }

    /// Restores normal sleep and removes the rule (admin prompt).
    static func removePermission() -> String? {
        let error = runAsAdmin("\(pmset) -a disablesleep 0; /bin/rm -f \(rulePath)",
                               prompt: "Claude Usage wants to remove its permission to change lid sleep.")
        if error == nil { appliedDisabled = false }
        return error
    }

    /// `do shell script … with administrator privileges` shows the standard
    /// macOS password dialog. Returns an error description, nil on success.
    private static func runAsAdmin(_ shell: String, prompt: String) -> String? {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with prompt \"\(prompt)\" with administrator privileges"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return nil }
        if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 { return "Cancelled." }
        return errorInfo[NSAppleScript.errorMessage] as? String ?? "Couldn't change the setting."
    }

    // MARK: - Switching

    /// Turns lid-closed sleep prevention on/off. No-op when unchanged or when
    /// the permission isn't installed (`sudo -n` never prompts).
    static func setSleepDisabled(_ disabled: Bool) {
        guard appliedDisabled != disabled else { return }
        guard isPermissionInstalled else { appliedDisabled = false; return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", pmset, "-a", "disablesleep", disabled ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { appliedDisabled = disabled }
        } catch {
            // appliedDisabled unchanged, so the next update retries
        }
    }

    /// Restores normal sleep regardless of what this launch did, e.g. at
    /// startup after a crash left it disabled.
    static func resetToNormalSleep() {
        appliedDisabled = nil
        setSleepDisabled(false)
    }

    // MARK: - Battery

    /// True when running on battery below the minimum charge
    static var batteryTooLow: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 100
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = max > 0 ? current * 100 / max : 100
            return onBattery && percent < minimumBatteryPercent
        }
        return false
    }
}
