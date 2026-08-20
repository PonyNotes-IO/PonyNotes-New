import UIKit
import Flutter
import DouyinOpenSDK
import WechatOpenSDK

@main
@objc class AppDelegate: FlutterAppDelegate, DouyinOpenSDKLogDelegate, WXApiDelegate, WXApiLogDelegate {
  private var weChatSDKChannel: FlutterMethodChannel?
  private var weChatSDKRegistered = false

  private let weChatAppID = "wx3b1a7737f52a004b"
  private let weChatUniversalLink = "https://www.xiaomabiji.com/ponynotes/"

  override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let douyinDelegate = DouyinOpenSDKApplicationDelegate.sharedInstance()
    douyinDelegate.logDelegate = self
    douyinDelegate.focusUseSchemaJump = true
    douyinDelegate.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    // Keep the SDK's registration/Universal Link rejection reason in the
    // normal Flutter log. `registerApp` can return true while the subsequent
    // auth request is still rejected by the WeChat platform configuration.
    WXApi.startLog(by: WXLogLevel.detail, logDelegate: self)
    registerWeChatSDK()

    GeneratedPluginRegistrant.register(with: self)
    registerWeChatSDKChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    return handleIncomingURL(
      app,
      url,
      sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String,
      annotation: options[UIApplication.OpenURLOptionsKey.annotation],
      options: options
    )
  }

  private func handleIncomingURL(
    _ application: UIApplication,
    _ url: URL,
    sourceApplication: String?,
    annotation: Any?,
    options: [UIApplication.OpenURLOptionsKey: Any]
  ) -> Bool {
    if url.scheme == weChatAppID {
      return WXApi.handleOpen(url, delegate: self)
    }

    let result = DouyinOpenSDKApplicationDelegate.sharedInstance().application(
      application,
      open: url,
      sourceApplication: sourceApplication,
      annotation: annotation
    )
    if result {
      return true
    }
    return super.application(application, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if let url = userActivity.webpageURL,
       url.host == "www.xiaomabiji.com",
       url.path.hasPrefix("/ponynotes/") {
      return WXApi.handleOpenUniversalLink(userActivity, delegate: self)
    }

    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  func onLog(_ logInfo: String) {
    NSLog("douyin log %@", logInfo)
  }

  func onLog(_ log: String, logLevel level: WXLogLevel) {
    NSLog("wechat sdk log [\(level.rawValue)] %@", log)
    weChatSDKChannel?.invokeMethod("onSDKDiagnostic", arguments: [
      "kind": "sdk_log",
      "level": level.rawValue,
      "message": log,
    ])
  }

  private func checkWeChatUniversalLinkAfterRejectedRequest() {
#if DEBUG
    WXApi.checkUniversalLinkReady { [weak self] step, result in
      let errorInfo = result.errorInfo ?? ""
      let suggestion = result.suggestion ?? ""
      NSLog(
        "wechat universal-link check step=%ld success=%@ error=%@ suggestion=%@",
        step.rawValue,
        result.success ? "true" : "false",
        errorInfo,
        suggestion
      )
      self?.weChatSDKChannel?.invokeMethod("onSDKDiagnostic", arguments: [
        "kind": "universal_link_check",
        "step": step.rawValue,
        "success": result.success,
        "errorInfo": errorInfo,
        "suggestion": suggestion,
      ])
    }
#endif
  }

  private func registerWeChatSDKChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("wechat sdk channel registration failed: FlutterViewController unavailable")
      return
    }

    let channel = FlutterMethodChannel(
      name: "ponynotes/wechat_sdk",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self, weak controller] call, result in
      guard call.method == "requestAuth" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self = self, let controller = controller else {
        result(FlutterError(
          code: "VIEW_CONTROLLER_UNAVAILABLE",
          message: "WeChat authorization view controller is unavailable",
          details: nil
        ))
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let scope = arguments["scope"] as? String,
            let state = arguments["state"] as? String,
            !scope.isEmpty,
            !state.isEmpty else {
        result(FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "WeChat authorization scope and state are required",
          details: nil
        ))
        return
      }

      let canOpenWeChatScheme = self.canOpenWeChatScheme()
      NSLog(
        "wechat auth preflight registered=%@ installed=%@ canOpenScheme=%@",
        self.weChatSDKRegistered ? "true" : "false",
        WXApi.isWXAppInstalled() ? "true" : "false",
        canOpenWeChatScheme ? "true" : "false"
      )
      guard self.weChatSDKRegistered else {
        result([
          "registered": false,
          "installed": WXApi.isWXAppInstalled(),
          "canOpenWeChatScheme": canOpenWeChatScheme,
          "requestSent": false,
        ])
        return
      }

      guard WXApi.isWXAppInstalled() else {
        result([
          "registered": true,
          "installed": false,
          "canOpenWeChatScheme": canOpenWeChatScheme,
          "requestSent": false,
        ])
        return
      }

      let request = SendAuthReq()
      request.scope = scope
      request.state = state
      request.nonautomatic = false
      WXApi.sendAuthReq(
        request,
        viewController: self.topViewController(from: controller),
        delegate: self
      ) { sent in
        if !sent {
          self.checkWeChatUniversalLinkAfterRejectedRequest()
        }
        result([
          "registered": true,
          "installed": true,
          "canOpenWeChatScheme": canOpenWeChatScheme,
          "requestSent": sent,
          "sdkVersion": WXApi.getVersion(),
          "supportsOpenApi": WXApi.isWXAppSupport(),
        ])
      }
    }
    weChatSDKChannel = channel
  }

  /// 微信 SDK 要求在应用启动时注册，不能只在用户点击登录后临时注册。
  private func registerWeChatSDK() {
    weChatSDKRegistered = WXApi.registerApp(
      weChatAppID,
      universalLink: weChatUniversalLink
    )
    NSLog(
      "wechat sdk registration result registered=%@ installed=%@ canOpenScheme=%@",
      weChatSDKRegistered ? "true" : "false",
      WXApi.isWXAppInstalled() ? "true" : "false",
      canOpenWeChatScheme() ? "true" : "false"
    )
  }

  private func canOpenWeChatScheme() -> Bool {
    guard let url = URL(string: "weixin://") else {
      return false
    }
    return UIApplication.shared.canOpenURL(url)
  }

  private func topViewController(from controller: UIViewController) -> UIViewController {
    if let presented = controller.presentedViewController {
      return topViewController(from: presented)
    }
    if let navigationController = controller as? UINavigationController,
       let visible = navigationController.visibleViewController {
      return topViewController(from: visible)
    }
    if let tabBarController = controller as? UITabBarController,
       let selected = tabBarController.selectedViewController {
      return topViewController(from: selected)
    }
    return controller
  }

  func onResp(_ resp: BaseResp) {
    guard let authResp = resp as? SendAuthResp else {
      return
    }
    weChatSDKChannel?.invokeMethod("onAuthResponse", arguments: [
      "errCode": authResp.errCode,
      "errStr": authResp.errStr ?? "",
      "code": authResp.code ?? "",
      "state": authResp.state ?? "",
    ])
  }
}
