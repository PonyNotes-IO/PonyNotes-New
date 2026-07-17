import UIKit
import Flutter
import DouyinOpenSDK
import StoreKit

@main
@objc class AppDelegate: FlutterAppDelegate,DouyinOpenSDKLogDelegate, SKPaymentTransactionObserver {
  override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    DouyinOpenSDKApplicationDelegate.sharedInstance().logDelegate = self
    GeneratedPluginRegistrant.register(with: self)
    SKPaymentQueue.default().add(self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    let result = DouyinOpenSDKApplicationDelegate.sharedInstance().application(app, open: url, sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String, annotation: options[UIApplication.OpenURLOptionsKey.annotation] as? String)
    if result {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
    for transaction in transactions {
      switch transaction.transactionState {
      case .purchased:
        SKPaymentQueue.default().finishTransaction(transaction)
      case .failed:
        SKPaymentQueue.default().finishTransaction(transaction)
      case .restored:
        SKPaymentQueue.default().finishTransaction(transaction)
      case .deferred:
        break
      case .purchasing:
        break
      @unknown default:
        SKPaymentQueue.default().finishTransaction(transaction)
      }
    }
  }

  func onLog(_ logInfo: String) {
    NSLog("douyin log %@", logInfo)
  }
}
