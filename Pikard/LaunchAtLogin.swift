import Foundation

/// Launch-at-login via a per-user LaunchAgent. This works for locally-built /
/// ad-hoc-signed apps where `SMAppService` (Background Task Management) refuses
/// to register. Writing the plist into ~/Library/LaunchAgents is enough — launchd
/// loads it automatically at the next login (RunAtLoad fires it then).
enum LaunchAtLogin {

  static let label = "dev.lsst.Pikard"

  private static var plistURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(label).plist")
  }

  /// True if the login-item plist is installed.
  static var isEnabled: Bool {
    FileManager.default.fileExists(atPath: plistURL.path)
  }

  static func setEnabled(_ enabled: Bool) throws {
    try enabled ? enable() : disable()
  }

  private static func enable() throws {
    guard let exe = Bundle.main.executablePath else { return }
    let plist: [String: Any] = [
      "Label": label,
      "ProgramArguments": [exe],
      "RunAtLoad": true,
      "LimitLoadToSessionType": "Aqua",
      "ProcessType": "Interactive",
    ]
    let dir = plistURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: plistURL, options: .atomic)
    // Don't `launchctl bootstrap` here: RunAtLoad would spawn a second copy
    // while this one is already running. The agent loads on the next login.
  }

  private static func disable() throws {
    // Best-effort unload from the current session, then remove the plist.
    let uid = getuid()
    runLaunchctl(["bootout", "gui/\(uid)/\(label)"])
    if FileManager.default.fileExists(atPath: plistURL.path) {
      try FileManager.default.removeItem(at: plistURL)
    }
  }

  @discardableResult
  private static func runLaunchctl(_ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = args
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
  }
}
