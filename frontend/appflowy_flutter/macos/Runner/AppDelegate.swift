import Cocoa
import FlutterMacOS
import WebKit

@main
class AppDelegate: FlutterAppDelegate {
  private var hasBeenActive = false

  #if DEBUG
  override func applicationDidFinishLaunching(_ notification: Notification) {
    if #available(macOS 13.3, *) {
      UserDefaults.standard.set(true, forKey: "WebKitDeveloperExtras")
      UserDefaults.standard.synchronize()
      print("🔧 [AppDelegate] WebKit开发者工具已启用")
    }
  }
  #endif

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    // 首次显示交给 Flutter；切回没有焦点窗口的应用时才补做恢复。
    if hasBeenActive && NSApp.keyWindow == nil {
      restoreMainWindowIfNeeded()
    }
    hasBeenActive = true
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    restoreMainWindowIfNeeded()
    return true
  }

  private func restoreMainWindowIfNeeded() {
    guard let window = mainFlutterWindow, NSApp.modalWindow == nil else { return }
    if window.isMiniaturized {
      window.deminiaturize(self)
    } else if !window.isVisible {
      window.makeKeyAndOrderFront(self)
    }
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
