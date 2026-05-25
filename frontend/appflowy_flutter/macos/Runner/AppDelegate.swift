import Cocoa
import FlutterMacOS
import WebKit

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    
    // 启用 WebKit 开发者工具
    #if DEBUG
    if #available(macOS 13.3, *) {
      UserDefaults.standard.set(true, forKey: "WebKitDeveloperExtras")
      UserDefaults.standard.synchronize()
      print("🔧 [AppDelegate] WebKit开发者工具已启用")
    }
    #endif
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
        for window in sender.windows {
            window.makeKeyAndOrderFront(self)
        }
    }

    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
