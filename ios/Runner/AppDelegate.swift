import Flutter
import UIKit
import WebKit

// WKWebView 的瀏覽器標識只能從網頁裡讀；讀完前要留住這個 WebView。
private enum UserAgentReader {
  private static var webView: WKWebView?

  static func read(_ completion: @escaping (String?) -> Void) {
    let webView = WKWebView(frame: .zero)
    self.webView = webView
    webView.evaluateJavaScript("navigator.userAgent") { value, _ in
      completion(value as? String)
      self.webView = nil
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NightReaderChannels")
    else { return }
    let messenger = registrar.messenger()
    FlutterMethodChannel(name: "com.inkpage.reader/word_segmenter", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "wordAt" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let args = call.arguments as? [String: Any]
        guard let text = args?["text"] as? String, let offset = args?["offset"] as? Int else {
          result(nil)
          return
        }
        result(wordAt(text, offset))
      }
    // 背景瀏覽器通過 Cloudflare 檢查後，夜讀要帶著同樣的 Cookie 與瀏覽器標識
    // 去抓網頁。通行 Cookie 設成網頁程式讀不到（HttpOnly），只能從 WebKit 的
    // Cookie 存放處讀。
    FlutterMethodChannel(name: "night_reader/webview", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "getCookies":
          guard let url = call.arguments as? String, let host = URL(string: url)?.host else {
            result(FlutterError(code: "bad_args", message: "url is required", details: nil))
            return
          }
          WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let matched = cookies.filter { cookie in
              let domain = cookie.domain.hasPrefix(".")
                ? String(cookie.domain.dropFirst()) : cookie.domain
              return host == domain || host.hasSuffix("." + domain)
            }
            result(matched.isEmpty ? nil : matched.map { "\($0.name)=\($0.value)" }
              .joined(separator: "; "))
          }
        // 單獨登出一個書源：刪掉送得到這個網站的 Cookie。
        case "clearCookies":
          guard let url = call.arguments as? String, let host = URL(string: url)?.host else {
            result(FlutterError(code: "bad_args", message: "url is required", details: nil))
            return
          }
          let store = WKWebsiteDataStore.default().httpCookieStore
          store.getAllCookies { cookies in
            let matched = cookies.filter { cookie in
              let domain = cookie.domain.hasPrefix(".")
                ? String(cookie.domain.dropFirst()) : cookie.domain
              return host == domain || host.hasSuffix("." + domain)
            }
            let group = DispatchGroup()
            for cookie in matched {
              group.enter()
              store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) { result(nil) }
          }
        case "defaultUserAgent":
          UserAgentReader.read { result($0) }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    FlutterEventChannel(name: "night_reader/battery", binaryMessenger: messenger)
      .setStreamHandler(BatteryStreamHandler())
    // reader_device 只實作螢幕常亮。挖孔高度不實作：iOS 隱藏狀態列時安全區域不變，
    // Flutter 的上緣內距已經是穩定值。視窗亮度不實作：iOS 只能改整台裝置的亮度，
    // 離開 App 也不會恢復，閱讀器因此在 iOS 不顯示亮度條。
    FlutterMethodChannel(name: "night_reader/reader_device", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "setKeepScreenOn" else {
          result(FlutterMethodNotImplemented)
          return
        }
        UIApplication.shared.isIdleTimerDisabled = call.arguments as? Bool ?? false
        result(nil)
      }
    // 狀態列高度（system_bars 的 statusBarExtent）不實作，理由同上。App 內更新只在 Android。
    FlutterMethodChannel(name: "night_reader/system_bars", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "screenCornerRadius" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(screenCornerRadius())
      }
  }
}

// 換頁轉場中新頁帶的螢幕圓角。系統沒有公開 API：Telegram 正式版依機型查表，
// 它的測試程式讀 UIScreen 的 _displayCornerRadius，這裡也這樣讀；讀不到時回
// nil，就不加圓角。
private func screenCornerRadius() -> Double? {
  let key = "_displayCornerRadius"
  guard UIScreen.main.responds(to: NSSelectorFromString(key)),
    let radius = UIScreen.main.value(forKey: key) as? CGFloat, radius > 0
  else { return nil }
  return Double(radius)
}

// Flutter 引擎的 ICU 不含中文詞典，長按選詞靠系統斷詞。offset 與回傳值都是
// UTF-16 位置，與 Dart 字串一致；標點與空白不算詞，回傳 nil 讓 Dart 端只選單一字元。
private func wordAt(_ text: String, _ offset: Int) -> [Int]? {
  let string = text as NSString
  guard offset >= 0, offset < string.length else { return nil }
  guard
    let tokenizer = CFStringTokenizerCreate(
      nil, string as CFString, CFRange(location: 0, length: string.length),
      kCFStringTokenizerUnitWord, Locale(identifier: "zh-Hant") as CFLocale)
  else { return nil }
  let type = CFStringTokenizerGoToTokenAtIndex(tokenizer, offset)
  if type.isEmpty { return nil }
  let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
  guard range.location != kCFNotFound, range.length > 0 else { return nil }
  return [range.location, range.location + range.length]
}

// 電量與充電狀態；只在 Dart 端有訂閱時才開啟電池監控。
private class BatteryStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(batteryChanged),
      name: UIDevice.batteryLevelDidChangeNotification, object: nil)
    center.addObserver(
      self, selector: #selector(batteryChanged),
      name: UIDevice.batteryStateDidChangeNotification, object: nil)
    batteryChanged()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self)
    UIDevice.current.isBatteryMonitoringEnabled = false
    sink = nil
    return nil
  }

  @objc private func batteryChanged() {
    let device = UIDevice.current
    // 模擬器與取不到電量時 batteryLevel 為 -1。
    guard device.batteryLevel >= 0 else { return }
    sink?([
      "percent": Int((device.batteryLevel * 100).rounded()),
      "charging": device.batteryState == .charging || device.batteryState == .full,
    ])
  }
}
