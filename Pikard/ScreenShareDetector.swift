import Foundation

/// Reports whether the screen is currently being captured / shared / recorded.
///
/// macOS exposes no *public* API for this (unlike iOS's `UIScreen.isCaptured`),
/// but the window server tracks it — that's how the system suppresses
/// notifications while you screen-share. We read the same signal via the private
/// `CGSIsScreenWatcherPresent` (renamed `SLSIsScreenWatcherPresent` in SkyLight).
/// It catches native apps (Zoom/Teams/QuickTime) *and* browser sharing
/// (Google Meet via getDisplayMedia), because the browser captures through the
/// same system mechanism.
///
/// Private symbol → fine for this personal, ad-hoc-signed build, not App-Store
/// safe. If the symbol ever disappears on a future macOS, we fail open (report
/// "not capturing") so popups keep working rather than being silently blocked
/// forever.
enum ScreenShareDetector {

  private typealias WatcherFn = @convention(c) () -> Bool

  // Resolve once. RTLD_DEFAULT (-2) searches every loaded image, so this finds
  // the symbol whether it lives in CoreGraphics or SkyLight without dlopen.
  private static let watcher: WatcherFn? = {
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    for name in ["CGSIsScreenWatcherPresent", "SLSIsScreenWatcherPresent"] {
      if let sym = dlsym(rtldDefault, name) {
        return unsafeBitCast(sym, to: WatcherFn.self)
      }
    }
    return nil
  }()

  /// True if something is currently watching/capturing the screen.
  /// Fails open (false) when the private symbol is unavailable.
  static var isScreenBeingCaptured: Bool {
    watcher?() ?? false
  }
}
