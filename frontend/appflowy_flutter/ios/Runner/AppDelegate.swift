import UIKit
import Flutter
import DouyinOpenSDK

@main
@objc class AppDelegate: FlutterAppDelegate,DouyinOpenSDKLogDelegate {
  override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    DouyinOpenSDKApplicationDelegate.sharedInstance().logDelegate = self
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    let result = DouyinOpenSDKApplicationDelegate.sharedInstance().application(app, open: url, sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String, annotation: options[UIApplication.OpenURLOptionsKey.annotation] as? String)
    return result;
  }

  func onLog(_ logInfo: String) {
    NSLog("douyin log %@", logInfo)
  }
}
