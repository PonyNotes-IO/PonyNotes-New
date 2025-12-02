import Cocoa
import FlutterMacOS

/// 手写笔记原生插件（macOS实现）
class HandwritingNativePlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var documents: [String: Any] = [:] // docId -> PN_DOC_HANDLE映射
  private let documentsLock = NSLock()
  
  /// FlutterPlugin协议要求的方法
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = HandwritingNativePlugin()
    instance.channel = FlutterMethodChannel(
      name: "handwriting_native",
      binaryMessenger: registrar.messenger
    )
    
    instance.channel?.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      instance.handleMethodCall(call: call, result: result)
    }
    
    registrar.addMethodCallDelegate(instance, channel: instance.channel!)
    
    print("✅ [HandwritingNativePlugin] MethodChannel registered")
  }
  
  /// 处理MethodChannel调用
  private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    print("📞 [HandwritingNativePlugin] Method called: \(call.method)")
    
    switch call.method {
    case "init":
      handleInit(call: call, result: result)
      
    case "create_doc":
      handleCreateDoc(call: call, result: result)
      
    case "open_doc":
      handleOpenDoc(call: call, result: result)
      
    case "save_doc":
      handleSaveDoc(call: call, result: result)
      
    case "close_doc":
      handleCloseDoc(call: call, result: result)
      
    case "handle_stroke":
      handleStroke(call: call, result: result)
      
    case "render_page":
      handleRenderPage(call: call, result: result)
      
    case "get_page_count":
      handleGetPageCount(call: call, result: result)
      
    case "get_page_size":
      handleGetPageSize(call: call, result: result)
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  // MARK: - 方法实现
  
  /// 初始化动态库
  private func handleInit(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let configJson = args["config"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing config parameter", details: nil))
      return
    }
    
    print("🔧 [HandwritingNativePlugin] Initializing with config: \(configJson)")
    
    // TODO: 调用动态库的 pn_xournal_init
    // 目前先返回成功，等待动态库构建完成后再实现
    
    result(true)
  }
  
  /// 创建文档
  private func handleCreateDoc(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let optionsJson = args["options"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing options parameter", details: nil))
      return
    }
    
    print("📄 [HandwritingNativePlugin] Creating document with options: \(optionsJson)")
    
    // TODO: 调用动态库的 pn_xournal_doc_create
    // 生成临时docId
    let docId = UUID().uuidString
    
    documentsLock.lock()
    documents[docId] = NSNull() // 占位，后续替换为实际的PN_DOC_HANDLE
    documentsLock.unlock()
    
    print("✅ [HandwritingNativePlugin] Document created with ID: \(docId)")
    result(docId)
  }
  
  /// 打开文档
  private func handleOpenDoc(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let xoppPath = args["path"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing path parameter", details: nil))
      return
    }
    
    print("📂 [HandwritingNativePlugin] Opening document from: \(xoppPath)")
    
    // TODO: 调用动态库的 pn_xournal_doc_open
    // 生成临时docId
    let docId = UUID().uuidString
    
    documentsLock.lock()
    documents[docId] = NSNull() // 占位，后续替换为实际的PN_DOC_HANDLE
    documentsLock.unlock()
    
    print("✅ [HandwritingNativePlugin] Document opened with ID: \(docId)")
    result(docId)
  }
  
  /// 保存文档
  private func handleSaveDoc(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let docId = args["docId"] as? String,
          let xoppPath = args["path"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing docId or path parameter", details: nil))
      return
    }
    
    print("💾 [HandwritingNativePlugin] Saving document \(docId) to: \(xoppPath)")
    
    documentsLock.lock()
    guard documents[docId] != nil else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    documentsLock.unlock()
    
    // TODO: 调用动态库的 pn_xournal_doc_save
    
    print("✅ [HandwritingNativePlugin] Document saved")
    result(true)
  }
  
  /// 关闭文档
  private func handleCloseDoc(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let docId = args["docId"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing docId parameter", details: nil))
      return
    }
    
    print("🗑️ [HandwritingNativePlugin] Closing document: \(docId)")
    
    documentsLock.lock()
    guard documents[docId] != nil else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    
    // TODO: 调用动态库的 pn_xournal_doc_close
    
    documents.removeValue(forKey: docId)
    documentsLock.unlock()
    
    print("✅ [HandwritingNativePlugin] Document closed")
    result(true)
  }
  
  /// 处理笔迹
  private func handleStroke(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let docId = args["docId"] as? String,
          let points = args["points"] as? [[String: Any]] else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing docId or points parameter", details: nil))
      return
    }
    
    print("✏️ [HandwritingNativePlugin] Handling stroke for document \(docId), points count: \(points.count)")
    
    documentsLock.lock()
    guard documents[docId] != nil else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    documentsLock.unlock()
    
    // TODO: 调用动态库的 pn_xournal_doc_handle_stroke
    // 需要将points转换为PN_STROKE_POINT数组
    
    print("✅ [HandwritingNativePlugin] Stroke handled")
    result(true)
  }
  
  /// 渲染页面为PNG
  private func handleRenderPage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let docId = args["docId"] as? String,
          let pageIndex = args["pageIndex"] as? Int,
          let pngPath = args["pngPath"] as? String,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing required parameters", details: nil))
      return
    }
    
    print("🎨 [HandwritingNativePlugin] Rendering page \(pageIndex) for document \(docId) to: \(pngPath)")
    print("   Size: \(width)x\(height)")
    
    documentsLock.lock()
    guard documents[docId] != nil else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    documentsLock.unlock()
    
    // TODO: 调用动态库的 pn_xournal_doc_render_page_to_png
    
    print("✅ [HandwritingNativePlugin] Page rendered")
    result(pngPath)
  }
  
  /// 获取页面数量
  private func handleGetPageCount(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let docId = args["docId"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing docId parameter", details: nil))
      return
    }
    
    documentsLock.lock()
    guard documents[docId] != nil else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    documentsLock.unlock()
    
    // TODO: 调用动态库的 pn_xournal_doc_get_page_count
    
    result(1) // 临时返回1
  }
  
  /// 获取页面尺寸
  private func handleGetPageSize(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let docId = args["docId"] as? String,
          let pageIndex = args["pageIndex"] as? Int else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing docId or pageIndex parameter", details: nil))
      return
    }
    
    documentsLock.lock()
    guard documents[docId] != nil else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    documentsLock.unlock()
    
    // TODO: 调用动态库的 pn_xournal_doc_get_page_size
    
    // 临时返回A4尺寸
    result([
      "width": 595.275591,
      "height": 841.889764,
    ])
  }
}

