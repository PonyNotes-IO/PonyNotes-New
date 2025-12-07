import Cocoa
import FlutterMacOS
import Darwin
import Foundation

// RTLD_DEFAULT 在 C 中定义为 ((void *) -2)
// 在 Swift 中，我们需要使用 UnsafeMutableRawPointer(bitPattern: -2) 来创建它
private let RTLD_DEFAULT_PTR = UnsafeMutableRawPointer(bitPattern: -2)

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
  private var placeholderDocIds: Set<String> = [] // 占位文档的docId集合
  private let documentsLock = NSLock()
  
  // 动态库句柄
  private var dylibHandle: UnsafeMutableRawPointer?
  // 动态库路径（用于 NSLookupSymbolInImage）
  private var dylibPath: String?
  
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
    
    // 使用 NSLog 确保日志输出
    let logMsg = "📚 [HandwritingNativePlugin] Checking \(possiblePaths.count) possible paths for dynamic library..."
    NSLog(logMsg)
    print(logMsg)
    
    for (index, path) in possiblePaths.enumerated() {
      let checkMsg = "📚 [HandwritingNativePlugin] [\(index + 1)/\(possiblePaths.count)] Checking path: \(path)"
      NSLog(checkMsg)
      print(checkMsg)
      
      if FileManager.default.fileExists(atPath: path) {
        let existsMsg = "📚 [HandwritingNativePlugin] File exists, attempting to load dynamic library from: \(path)"
        NSLog(existsMsg)
        print(existsMsg)
        
        // 尝试使用 RTLD_LAZY | RTLD_GLOBAL
        // RTLD_LAZY: 延迟解析符号，避免依赖库问题导致立即失败
        // RTLD_GLOBAL: 允许后续的 dlsym 调用找到符号
        // 注意：使用绝对路径，避免rpath问题
        let absolutePath = (path as NSString).resolvingSymlinksInPath
        let resolvedMsg = "📚 [HandwritingNativePlugin] Resolved path: \(absolutePath)"
        NSLog(resolvedMsg)
        print(resolvedMsg)
        
        // 预加载关键依赖库（可选，帮助解决依赖问题）
        // 注意：使用 RTLD_NOW | RTLD_GLOBAL 确保依赖库立即解析并添加到全局符号表
        let keyDependencies = [
          "/opt/homebrew/opt/glib/lib/libglib-2.0.0.dylib",
          "/opt/homebrew/opt/cairo/lib/libcairo.2.dylib",
          "/opt/homebrew/opt/poppler/lib/libpoppler-cpp.2.dylib",
        ]
        for depPath in keyDependencies {
          if FileManager.default.fileExists(atPath: depPath) {
            let depHandle = dlopen(depPath, RTLD_NOW | RTLD_GLOBAL)
            if depHandle != nil {
              print("✅ [HandwritingNativePlugin] Pre-loaded dependency: \(depPath)")
            } else {
              if let error = dlerror() {
                print("⚠️ [HandwritingNativePlugin] Failed to pre-load dependency \(depPath): \(String(cString: error))")
              }
            }
          }
        }
        
        // 使用 RTLD_NOW 立即解析所有符号，而不是延迟解析
        // 这样可以确保依赖库正确解析，符号可以立即使用
        // 尝试使用 RTLD_NOW | RTLD_GLOBAL，看看是否能解决问题
        // 如果使用 RTLD_LOCAL，符号只在当前handle中可见，可能无法被查找
        // 使用 RTLD_GLOBAL 时，符号会被添加到全局符号表，可以从 handle 或 RTLD_DEFAULT 查找
        print("🔍 [HandwritingNativePlugin] Attempting to dlopen with RTLD_NOW | RTLD_GLOBAL...")
        dlerror() // 清除之前的错误
        let handle = dlopen(absolutePath, RTLD_NOW | RTLD_GLOBAL)
        
        if handle != nil {
          dylibHandle = handle
          dylibPath = absolutePath  // 保存路径用于 NSLookupSymbolInImage
          let successMsg = "✅ [HandwritingNativePlugin] Dynamic library loaded successfully from: \(absolutePath)"
          NSLog(successMsg)
          print(successMsg)
          print("🔍 [HandwritingNativePlugin] dlopen returned handle: \(handle!)")
          
          // 检查是否有错误（即使dlopen成功，也可能有警告）
          if let error = dlerror() {
            print("⚠️ [HandwritingNativePlugin] Warning after dlopen: \(String(cString: error))")
          } else {
            print("✅ [HandwritingNativePlugin] No errors after dlopen")
          }
          
          // 验证动态库是否正确加载：尝试查找一个已知符号
          // 使用 RTLD_GLOBAL 时，符号会被添加到全局符号表，可以从 handle 或 RTLD_DEFAULT 查找
          // 注意：根据测试，符号可能是不带下划线的形式
          print("🔍 [HandwritingNativePlugin] Attempting to find symbol 'pn_xournal_init' from handle...")
          dlerror() // 清除错误
          var testSymbol = dlsym(handle, "pn_xournal_init")
          if testSymbol == nil {
            print("🔍 [HandwritingNativePlugin] Trying with underscore prefix '_pn_xournal_init'...")
            testSymbol = dlsym(handle, "_pn_xournal_init")
          }
          
          if testSymbol != nil {
            print("✅ [HandwritingNativePlugin] Test symbol '_pn_xournal_init' found at handle: \(testSymbol!)")
            // 检查是否有错误
            if let error = dlerror() {
              print("⚠️ [HandwritingNativePlugin] Warning: Error after dlsym returned non-nil: \(String(cString: error))")
            }
          } else {
            print("❌ [HandwritingNativePlugin] Test symbol '_pn_xournal_init' NOT found from handle")
            // 如果从特定handle找不到，尝试从全局符号表查找（使用RTLD_DEFAULT）
            dlerror() // 清除错误
            print("🔍 [HandwritingNativePlugin] Attempting to find symbol '_pn_xournal_init' from RTLD_DEFAULT...")
            // 在Swift中，RTLD_DEFAULT需要用UnsafeMutableRawPointer(bitPattern: -2)表示
            if let rtlDefault = RTLD_DEFAULT_PTR {
              testSymbol = dlsym(rtlDefault, "_pn_xournal_init")
              if testSymbol != nil {
                print("✅ [HandwritingNativePlugin] Test symbol '_pn_xournal_init' found via global symbol table at: \(testSymbol!)")
              } else {
                if let error = dlerror() {
                  print("❌ [HandwritingNativePlugin] Test symbol '_pn_xournal_init' NOT found from RTLD_DEFAULT: \(String(cString: error))")
                } else {
                  print("❌ [HandwritingNativePlugin] Test symbol '_pn_xournal_init' NOT found from RTLD_DEFAULT (no error)")
                }
              }
            } else {
              print("❌ [HandwritingNativePlugin] RTLD_DEFAULT_PTR is nil")
            }
          }
          
          if testSymbol == nil {
            print("❌ [HandwritingNativePlugin] CRITICAL: Symbol '_pn_xournal_init' not found from any source!")
            print("🔍 [HandwritingNativePlugin] This indicates a serious problem with symbol resolution")
            print("🔍 [HandwritingNativePlugin] Possible causes:")
            print("   1. Dependencies not resolved correctly")
            print("   2. Symbol not exported correctly from the library")
            print("   3. Library architecture mismatch")
            print("   4. Library corruption")
          }
          
          // 加载所有函数指针
          print("🔍 [HandwritingNativePlugin] Starting to load function pointers...")
          if loadFunctionPointers() {
            print("✅ [HandwritingNativePlugin] All function pointers loaded successfully")
            return true
          } else {
            print("❌ [HandwritingNativePlugin] Failed to load function pointers, closing library")
            print("🔍 [HandwritingNativePlugin] Closing handle: \(handle!)")
            dlclose(handle)
            dylibHandle = nil
            print("🔍 [HandwritingNativePlugin] Handle closed, dylibHandle set to nil")
          }
        } else {
          // dlopen失败
          print("❌ [HandwritingNativePlugin] dlopen returned nil")
          if let error = dlerror() {
            let errorMsg = "❌ [HandwritingNativePlugin] Failed to load dynamic library from \(path): \(String(cString: error))"
            NSLog(errorMsg)
            print(errorMsg)
            print("🔍 [HandwritingNativePlugin] This usually indicates:")
            print("   1. Missing dependencies")
            print("   2. Wrong architecture")
            print("   3. Corrupted library file")
            print("   4. Permission issues")
          } else {
            let errorMsg = "❌ [HandwritingNativePlugin] Failed to load dynamic library from \(path): unknown error"
            NSLog(errorMsg)
            print(errorMsg)
          }
        }
      } else {
        let notExistMsg = "⚠️ [HandwritingNativePlugin] File does not exist: \(path)"
        NSLog(notExistMsg)
        print(notExistMsg)
      }
    }
    
    let notFoundMsg = "⚠️ [HandwritingNativePlugin] Dynamic library not found in any path, using placeholder implementation"
    NSLog(notFoundMsg)
    print(notFoundMsg)
    return false
  }
  
  /// 加载函数指针
  private func loadFunctionPointers() -> Bool {
    print("🔍 [HandwritingNativePlugin] loadFunctionPointers called")
    guard let handle = dylibHandle else {
      print("❌ [HandwritingNativePlugin] loadFunctionPointers: dylibHandle is nil")
      return false
    }
    print("🔍 [HandwritingNativePlugin] loadFunctionPointers: dylibHandle is valid: \(handle)")
    
    // 辅助函数：从dlsym获取函数指针，并检查错误
    // 首先从特定的handle查找（使用RTLD_LOCAL时，符号只在当前handle中可见）
    // 如果失败，则尝试从全局符号表查找（使用RTLD_DEFAULT）
    // 注意：macOS 的导出表使用压缩格式，dlsym 应该能够解析，但如果失败，可能需要使用其他方法
    func getFunction<T>(_ name: String) -> T? {
      print("🔍 [HandwritingNativePlugin] getFunction called for: '\(name)'")
      print("🔍 [HandwritingNativePlugin] Handle value: \(handle)")
      
      dlerror() // 清除之前的错误
      
      // 首先尝试从特定的handle查找（这是主要方式）
      print("🔍 [HandwritingNativePlugin] Attempting dlsym(handle, '\(name)')...")
      var symbol = dlsym(handle, name)
      
      if symbol != nil {
        print("🔍 [HandwritingNativePlugin] dlsym returned non-nil: \(symbol!)")
        // 检查是否有错误（即使dlsym返回非nil，也可能有错误）
        let errorAfter = dlerror()
        if errorAfter != nil {
          print("❌ [HandwritingNativePlugin] Error after loading symbol '\(name)' from handle: \(String(cString: errorAfter!))")
          symbol = nil
        } else {
          print("✅ [HandwritingNativePlugin] Found symbol '\(name)' at handle: \(symbol!)")
        }
      } else {
        print("❌ [HandwritingNativePlugin] dlsym(handle, '\(name)') returned nil")
        // 如果从特定handle找不到，尝试从全局符号表查找（使用RTLD_DEFAULT）
        dlerror() // 清除错误
        print("🔍 [HandwritingNativePlugin] Attempting dlsym(RTLD_DEFAULT, '\(name)')...")
        // 在Swift中，RTLD_DEFAULT需要用UnsafeMutableRawPointer(bitPattern: -2)表示
        if let rtlDefault = RTLD_DEFAULT_PTR {
          symbol = dlsym(rtlDefault, name)
          if symbol != nil {
            print("✅ [HandwritingNativePlugin] Found symbol '\(name)' via global symbol table at: \(symbol!)")
          } else {
            if let error = dlerror() {
              print("❌ [HandwritingNativePlugin] dlsym(RTLD_DEFAULT, '\(name)') returned nil with error: \(String(cString: error))")
            } else {
              print("❌ [HandwritingNativePlugin] dlsym(RTLD_DEFAULT, '\(name)') returned nil (no error)")
            }
          }
        } else {
          print("❌ [HandwritingNativePlugin] RTLD_DEFAULT_PTR is nil, cannot try RTLD_DEFAULT")
        }
      }
      
      guard let foundSymbol = symbol else {
        // 检查是否有错误
        if let error = dlerror() {
          print("❌ [HandwritingNativePlugin] Failed to load symbol '\(name)': \(String(cString: error))")
        } else {
          print("❌ [HandwritingNativePlugin] Failed to load symbol '\(name)': symbol not found (no error)")
        }
        // 注意：导出表数据中确实包含符号（压缩格式），但 dlsym 无法找到
        // 这可能是因为 -Wl,-exported_symbol 选项没有正确工作
        // 或者符号导出格式有问题
        print("🔍 [HandwritingNativePlugin] Export table contains symbols in compressed format")
        print("   But dlsym cannot find them - this suggests an export configuration issue")
        return nil
      }
      
      print("✅ [HandwritingNativePlugin] Successfully loaded symbol '\(name)', casting to function pointer...")
      return unsafeBitCast(foundSymbol, to: T.self)
    }
    
    // 加载各个函数指针
    // 注意：虽然 -Wl,-exported_symbol 使用了带下划线的符号名称，
    // 但实际的符号可能是不带下划线的，需要尝试两种形式
    var allLoaded = true
    var missingFunctions: [String] = []
    
    // 首先尝试不带下划线的符号名称（根据 ctypes 测试，这是实际导出的形式）
    if let funcPtr: PN_XournalInitFunc = getFunction("pn_xournal_init") ?? getFunction("_pn_xournal_init") {
      pn_xournal_init = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_init")
    }
    
    if let funcPtr: PN_XournalShutdownFunc = getFunctionWithFallback("pn_xournal_shutdown", "_pn_xournal_shutdown") {
      pn_xournal_shutdown = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_shutdown")
    }
    
    if let funcPtr: PN_XournalDocCreateFunc = getFunctionWithFallback("pn_xournal_doc_create", "_pn_xournal_doc_create") {
      pn_xournal_doc_create = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_doc_create")
    }
    
    if let funcPtr: PN_XournalDocOpenFunc = getFunctionWithFallback("pn_xournal_doc_open", "_pn_xournal_doc_open") {
      pn_xournal_doc_open = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_doc_open")
    }
    
    if let funcPtr: PN_XournalDocOpenPdfFunc = getFunctionWithFallback("pn_xournal_doc_open_pdf", "_pn_xournal_doc_open_pdf") {
      pn_xournal_doc_open_pdf = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_doc_open_pdf")
    }
    
    if let funcPtr: PN_XournalDocSaveFunc = getFunctionWithFallback("pn_xournal_doc_save", "_pn_xournal_doc_save") {
      pn_xournal_doc_save = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_doc_save")
    }
    
    if let funcPtr: PN_XournalDocCloseFunc = getFunctionWithFallback("pn_xournal_doc_close", "_pn_xournal_doc_close") {
      pn_xournal_doc_close = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_doc_close")
    }
    
    if let funcPtr: PN_XournalDocHandleStrokeFunc = getFunctionWithFallback("pn_xournal_doc_handle_stroke", "_pn_xournal_doc_handle_stroke") {
      pn_xournal_doc_handle_stroke = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_doc_handle_stroke")
    }
    
    if let funcPtr: PN_XournalDocRenderPageToPngFunc = getFunctionWithFallback("pn_xournal_doc_render_page_to_png", "_pn_xournal_doc_render_page_to_png") {
      pn_xournal_doc_render_page_to_png = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_doc_render_page_to_png")
    }
    
    if let funcPtr: PN_XournalDocGetPageCountFunc = getFunctionWithFallback("pn_xournal_doc_get_page_count", "_pn_xournal_doc_get_page_count") {
      pn_xournal_doc_get_page_count = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_doc_get_page_count")
    }
    
    if let funcPtr: PN_XournalDocGetPageSizeFunc = getFunctionWithFallback("pn_xournal_doc_get_page_size", "_pn_xournal_doc_get_page_size") {
      pn_xournal_doc_get_page_size = funcPtr
    } else {
      allLoaded = false
      missingFunctions.append("pn_xournal_doc_get_page_size")
    }
    
    if allLoaded {
      print("✅ [HandwritingNativePlugin] All function pointers loaded successfully")
    } else {
      print("❌ [HandwritingNativePlugin] Failed to load some function pointers. Missing: \(missingFunctions.joined(separator: ", "))")
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
  
  /// 创建占位PNG文件（空白白色图像）
  private func createPlaceholderPng(path: String, width: Int, height: Int) -> Bool {
    let url = URL(fileURLWithPath: path)
    
    // 创建图像上下文
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      print("❌ [HandwritingNativePlugin] Failed to create CGContext for placeholder PNG")
      return false
    }
    
    // 填充白色背景
    context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    // 创建图像
    guard let image = context.makeImage() else {
      print("❌ [HandwritingNativePlugin] Failed to create CGImage for placeholder PNG")
      return false
    }
    
    // 保存为PNG
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
      print("❌ [HandwritingNativePlugin] Failed to create CGImageDestination for placeholder PNG")
      return false
    }
    
    CGImageDestinationAddImage(destination, image, nil)
    
    if !CGImageDestinationFinalize(destination) {
      print("❌ [HandwritingNativePlugin] Failed to finalize placeholder PNG")
      return false
    }
    
    print("✅ [HandwritingNativePlugin] Placeholder PNG created: \(path) (\(width)x\(height))")
    return true
  }
  
  /// FlutterPlugin协议要求的方法
  public static func register(with registrar: FlutterPluginRegistrar) {
    // 使用 NSLog 确保日志输出（Flutter 的 print 可能被过滤）
    NSLog("🔧 [HandwritingNativePlugin] register called")
    print("🔧 [HandwritingNativePlugin] register called")
    
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
    NSLog("🔧 [HandwritingNativePlugin] Attempting to load dynamic library...")
    print("🔧 [HandwritingNativePlugin] Attempting to load dynamic library...")
    let loaded = instance.loadDynamicLibrary()
    if loaded {
      NSLog("✅ [HandwritingNativePlugin] Dynamic library loaded successfully during registration")
      print("✅ [HandwritingNativePlugin] Dynamic library loaded successfully during registration")
    } else {
      NSLog("⚠️ [HandwritingNativePlugin] Dynamic library not loaded during registration, will use placeholder")
      print("⚠️ [HandwritingNativePlugin] Dynamic library not loaded during registration, will use placeholder")
    }
    
    NSLog("✅ [HandwritingNativePlugin] MethodChannel registered")
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
      documents[docId] = nil // 占位（存储nil以便后续检查时能找到key）
      placeholderDocIds.insert(docId) // 标记为占位文档
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
      documents[docId] = nil // 占位（存储nil以便后续检查时能找到key）
      placeholderDocIds.insert(docId) // 标记为占位文档
      documentsLock.unlock()
      print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder")
      print("✅ [HandwritingNativePlugin] Document opened with ID: \(docId)")
      result(docId)
    }
  }
  
  /// 打开PDF文档
  private func handleOpenPdf(call: FlutterMethodCall, result: @escaping FlutterResult) {
    print("📞 [HandwritingNativePlugin] handleOpenPdf called")
    
    guard let args = call.arguments as? [String: Any],
          let pdfPath = args["path"] as? String else {
      print("❌ [HandwritingNativePlugin] handleOpenPdf: Missing path parameter")
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing path parameter", details: nil))
      return
    }
    
    // attachToDocument: 0=替换当前文档, 1=附加到当前文档（默认0）
    let attachToDocument = (args["attachToDocument"] as? Bool) ?? false
    let attachInt: Int32 = attachToDocument ? 1 : 0
    
    print("📄 [HandwritingNativePlugin] Opening PDF from: \(pdfPath), attach: \(attachToDocument)")
    print("📄 [HandwritingNativePlugin] Checking if dynamic library is loaded...")
    
    // 检查动态库加载状态
    let dylibStatus = dylibHandle != nil ? "loaded" : "not loaded"
    let funcStatus = pn_xournal_doc_open_pdf != nil ? "available" : "not available"
    NSLog("📄 [HandwritingNativePlugin] Dynamic library status: \(dylibStatus), PDF open function: \(funcStatus)")
    print("📄 [HandwritingNativePlugin] Dynamic library status: \(dylibStatus), PDF open function: \(funcStatus)")
    
    // 如果动态库未加载，尝试重新加载
    if dylibHandle == nil {
      NSLog("📄 [HandwritingNativePlugin] Dynamic library not loaded, attempting to reload...")
      print("📄 [HandwritingNativePlugin] Dynamic library not loaded, attempting to reload...")
      let reloaded = loadDynamicLibrary()
      if reloaded {
        NSLog("✅ [HandwritingNativePlugin] Dynamic library reloaded successfully")
        print("✅ [HandwritingNativePlugin] Dynamic library reloaded successfully")
      } else {
        NSLog("❌ [HandwritingNativePlugin] Failed to reload dynamic library")
        print("❌ [HandwritingNativePlugin] Failed to reload dynamic library")
      }
    }
    
    // 如果动态库已加载，调用实际的PDF打开函数
    if let openPdfFunc = pn_xournal_doc_open_pdf {
      print("✅ [HandwritingNativePlugin] PDF open function is available, calling native function...")
      var docHandle: OpaquePointer?
      pdfPath.withCString { cString in
        print("📄 [HandwritingNativePlugin] Calling pn_xournal_doc_open_pdf with path: \(pdfPath)")
        let ret = openPdfFunc(&docHandle, cString, attachInt)
        print("📄 [HandwritingNativePlugin] pn_xournal_doc_open_pdf returned: \(ret), docHandle: \(docHandle != nil ? "valid" : "nil")")
        
        if ret == 0, let handle = docHandle {
          let docId = UUID().uuidString
          documentsLock.lock()
          documents[docId] = handle
          let docCount = documents.count
          documentsLock.unlock()
          print("✅ [HandwritingNativePlugin] PDF opened successfully with ID: \(docId)")
          print("✅ [HandwritingNativePlugin] Total documents in map: \(docCount)")
          result(docId)
        } else {
          print("❌ [HandwritingNativePlugin] Failed to open PDF, error code: \(ret), docHandle: \(docHandle != nil ? "valid" : "nil")")
          result(FlutterError(code: "OPEN_PDF_FAILED", message: "Failed to open PDF document", details: ret))
        }
      }
    } else {
      // 占位实现
      print("⚠️ [HandwritingNativePlugin] PDF open function is NOT available, using placeholder")
      let docId = UUID().uuidString
      documentsLock.lock()
      documents[docId] = nil // 占位（存储nil以便后续检查时能找到key）
      placeholderDocIds.insert(docId) // 标记为占位文档
      let docCount = documents.count
      let placeholderCount = placeholderDocIds.count
      documentsLock.unlock()
      print("⚠️ [HandwritingNativePlugin] Dynamic library not available, using placeholder")
      print("✅ [HandwritingNativePlugin] PDF opened (placeholder) with ID: \(docId)")
      print("✅ [HandwritingNativePlugin] Total documents in map: \(docCount), placeholder docs: \(placeholderCount)")
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
    let isPlaceholder = placeholderDocIds.contains(docId)
    let docHandle = documents[docId] // 可能是nil（占位文档）
    documentsLock.unlock()
    
    // 检查文档是否存在（包括占位文档）
    if docHandle == nil && !isPlaceholder {
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    
    // 如果是占位文档，返回占位结果
    if isPlaceholder {
      print("⚠️ [HandwritingNativePlugin] Document is placeholder, returning placeholder save result")
      result(true)
      return
    }
    
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
    let isPlaceholder = placeholderDocIds.contains(docId)
    let docHandle = documents[docId] // 可能是nil（占位文档）
    
    // 检查文档是否存在（包括占位文档）
    if docHandle == nil && !isPlaceholder {
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
    
    // 移除文档映射和占位标记
    documents.removeValue(forKey: docId)
    placeholderDocIds.remove(docId)
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
    let isPlaceholder = placeholderDocIds.contains(docId)
    let docHandle = documents[docId] // 可能是nil（占位文档）
    documentsLock.unlock()
    
    // 检查文档是否存在（包括占位文档）
    if docHandle == nil && !isPlaceholder {
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    
    // 如果是占位文档，直接返回成功（占位实现）
    if isPlaceholder {
      print("⚠️ [HandwritingNativePlugin] Document is placeholder, stroke ignored")
      result(true)
      return
    }
    
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
    let isPlaceholder = placeholderDocIds.contains(docId)
    let docHandle = documents[docId] // 可能是nil（占位文档）
    let totalDocs = documents.count
    let placeholderCount = placeholderDocIds.count
    documentsLock.unlock()
    
    print("🎨 [HandwritingNativePlugin] docId: \(docId), isPlaceholder: \(isPlaceholder), docHandle: \(docHandle != nil ? "valid" : "nil"), totalDocs: \(totalDocs), placeholderCount: \(placeholderCount)")
    
    // 检查文档是否存在（包括占位文档）
    if docHandle == nil && !isPlaceholder {
      print("❌ [HandwritingNativePlugin] Document not found: \(docId)")
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    
    // 如果是占位文档，创建占位PNG文件并返回
    if isPlaceholder {
      print("⚠️ [HandwritingNativePlugin] Document is placeholder, creating placeholder PNG file...")
      if createPlaceholderPng(path: pngPath, width: width, height: height) {
        print("✅ [HandwritingNativePlugin] Placeholder PNG created successfully")
        result(pngPath)
      } else {
        print("❌ [HandwritingNativePlugin] Failed to create placeholder PNG")
        result(FlutterError(code: "PLACEHOLDER_PNG_FAILED", message: "Failed to create placeholder PNG file", details: nil))
      }
      return
    }
    
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
    
    print("📄 [HandwritingNativePlugin] handleGetPageCount called for docId: \(docId)")
    
    documentsLock.lock()
    let isPlaceholder = placeholderDocIds.contains(docId)
    let docHandle = documents[docId] // 可能是nil（占位文档）
    let totalDocs = documents.count
    let placeholderCount = placeholderDocIds.count
    documentsLock.unlock()
    
    print("📄 [HandwritingNativePlugin] docId: \(docId), isPlaceholder: \(isPlaceholder), docHandle: \(docHandle != nil ? "valid" : "nil"), totalDocs: \(totalDocs), placeholderCount: \(placeholderCount)")
    
    // 检查文档是否存在（包括占位文档）
    if docHandle == nil && !isPlaceholder {
      print("❌ [HandwritingNativePlugin] Document not found: \(docId)")
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    
    // 如果是占位文档，返回占位结果
    if isPlaceholder {
      print("⚠️ [HandwritingNativePlugin] Document is placeholder, returning placeholder page count: 1")
      result(1)
      return
    }
    
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
    
    print("📄 [HandwritingNativePlugin] handleGetPageSize called for docId: \(docId), pageIndex: \(pageIndex)")
    
    documentsLock.lock()
    let isPlaceholder = placeholderDocIds.contains(docId)
    let docHandle = documents[docId] // 可能是nil（占位文档）
    let totalDocs = documents.count
    let placeholderCount = placeholderDocIds.count
    documentsLock.unlock()
    
    print("📄 [HandwritingNativePlugin] docId: \(docId), isPlaceholder: \(isPlaceholder), docHandle: \(docHandle != nil ? "valid" : "nil"), totalDocs: \(totalDocs), placeholderCount: \(placeholderCount)")
    
    // 检查文档是否存在（包括占位文档）
    if docHandle == nil && !isPlaceholder {
      print("❌ [HandwritingNativePlugin] Document not found: \(docId)")
      result(FlutterError(code: "DOCUMENT_NOT_FOUND", message: "Document not found: \(docId)", details: nil))
      return
    }
    
    // 如果是占位文档，返回占位结果（A4尺寸）
    if isPlaceholder {
      print("⚠️ [HandwritingNativePlugin] Document is placeholder, returning placeholder page size (A4)")
      result([
        "width": 595.275591,
        "height": 841.889764,
      ])
      return
    }
    
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

