import Cocoa
import FlutterMacOS
import Darwin

// 与 C 层 PN_STROKE_POINT 对应的结构体，需放在顶层以便 @convention(c) 使用
struct PN_STROKE_POINT {
  var x: Float
  var y: Float
  var pressure: Float
  var timestamp: Int64
  var tool: Int32
  var phase: Int32
}

/// 手写笔记原生插件（macOS实现）
class HandwritingNativePlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var documents: [String: OpaquePointer?] = [:] // docId -> PN_DOC_HANDLE映射
  private let documentsLock = NSLock()
  
  // 动态库句柄
  private var dylibHandle: UnsafeMutableRawPointer?
  
  // C API函数指针类型定义
  typealias PN_XournalInitFunc = @convention(c) (UnsafePointer<CChar>?) -> Int32
  typealias PN_XournalShutdownFunc = @convention(c) () -> Int32
  typealias PN_XournalDocCreateFunc = @convention(c) (UnsafeMutablePointer<OpaquePointer?>?, UnsafePointer<CChar>?) -> Int32
  typealias PN_XournalDocOpenFunc = @convention(c) (UnsafeMutablePointer<OpaquePointer?>?, UnsafePointer<CChar>?) -> Int32
  typealias PN_XournalDocOpenPdfFunc = @convention(c) (UnsafeMutablePointer<OpaquePointer?>?, UnsafePointer<CChar>?, Int32) -> Int32
  typealias PN_XournalDocSaveFunc = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
  typealias PN_XournalDocCloseFunc = @convention(c) (OpaquePointer?) -> Int32
  typealias PN_XournalDocHandleStrokeFunc = @convention(c) (OpaquePointer?, UnsafeRawPointer?, Int32) -> Int32
  typealias PN_XournalDocRenderPageToPngFunc = @convention(c) (OpaquePointer?, Int32, UnsafePointer<CChar>?, Int32, Int32, UnsafePointer<CChar>?) -> Int32
  typealias PN_XournalDocGetPageCountFunc = @convention(c) (OpaquePointer?, UnsafeMutablePointer<Int32>?) -> Int32
  typealias PN_XournalDocGetPageSizeFunc = @convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<Double>?, UnsafeMutablePointer<Double>?) -> Int32
  
  // C API函数指针
  private var pn_xournal_init: PN_XournalInitFunc?
  private var pn_xournal_shutdown: PN_XournalShutdownFunc?
  private var pn_xournal_doc_create: PN_XournalDocCreateFunc?
  private var pn_xournal_doc_open: PN_XournalDocOpenFunc?
  private var pn_xournal_doc_open_pdf: PN_XournalDocOpenPdfFunc?
  private var pn_xournal_doc_save: PN_XournalDocSaveFunc?
  private var pn_xournal_doc_close: PN_XournalDocCloseFunc?
  private var pn_xournal_doc_handle_stroke: PN_XournalDocHandleStrokeFunc?
  private var pn_xournal_doc_render_page_to_png: PN_XournalDocRenderPageToPngFunc?
  private var pn_xournal_doc_get_page_count: PN_XournalDocGetPageCountFunc?
  private var pn_xournal_doc_get_page_size: PN_XournalDocGetPageSizeFunc?
  
  /// 加载动态库
  private func loadDynamicLibrary() -> Bool {
    // 动态库路径（待构建后确定实际路径）
    // 优先尝试从bundle中加载，如果失败则尝试绝对路径
    let possiblePaths = [
      Bundle.main.path(forResource: "libponynotes_xournalpp", ofType: "dylib"),
      "/Users/kuncao/github.com/PonyNotes-IO/PonyNotes-New/binaries/macos/libponynotes_xournalpp.dylib",
      "/usr/local/lib/libponynotes_xournalpp.dylib",
    ].compactMap { $0 }
    
    for path in possiblePaths {
      if FileManager.default.fileExists(atPath: path) {
        print("📚 [HandwritingNativePlugin] Attempting to load dynamic library from: \(path)")
        
        let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
        if handle != nil {
          dylibHandle = handle
          print("✅ [HandwritingNativePlugin] Dynamic library loaded successfully")
          
          // 加载所有函数指针
          if loadFunctionPointers() {
            return true
          } else {
            dlclose(handle)
            dylibHandle = nil
          }
        } else {
          if let error = dlerror() {
            print("❌ [HandwritingNativePlugin] Failed to load dynamic library: \(String(cString: error))")
          }
        }
      }
    }
    
    print("⚠️ [HandwritingNativePlugin] Dynamic library not found, using placeholder implementation")
    return false
  }
  
  /// 加载函数指针
  private func loadFunctionPointers() -> Bool {
    guard let handle = dylibHandle else { return false }
    
    // 辅助函数：从dlsym获取函数指针
    func getFunction<T>(_ name: String) -> T? {
      dlerror() // 清除之前的错误
      guard let symbol = dlsym(handle, name) else {
        return nil
      }
      return unsafeBitCast(symbol, to: T.self)
    }
    
    // 加载各个函数指针（macOS下C函数符号有下划线前缀）
    pn_xournal_init = getFunction("_pn_xournal_init")
    pn_xournal_shutdown = getFunction("_pn_xournal_shutdown")
    pn_xournal_doc_create = getFunction("_pn_xournal_doc_create")
    pn_xournal_doc_open = getFunction("_pn_xournal_doc_open")
    pn_xournal_doc_open_pdf = getFunction("_pn_xournal_doc_open_pdf")
    pn_xournal_doc_save = getFunction("_pn_xournal_doc_save")
    pn_xournal_doc_close = getFunction("_pn_xournal_doc_close")
    pn_xournal_doc_handle_stroke = getFunction("_pn_xournal_doc_handle_stroke")
    pn_xournal_doc_render_page_to_png = getFunction("_pn_xournal_doc_render_page_to_png")
    pn_xournal_doc_get_page_count = getFunction("_pn_xournal_doc_get_page_count")
    pn_xournal_doc_get_page_size = getFunction("_pn_xournal_doc_get_page_size")
    
    // 检查是否有错误
    if let error = dlerror() {
      print("❌ [HandwritingNativePlugin] Failed to load function pointers: \(String(cString: error))")
      return false
    }
    
    // 检查所有必需的函数是否都已加载
    let allLoaded = pn_xournal_init != nil &&
                    pn_xournal_shutdown != nil &&
                    pn_xournal_doc_create != nil &&
                    pn_xournal_doc_open != nil &&
                    pn_xournal_doc_open_pdf != nil &&
                    pn_xournal_doc_save != nil &&
                    pn_xournal_doc_close != nil &&
                    pn_xournal_doc_handle_stroke != nil &&
                    pn_xournal_doc_render_page_to_png != nil &&
                    pn_xournal_doc_get_page_count != nil &&
                    pn_xournal_doc_get_page_size != nil
    
    if allLoaded {
      print("✅ [HandwritingNativePlugin] All function pointers loaded successfully")
    } else {
      print("⚠️ [HandwritingNativePlugin] Some function pointers failed to load")
    }
    
    return allLoaded
  }
  
  deinit {
    // 清理动态库
    if let handle = dylibHandle {
      if pn_xournal_shutdown != nil {
        pn_xournal_shutdown?()
      }
      dlclose(handle)
    }
  }
  
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
    
    // 尝试加载动态库
    _ = instance.loadDynamicLibrary()
    
    print("✅ [HandwritingNativePlugin] MethodChannel registered")
  }
  
  /// Flutter 引擎通过 Objective-C 运行时调用的入口
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    handleMethodCall(call: call, result: result)
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
      
    case "open_pdf":
      handleOpenPdf(call: call, result: result)
      
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
    
    // 如果动态库已加载，调用实际的初始化函数
    if let initFunc = pn_xournal_init {
      configJson.withCString { cString in
        let ret = initFunc(cString)
        if ret == 0 {
          print("✅ [HandwritingNativePlugin] Dynamic library initialized successfully")
          result(true)
        } else {
          print("❌ [HandwritingNativePlugin] Failed to initialize dynamic library, error code: \(ret)")
          result(FlutterError(code: "INIT_FAILED", message: "Failed to initialize dynamic library", details: ret))
        }
      }
    } else {
      // 动态库未加载，尝试加载
      if loadDynamicLibrary() {
        if let initFunc = pn_xournal_init {
          configJson.withCString { cString in
            let ret = initFunc(cString)
            if ret == 0 {
              print("✅ [HandwritingNativePlugin] Dynamic library initialized successfully")
              result(true)
            } else {
              print("❌ [HandwritingNativePlugin] Failed to initialize dynamic library, error code: \(ret)")
              result(FlutterError(code: "INIT_FAILED", message: "Failed to initialize dynamic library", details: ret))
            }
          }
        } else {
          print("⚠️ [HandwritingNativePlugin] Dynamic library loaded but init function not found, using placeholder")
          result(true)
        }
      } else {
        print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder implementation")
        result(true)
      }
    }
  }
  
  /// 创建文档
  private func handleCreateDoc(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let optionsJson = args["options"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing options parameter", details: nil))
      return
    }
    
    print("📄 [HandwritingNativePlugin] Creating document with options: \(optionsJson)")
    
    // 如果动态库已加载，调用实际的创建函数
    if let createFunc = pn_xournal_doc_create {
      var docHandle: OpaquePointer?
      optionsJson.withCString { cString in
        let ret = createFunc(&docHandle, cString)
        if ret == 0, let handle = docHandle {
          let docId = UUID().uuidString
          documentsLock.lock()
          documents[docId] = handle
          documentsLock.unlock()
          print("✅ [HandwritingNativePlugin] Document created with ID: \(docId)")
          result(docId)
        } else {
          print("❌ [HandwritingNativePlugin] Failed to create document, error code: \(ret)")
          result(FlutterError(code: "CREATE_FAILED", message: "Failed to create document", details: ret))
        }
      }
    } else {
      // 占位实现
      let docId = UUID().uuidString
      documentsLock.lock()
      documents[docId] = nil // 占位
      documentsLock.unlock()
      print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder")
      print("✅ [HandwritingNativePlugin] Document created with ID: \(docId)")
      result(docId)
    }
  }
  
  /// 打开文档
  private func handleOpenDoc(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let xoppPath = args["path"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing path parameter", details: nil))
      return
    }
    
    print("📂 [HandwritingNativePlugin] Opening document from: \(xoppPath)")
    
    // 如果动态库已加载，调用实际的打开函数
    if let openFunc = pn_xournal_doc_open {
      var docHandle: OpaquePointer?
      xoppPath.withCString { cString in
        let ret = openFunc(&docHandle, cString)
        if ret == 0, let handle = docHandle {
          let docId = UUID().uuidString
          documentsLock.lock()
          documents[docId] = handle
          documentsLock.unlock()
          print("✅ [HandwritingNativePlugin] Document opened with ID: \(docId)")
          result(docId)
        } else {
          print("❌ [HandwritingNativePlugin] Failed to open document, error code: \(ret)")
          result(FlutterError(code: "OPEN_FAILED", message: "Failed to open document", details: ret))
        }
      }
    } else {
      // 占位实现
      let docId = UUID().uuidString
      documentsLock.lock()
      documents[docId] = nil // 占位
      documentsLock.unlock()
      print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder")
      print("✅ [HandwritingNativePlugin] Document opened with ID: \(docId)")
      result(docId)
    }
  }
  
  /// 打开PDF文档
  private func handleOpenPdf(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let pdfPath = args["path"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing path parameter", details: nil))
      return
    }
    
    // attachToDocument: 0=替换当前文档, 1=附加到当前文档（默认0）
    let attachToDocument = (args["attachToDocument"] as? Bool) ?? false
    let attachInt: Int32 = attachToDocument ? 1 : 0
    
    print("📄 [HandwritingNativePlugin] Opening PDF from: \(pdfPath), attach: \(attachToDocument)")
    
    // 如果动态库已加载，调用实际的PDF打开函数
    if let openPdfFunc = pn_xournal_doc_open_pdf {
      var docHandle: OpaquePointer?
      pdfPath.withCString { cString in
        let ret = openPdfFunc(&docHandle, cString, attachInt)
        if ret == 0, let handle = docHandle {
          let docId = UUID().uuidString
          documentsLock.lock()
          documents[docId] = handle
          documentsLock.unlock()
          print("✅ [HandwritingNativePlugin] PDF opened with ID: \(docId)")
          result(docId)
        } else {
          print("❌ [HandwritingNativePlugin] Failed to open PDF, error code: \(ret)")
          result(FlutterError(code: "OPEN_PDF_FAILED", message: "Failed to open PDF document", details: ret))
        }
      }
    } else {
      // 占位实现
      let docId = UUID().uuidString
      documentsLock.lock()
      documents[docId] = nil // 占位
      documentsLock.unlock()
      print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder")
      print("✅ [HandwritingNativePlugin] PDF opened (placeholder) with ID: \(docId)")
      result(docId)
    }
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
    guard let docHandle = documents[docId] else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    documentsLock.unlock()
    
    // 如果动态库已加载且文档句柄有效，调用实际的保存函数
    if let saveFunc = pn_xournal_doc_save, let handle = docHandle {
      xoppPath.withCString { cString in
        let ret = saveFunc(handle, cString)
        if ret == 0 {
          print("✅ [HandwritingNativePlugin] Document saved")
          result(true)
        } else {
          print("❌ [HandwritingNativePlugin] Failed to save document, error code: \(ret)")
          result(FlutterError(code: "SAVE_FAILED", message: "Failed to save document", details: ret))
        }
      }
    } else {
      // 占位实现
      print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder")
      print("✅ [HandwritingNativePlugin] Document saved")
      result(true)
    }
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
    guard let docHandle = documents[docId] else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    
    // 如果动态库已加载且文档句柄有效，调用实际的关闭函数
    if let closeFunc = pn_xournal_doc_close, let handle = docHandle {
      let ret = closeFunc(handle)
      if ret != 0 {
        print("⚠️ [HandwritingNativePlugin] Failed to close document, error code: \(ret)")
      }
    }
    
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
    guard let docHandle = documents[docId] else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    documentsLock.unlock()
    
    // 将Flutter传入的points转换为PN_STROKE_POINT数组
    var strokePoints: [PN_STROKE_POINT] = []
    for pointDict in points {
      guard let x = pointDict["x"] as? Double,
            let y = pointDict["y"] as? Double,
            let pressure = pointDict["pressure"] as? Double,
            let timestamp = pointDict["timestamp"] as? Int64,
            let tool = pointDict["tool"] as? Int,
            let phase = pointDict["phase"] as? Int else {
        print("⚠️ [HandwritingNativePlugin] Invalid point data, skipping")
        continue
      }
      
      strokePoints.append(PN_STROKE_POINT(
        x: Float(x),
        y: Float(y),
        pressure: Float(pressure),
        timestamp: timestamp,
        tool: Int32(tool),
        phase: Int32(phase)
      ))
    }
    
    if strokePoints.isEmpty {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "No valid points provided", details: nil))
      return
    }
    
    // 如果动态库已加载且文档句柄有效，调用实际的笔迹处理函数
    if let strokeFunc = pn_xournal_doc_handle_stroke, let handle = docHandle {
      strokePoints.withUnsafeBufferPointer { buffer in
        let ret = strokeFunc(handle, UnsafeRawPointer(buffer.baseAddress), Int32(strokePoints.count))
        if ret == 0 {
          print("✅ [HandwritingNativePlugin] Stroke handled successfully")
          result(true)
        } else {
          print("❌ [HandwritingNativePlugin] Failed to handle stroke, error code: \(ret)")
          result(FlutterError(code: "STROKE_FAILED", message: "Failed to handle stroke", details: ret))
        }
      }
    } else {
      // 占位实现
      print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder")
      print("✅ [HandwritingNativePlugin] Stroke handled")
      result(true)
    }
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
    guard let docHandle = documents[docId] else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    documentsLock.unlock()
    
    // 获取options（可选）
    let optionsJson = (args["options"] as? String) ?? "{}"
    
    // 如果动态库已加载且文档句柄有效，调用实际的渲染函数
    if let renderFunc = pn_xournal_doc_render_page_to_png, let handle = docHandle {
      pngPath.withCString { pngCString in
        optionsJson.withCString { optionsCString in
          let ret = renderFunc(handle, Int32(pageIndex), pngCString, Int32(width), Int32(height), optionsCString)
          if ret == 0 {
            print("✅ [HandwritingNativePlugin] Page rendered successfully")
            result(pngPath)
          } else {
            print("❌ [HandwritingNativePlugin] Failed to render page, error code: \(ret)")
            result(FlutterError(code: "RENDER_FAILED", message: "Failed to render page", details: ret))
          }
        }
      }
    } else {
      // 占位实现
      print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder")
      print("✅ [HandwritingNativePlugin] Page rendered")
      result(pngPath)
    }
  }
  
  /// 获取页面数量
  private func handleGetPageCount(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let docId = args["docId"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing docId parameter", details: nil))
      return
    }
    
    documentsLock.lock()
    guard let docHandle = documents[docId] else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    documentsLock.unlock()
    
    // 如果动态库已加载且文档句柄有效，调用实际的获取页面数量函数
    if let getPageCountFunc = pn_xournal_doc_get_page_count, let handle = docHandle {
      var count: Int32 = 0
      let ret = getPageCountFunc(handle, &count)
      if ret == 0 {
        print("✅ [HandwritingNativePlugin] Page count: \(count)")
        result(Int(count))
      } else {
        print("❌ [HandwritingNativePlugin] Failed to get page count, error code: \(ret)")
        result(FlutterError(code: "GET_PAGE_COUNT_FAILED", message: "Failed to get page count", details: ret))
      }
    } else {
      // 占位实现
      print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder")
      result(1)
    }
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
    guard let docHandle = documents[docId] else {
      documentsLock.unlock()
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    documentsLock.unlock()
    
    // 如果动态库已加载且文档句柄有效，调用实际的获取页面尺寸函数
    if let getPageSizeFunc = pn_xournal_doc_get_page_size, let handle = docHandle {
      var width: Double = 0
      var height: Double = 0
      let ret = getPageSizeFunc(handle, Int32(pageIndex), &width, &height)
      if ret == 0 {
        print("✅ [HandwritingNativePlugin] Page \(pageIndex) size: \(width)x\(height)")
        result([
          "width": width,
          "height": height,
        ])
      } else {
        print("❌ [HandwritingNativePlugin] Failed to get page size, error code: \(ret)")
        result(FlutterError(code: "GET_PAGE_SIZE_FAILED", message: "Failed to get page size", details: ret))
      }
    } else {
      // 占位实现：返回A4尺寸
      print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder")
      result([
        "width": 595.275591,
        "height": 841.889764,
      ])
    }
  }
}

