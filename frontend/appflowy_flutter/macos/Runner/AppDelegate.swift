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
        // 只恢复应用的内容窗口，跳过 NSPanel 等系统辅助面板。
        // 系统的「拼写和语法」面板（NSSpellChecker.spellingPanel，本质是 NSSpellingPanel/NSPanel）
        // 也存在于 NSApp.windows 中，若一并 makeKeyAndOrderFront 会使其在重新激活应用时自动弹出。
        for window in sender.windows where !(window is NSPanel) {
            window.makeKeyAndOrderFront(self)
        }
    }

    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
