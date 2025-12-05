#include "handwriting_native_plugin.h"

#include <windows.h>
#include <sstream>
#include <iomanip>
#include <random>
#include <string>
#include <mutex>
#include <vector>

// TODO: 动态库构建后，取消注释以下行并包含实际的C API头文件
// #include "include/ponynotes_xournalpp.h"

// 生成UUID字符串（简化版本）
std::string GenerateUUID() {
  std::random_device rd;
  std::mt19937 gen(rd());
  std::uniform_int_distribution<> dis(0, 15);
  std::uniform_int_distribution<> dis2(8, 11);

  std::stringstream ss;
  ss << std::hex;
  for (int i = 0; i < 8; i++) {
    ss << dis(gen);
  }
  ss << "-";
  for (int i = 0; i < 4; i++) {
    ss << dis(gen);
  }
  ss << "-4";
  for (int i = 0; i < 3; i++) {
    ss << dis(gen);
  }
  ss << "-";
  ss << dis2(gen);
  for (int i = 0; i < 3; i++) {
    ss << dis(gen);
  }
  ss << "-";
  for (int i = 0; i < 12; i++) {
    ss << dis(gen);
  }
  return ss.str();
}

void HandwritingNativePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<HandwritingNativePlugin>();
  
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "handwriting_native",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  plugin->channel_ = std::move(channel);
  
  // 注意：不需要调用 AddPlugin，registrar 会自动管理插件生命周期
  // 但我们需要确保 plugin 不会被销毁，所以使用 release()
  plugin.release();
  
  OutputDebugStringA("[HandwritingNativePlugin] Registered successfully\n");
}

HandwritingNativePlugin::HandwritingNativePlugin() 
  : dll_handle_(nullptr),
    pn_xournal_init_(nullptr),
    pn_xournal_shutdown_(nullptr),
    pn_xournal_doc_create_(nullptr),
    pn_xournal_doc_open_(nullptr),
    pn_xournal_doc_open_pdf_(nullptr),
    pn_xournal_doc_save_(nullptr),
    pn_xournal_doc_close_(nullptr),
    pn_xournal_doc_handle_stroke_(nullptr),
    pn_xournal_doc_render_page_to_png_(nullptr),
    pn_xournal_doc_get_page_count_(nullptr),
    pn_xournal_doc_get_page_size_(nullptr) {
  // 尝试加载动态库
  LoadDynamicLibrary();
}

HandwritingNativePlugin::~HandwritingNativePlugin() {
  UnloadDynamicLibrary();
}

bool HandwritingNativePlugin::LoadDynamicLibrary() {
  // 动态库路径（待构建后确定实际路径）
  std::vector<std::wstring> possible_paths = {
    L"ponynotes_xournalpp.dll",  // 当前目录
    L"binaries\\windows\\ponynotes_xournalpp.dll",  // 相对路径
    L"C:\\Users\\kuncao\\github.com\\PonyNotes-IO\\PonyNotes-New\\binaries\\windows\\ponynotes_xournalpp.dll",  // 绝对路径
  };
  
  for (const auto& path : possible_paths) {
    dll_handle_ = LoadLibraryW(path.c_str());
    if (dll_handle_ != nullptr) {
      char log_msg[512];
      sprintf_s(log_msg, "[HandwritingNativePlugin] Dynamic library loaded from: %ws\n", path.c_str());
      OutputDebugStringA(log_msg);
      
      if (LoadFunctionPointers()) {
        OutputDebugStringA("[HandwritingNativePlugin] Dynamic library initialized successfully\n");
        return true;
      } else {
        FreeLibrary(dll_handle_);
        dll_handle_ = nullptr;
      }
    }
  }
  
  OutputDebugStringA("[HandwritingNativePlugin] Dynamic library not found, using placeholder implementation\n");
  return false;
}

bool HandwritingNativePlugin::LoadFunctionPointers() {
  if (dll_handle_ == nullptr) {
    return false;
  }
  
  // 加载各个函数指针
  pn_xournal_init_ = (PN_XournalInitFunc)GetProcAddress(dll_handle_, "pn_xournal_init");
  pn_xournal_shutdown_ = (PN_XournalShutdownFunc)GetProcAddress(dll_handle_, "pn_xournal_shutdown");
  pn_xournal_doc_create_ = (PN_XournalDocCreateFunc)GetProcAddress(dll_handle_, "pn_xournal_doc_create");
  pn_xournal_doc_open_ = (PN_XournalDocOpenFunc)GetProcAddress(dll_handle_, "pn_xournal_doc_open");
  pn_xournal_doc_open_pdf_ = (PN_XournalDocOpenPdfFunc)GetProcAddress(dll_handle_, "pn_xournal_doc_open_pdf");
  pn_xournal_doc_save_ = (PN_XournalDocSaveFunc)GetProcAddress(dll_handle_, "pn_xournal_doc_save");
  pn_xournal_doc_close_ = (PN_XournalDocCloseFunc)GetProcAddress(dll_handle_, "pn_xournal_doc_close");
  pn_xournal_doc_handle_stroke_ = (PN_XournalDocHandleStrokeFunc)GetProcAddress(dll_handle_, "pn_xournal_doc_handle_stroke");
  pn_xournal_doc_render_page_to_png_ = (PN_XournalDocRenderPageToPngFunc)GetProcAddress(dll_handle_, "pn_xournal_doc_render_page_to_png");
  pn_xournal_doc_get_page_count_ = (PN_XournalDocGetPageCountFunc)GetProcAddress(dll_handle_, "pn_xournal_doc_get_page_count");
  pn_xournal_doc_get_page_size_ = (PN_XournalDocGetPageSizeFunc)GetProcAddress(dll_handle_, "pn_xournal_doc_get_page_size");
  
  // 检查所有必需的函数是否都已加载
  bool all_loaded = pn_xournal_init_ != nullptr &&
                    pn_xournal_shutdown_ != nullptr &&
                    pn_xournal_doc_create_ != nullptr &&
                    pn_xournal_doc_open_ != nullptr &&
                    pn_xournal_doc_open_pdf_ != nullptr &&
                    pn_xournal_doc_save_ != nullptr &&
                    pn_xournal_doc_close_ != nullptr &&
                    pn_xournal_doc_handle_stroke_ != nullptr &&
                    pn_xournal_doc_render_page_to_png_ != nullptr &&
                    pn_xournal_doc_get_page_count_ != nullptr &&
                    pn_xournal_doc_get_page_size_ != nullptr;
  
  if (all_loaded) {
    OutputDebugStringA("[HandwritingNativePlugin] All function pointers loaded successfully\n");
  } else {
    OutputDebugStringA("[HandwritingNativePlugin] Some function pointers failed to load\n");
  }
  
  return all_loaded;
}

void HandwritingNativePlugin::UnloadDynamicLibrary() {
  if (dll_handle_ != nullptr) {
    if (pn_xournal_shutdown_ != nullptr) {
      pn_xournal_shutdown_();
    }
    FreeLibrary(dll_handle_);
    dll_handle_ = nullptr;
    OutputDebugStringA("[HandwritingNativePlugin] Dynamic library unloaded\n");
  }
}

void HandwritingNativePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::string method_name = method_call.method_name();
  
  char log_msg[256];
  sprintf_s(log_msg, "[HandwritingNativePlugin] Method called: %s\n", method_name.c_str());
  OutputDebugStringA(log_msg);

  if (method_name == "init") {
    HandleInit(method_call, std::move(result));
  } else if (method_name == "create_doc") {
    HandleCreateDoc(method_call, std::move(result));
  } else if (method_name == "open_doc") {
    HandleOpenDoc(method_call, std::move(result));
  } else if (method_name == "open_pdf") {
    HandleOpenPdf(method_call, std::move(result));
  } else if (method_name == "save_doc") {
    HandleSaveDoc(method_call, std::move(result));
  } else if (method_name == "close_doc") {
    HandleCloseDoc(method_call, std::move(result));
  } else if (method_name == "handle_stroke") {
    HandleStroke(method_call, std::move(result));
  } else if (method_name == "render_page") {
    HandleRenderPage(method_call, std::move(result));
  } else if (method_name == "get_page_count") {
    HandleGetPageCount(method_call, std::move(result));
  } else if (method_name == "get_page_size") {
    HandleGetPageSize(method_call, std::move(result));
  } else {
    result->NotImplemented();
  }
}

void HandwritingNativePlugin::HandleInit(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGUMENT", "Missing arguments");
    return;
  }

  auto config_it = args->find(flutter::EncodableValue("config"));
  if (config_it == args->end()) {
    result->Error("INVALID_ARGUMENT", "Missing config parameter");
    return;
  }

  const auto* config_json = std::get_if<std::string>(&config_it->second);
  if (!config_json) {
    result->Error("INVALID_ARGUMENT", "config must be a string");
    return;
  }

  OutputDebugStringA("[HandwritingNativePlugin] Initializing...\n");
  
  // 如果动态库已加载，调用实际的初始化函数
  if (pn_xournal_init_ != nullptr) {
    int ret = pn_xournal_init_(config_json->c_str());
    if (ret == 0) {
      OutputDebugStringA("[HandwritingNativePlugin] Dynamic library initialized successfully\n");
      result->Success(flutter::EncodableValue(true));
    } else {
      char log_msg[256];
      sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to initialize dynamic library, error code: %d\n", ret);
      OutputDebugStringA(log_msg);
      result->Error("INIT_FAILED", "Failed to initialize dynamic library", flutter::EncodableValue(ret));
    }
  } else {
    // 动态库未加载，尝试加载
    if (LoadDynamicLibrary() && pn_xournal_init_ != nullptr) {
      int ret = pn_xournal_init_(config_json->c_str());
      if (ret == 0) {
        OutputDebugStringA("[HandwritingNativePlugin] Dynamic library initialized successfully\n");
        result->Success(flutter::EncodableValue(true));
      } else {
        char log_msg[256];
        sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to initialize dynamic library, error code: %d\n", ret);
        OutputDebugStringA(log_msg);
        result->Error("INIT_FAILED", "Failed to initialize dynamic library", flutter::EncodableValue(ret));
      }
    } else {
      OutputDebugStringA("[HandwritingNativePlugin] Dynamic library not available, using placeholder implementation\n");
      result->Success(flutter::EncodableValue(true));
    }
  }
}

void HandwritingNativePlugin::HandleCreateDoc(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGUMENT", "Missing arguments");
    return;
  }

  auto options_it = args->find(flutter::EncodableValue("options"));
  if (options_it == args->end()) {
    result->Error("INVALID_ARGUMENT", "Missing options parameter");
    return;
  }

  const auto* options_json = std::get_if<std::string>(&options_it->second);
  if (!options_json) {
    result->Error("INVALID_ARGUMENT", "options must be a string");
    return;
  }

  OutputDebugStringA("[HandwritingNativePlugin] Creating document...\n");
  
  // 如果动态库已加载，调用实际的创建函数
  if (pn_xournal_doc_create_ != nullptr) {
    PN_DOC_HANDLE doc_handle = nullptr;
    int ret = pn_xournal_doc_create_(&doc_handle, options_json->c_str());
    if (ret == 0 && doc_handle != nullptr) {
      std::string docId = GenerateUUID();
      std::lock_guard<std::mutex> lock(documents_mutex_);
      documents_[docId] = doc_handle;
      
      char log_msg[256];
      sprintf_s(log_msg, "[HandwritingNativePlugin] Document created with ID: %s\n", docId.c_str());
      OutputDebugStringA(log_msg);
      result->Success(flutter::EncodableValue(docId));
    } else {
      char log_msg[256];
      sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to create document, error code: %d\n", ret);
      OutputDebugStringA(log_msg);
      result->Error("CREATE_FAILED", "Failed to create document", flutter::EncodableValue(ret));
    }
  } else {
    // 占位实现
    std::string docId = GenerateUUID();
    std::lock_guard<std::mutex> lock(documents_mutex_);
    documents_[docId] = nullptr; // 占位
    
    char log_msg[256];
    sprintf_s(log_msg, "[HandwritingNativePlugin] Dynamic library not available, using placeholder\n");
    OutputDebugStringA(log_msg);
    sprintf_s(log_msg, "[HandwritingNativePlugin] Document created with ID: %s\n", docId.c_str());
    OutputDebugStringA(log_msg);
    result->Success(flutter::EncodableValue(docId));
  }
}

void HandwritingNativePlugin::HandleOpenDoc(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGUMENT", "Missing arguments");
    return;
  }

  auto path_it = args->find(flutter::EncodableValue("path"));
  if (path_it == args->end()) {
    result->Error("INVALID_ARGUMENT", "Missing path parameter");
    return;
  }

  const auto* xopp_path = std::get_if<std::string>(&path_it->second);
  if (!xopp_path) {
    result->Error("INVALID_ARGUMENT", "path must be a string");
    return;
  }

  char log_msg[512];
  sprintf_s(log_msg, "[HandwritingNativePlugin] Opening document from: %s\n", xopp_path->c_str());
  OutputDebugStringA(log_msg);
  
  // 如果动态库已加载，调用实际的打开函数
  if (pn_xournal_doc_open_ != nullptr) {
    PN_DOC_HANDLE doc_handle = nullptr;
    int ret = pn_xournal_doc_open_(&doc_handle, xopp_path->c_str());
    if (ret == 0 && doc_handle != nullptr) {
      std::string docId = GenerateUUID();
      std::lock_guard<std::mutex> lock(documents_mutex_);
      documents_[docId] = doc_handle;
      
      sprintf_s(log_msg, "[HandwritingNativePlugin] Document opened with ID: %s\n", docId.c_str());
      OutputDebugStringA(log_msg);
      result->Success(flutter::EncodableValue(docId));
    } else {
      sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to open document, error code: %d\n", ret);
      OutputDebugStringA(log_msg);
      result->Error("OPEN_FAILED", "Failed to open document", flutter::EncodableValue(ret));
    }
  } else {
    // 占位实现
    std::string docId = GenerateUUID();
    std::lock_guard<std::mutex> lock(documents_mutex_);
    documents_[docId] = nullptr; // 占位
    
    sprintf_s(log_msg, "[HandwritingNativePlugin] Dynamic library not available, using placeholder\n");
    OutputDebugStringA(log_msg);
    sprintf_s(log_msg, "[HandwritingNativePlugin] Document opened with ID: %s\n", docId.c_str());
    OutputDebugStringA(log_msg);
    result->Success(flutter::EncodableValue(docId));
  }
}

void HandwritingNativePlugin::HandleOpenPdf(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGUMENT", "Missing arguments");
    return;
  }

  auto path_it = args->find(flutter::EncodableValue("path"));
  if (path_it == args->end()) {
    result->Error("INVALID_ARGUMENT", "Missing path parameter");
    return;
  }

  const auto* pdf_path = std::get_if<std::string>(&path_it->second);
  if (!pdf_path) {
    result->Error("INVALID_ARGUMENT", "path must be a string");
    return;
  }

  // attachToDocument: 0=替换当前文档, 1=附加到当前文档（默认0）
  bool attach_to_document = false;
  auto attach_it = args->find(flutter::EncodableValue("attachToDocument"));
  if (attach_it != args->end()) {
    const auto* attach_value = std::get_if<bool>(&attach_it->second);
    if (attach_value) {
      attach_to_document = *attach_value;
    }
  }
  int attach_int = attach_to_document ? 1 : 0;

  char log_msg[512];
  sprintf_s(log_msg, "[HandwritingNativePlugin] Opening PDF from: %s, attach: %d\n", pdf_path->c_str(), attach_int);
  OutputDebugStringA(log_msg);
  
  // 如果动态库已加载，调用实际的PDF打开函数
  if (pn_xournal_doc_open_pdf_ != nullptr) {
    PN_DOC_HANDLE doc_handle = nullptr;
    int ret = pn_xournal_doc_open_pdf_(&doc_handle, pdf_path->c_str(), attach_int);
    if (ret == 0 && doc_handle != nullptr) {
      std::string docId = GenerateUUID();
      std::lock_guard<std::mutex> lock(documents_mutex_);
      documents_[docId] = doc_handle;
      
      sprintf_s(log_msg, "[HandwritingNativePlugin] PDF opened with ID: %s\n", docId.c_str());
      OutputDebugStringA(log_msg);
      result->Success(flutter::EncodableValue(docId));
    } else {
      sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to open PDF, error code: %d\n", ret);
      OutputDebugStringA(log_msg);
      result->Error("OPEN_PDF_FAILED", "Failed to open PDF document", flutter::EncodableValue(ret));
    }
  } else {
    // 占位实现
    std::string docId = GenerateUUID();
    std::lock_guard<std::mutex> lock(documents_mutex_);
    documents_[docId] = nullptr; // 占位
    
    sprintf_s(log_msg, "[HandwritingNativePlugin] Dynamic library not available, using placeholder\n");
    OutputDebugStringA(log_msg);
    sprintf_s(log_msg, "[HandwritingNativePlugin] PDF opened (placeholder) with ID: %s\n", docId.c_str());
    OutputDebugStringA(log_msg);
    result->Success(flutter::EncodableValue(docId));
  }
}

void HandwritingNativePlugin::HandleSaveDoc(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGUMENT", "Missing arguments");
    return;
  }

  auto docId_it = args->find(flutter::EncodableValue("docId"));
  auto path_it = args->find(flutter::EncodableValue("path"));
  
  if (docId_it == args->end() || path_it == args->end()) {
    result->Error("INVALID_ARGUMENT", "Missing docId or path parameter");
    return;
  }

  const auto* docId = std::get_if<std::string>(&docId_it->second);
  const auto* xopp_path = std::get_if<std::string>(&path_it->second);
  
  if (!docId || !xopp_path) {
    result->Error("INVALID_ARGUMENT", "docId and path must be strings");
    return;
  }

  char log_msg[512];
  sprintf_s(log_msg, "[HandwritingNativePlugin] Saving document %s to: %s\n", docId->c_str(), xopp_path->c_str());
  OutputDebugStringA(log_msg);
  
  PN_DOC_HANDLE doc_handle = nullptr;
  {
    std::lock_guard<std::mutex> lock(documents_mutex_);
    auto doc_it = documents_.find(*docId);
    if (doc_it == documents_.end()) {
      result->Error("DOCUMENT_NOT_FOUND", "Document not found: " + *docId);
      return;
    }
    doc_handle = doc_it->second;
  } // 锁在这里自动释放
  
  // 如果动态库已加载且文档句柄有效，调用实际的保存函数
  if (pn_xournal_doc_save_ != nullptr && doc_handle != nullptr) {
    int ret = pn_xournal_doc_save_(doc_handle, xopp_path->c_str());
    if (ret == 0) {
      OutputDebugStringA("[HandwritingNativePlugin] Document saved\n");
      result->Success(flutter::EncodableValue(true));
    } else {
      sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to save document, error code: %d\n", ret);
      OutputDebugStringA(log_msg);
      result->Error("SAVE_FAILED", "Failed to save document", flutter::EncodableValue(ret));
    }
  } else {
    // 占位实现
    OutputDebugStringA("[HandwritingNativePlugin] Dynamic library not available, using placeholder\n");
    OutputDebugStringA("[HandwritingNativePlugin] Document saved\n");
    result->Success(flutter::EncodableValue(true));
  }
}

void HandwritingNativePlugin::HandleCloseDoc(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGUMENT", "Missing arguments");
    return;
  }

  auto docId_it = args->find(flutter::EncodableValue("docId"));
  if (docId_it == args->end()) {
    result->Error("INVALID_ARGUMENT", "Missing docId parameter");
    return;
  }

  const auto* docId = std::get_if<std::string>(&docId_it->second);
  if (!docId) {
    result->Error("INVALID_ARGUMENT", "docId must be a string");
    return;
  }

  char log_msg[256];
  sprintf_s(log_msg, "[HandwritingNativePlugin] Closing document: %s\n", docId->c_str());
  OutputDebugStringA(log_msg);
  
  std::lock_guard<std::mutex> lock(documents_mutex_);
  auto doc_it = documents_.find(*docId);
  if (doc_it == documents_.end()) {
    result->Error("DOCUMENT_NOT_FOUND", "Document not found: " + *docId);
    return;
  }
  
  PN_DOC_HANDLE doc_handle = doc_it->second;
  
  // 如果动态库已加载且文档句柄有效，调用实际的关闭函数
  if (pn_xournal_doc_close_ != nullptr && doc_handle != nullptr) {
    int ret = pn_xournal_doc_close_(doc_handle);
    if (ret != 0) {
      sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to close document, error code: %d\n", ret);
      OutputDebugStringA(log_msg);
    }
  }
  
  documents_.erase(doc_it);
  
  OutputDebugStringA("[HandwritingNativePlugin] Document closed\n");
  result->Success(flutter::EncodableValue(true));
}

void HandwritingNativePlugin::HandleStroke(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGUMENT", "Missing arguments");
    return;
  }

  auto docId_it = args->find(flutter::EncodableValue("docId"));
  auto points_it = args->find(flutter::EncodableValue("points"));
  
  if (docId_it == args->end() || points_it == args->end()) {
    result->Error("INVALID_ARGUMENT", "Missing docId or points parameter");
    return;
  }

  const auto* docId = std::get_if<std::string>(&docId_it->second);
  const auto* points_list = std::get_if<flutter::EncodableList>(&points_it->second);
  
  if (!docId || !points_list) {
    result->Error("INVALID_ARGUMENT", "docId must be a string and points must be a list");
    return;
  }

  char log_msg[256];
  sprintf_s(log_msg, "[HandwritingNativePlugin] Handling stroke for document %s, points count: %zu\n", 
            docId->c_str(), points_list->size());
  OutputDebugStringA(log_msg);
  
  PN_DOC_HANDLE doc_handle = nullptr;
  {
    std::lock_guard<std::mutex> lock(documents_mutex_);
    auto doc_it = documents_.find(*docId);
    if (doc_it == documents_.end()) {
      result->Error("DOCUMENT_NOT_FOUND", "Document not found: " + *docId);
      return;
    }
    doc_handle = doc_it->second;
  } // 锁在这里自动释放
  
  // 将Flutter传入的points转换为PN_STROKE_POINT数组
  std::vector<PN_STROKE_POINT> stroke_points;
  for (const auto& point_value : *points_list) {
    const auto* point_map = std::get_if<flutter::EncodableMap>(&point_value);
    if (!point_map) {
      OutputDebugStringA("[HandwritingNativePlugin] Invalid point data, skipping\n");
      continue;
    }
    
    auto x_it = point_map->find(flutter::EncodableValue("x"));
    auto y_it = point_map->find(flutter::EncodableValue("y"));
    auto pressure_it = point_map->find(flutter::EncodableValue("pressure"));
    auto timestamp_it = point_map->find(flutter::EncodableValue("timestamp"));
    auto tool_it = point_map->find(flutter::EncodableValue("tool"));
    auto phase_it = point_map->find(flutter::EncodableValue("phase"));
    
    if (x_it == point_map->end() || y_it == point_map->end() ||
        pressure_it == point_map->end() || timestamp_it == point_map->end() ||
        tool_it == point_map->end() || phase_it == point_map->end()) {
      OutputDebugStringA("[HandwritingNativePlugin] Missing required point fields, skipping\n");
      continue;
    }
    
    const auto* x = std::get_if<double>(&x_it->second);
    const auto* y = std::get_if<double>(&y_it->second);
    const auto* pressure = std::get_if<double>(&pressure_it->second);
    const auto* timestamp = std::get_if<int64_t>(&timestamp_it->second);
    const auto* tool = std::get_if<int32_t>(&tool_it->second);
    const auto* phase = std::get_if<int32_t>(&phase_it->second);
    
    if (!x || !y || !pressure || !timestamp || !tool || !phase) {
      OutputDebugStringA("[HandwritingNativePlugin] Invalid point data types, skipping\n");
      continue;
    }
    
    PN_STROKE_POINT point;
    point.x = static_cast<float>(*x);
    point.y = static_cast<float>(*y);
    point.pressure = static_cast<float>(*pressure);
    point.timestamp = *timestamp;
    point.tool = *tool;
    point.phase = *phase;
    stroke_points.push_back(point);
  }
  
  if (stroke_points.empty()) {
    result->Error("INVALID_ARGUMENT", "No valid points provided");
    return;
  }
  
  // 如果动态库已加载且文档句柄有效，调用实际的笔迹处理函数
  if (pn_xournal_doc_handle_stroke_ != nullptr && doc_handle != nullptr) {
    int ret = pn_xournal_doc_handle_stroke_(doc_handle, stroke_points.data(), static_cast<int>(stroke_points.size()));
    if (ret == 0) {
      OutputDebugStringA("[HandwritingNativePlugin] Stroke handled successfully\n");
      result->Success(flutter::EncodableValue(true));
    } else {
      sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to handle stroke, error code: %d\n", ret);
      OutputDebugStringA(log_msg);
      result->Error("STROKE_FAILED", "Failed to handle stroke", flutter::EncodableValue(ret));
    }
  } else {
    // 占位实现
    OutputDebugStringA("[HandwritingNativePlugin] Dynamic library not available, using placeholder\n");
    OutputDebugStringA("[HandwritingNativePlugin] Stroke handled\n");
    result->Success(flutter::EncodableValue(true));
  }
}

void HandwritingNativePlugin::HandleRenderPage(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGUMENT", "Missing arguments");
    return;
  }

  auto docId_it = args->find(flutter::EncodableValue("docId"));
  auto pageIndex_it = args->find(flutter::EncodableValue("pageIndex"));
  auto pngPath_it = args->find(flutter::EncodableValue("pngPath"));
  auto width_it = args->find(flutter::EncodableValue("width"));
  auto height_it = args->find(flutter::EncodableValue("height"));
  
  if (docId_it == args->end() || pageIndex_it == args->end() || 
      pngPath_it == args->end() || width_it == args->end() || height_it == args->end()) {
    result->Error("INVALID_ARGUMENT", "Missing required parameters");
    return;
  }

  const auto* docId = std::get_if<std::string>(&docId_it->second);
  const auto* pageIndex = std::get_if<int32_t>(&pageIndex_it->second);
  const auto* png_path = std::get_if<std::string>(&pngPath_it->second);
  const auto* width = std::get_if<int32_t>(&width_it->second);
  const auto* height = std::get_if<int32_t>(&height_it->second);
  
  if (!docId || !pageIndex || !png_path || !width || !height) {
    result->Error("INVALID_ARGUMENT", "Invalid parameter types");
    return;
  }

  char log_msg[512];
  sprintf_s(log_msg, "[HandwritingNativePlugin] Rendering page %d for document %s to: %s\n", 
            *pageIndex, docId->c_str(), png_path->c_str());
  OutputDebugStringA(log_msg);
  sprintf_s(log_msg, "   Size: %dx%d\n", *width, *height);
  OutputDebugStringA(log_msg);
  
  PN_DOC_HANDLE doc_handle = nullptr;
  {
    std::lock_guard<std::mutex> lock(documents_mutex_);
    auto doc_it = documents_.find(*docId);
    if (doc_it == documents_.end()) {
      result->Error("DOCUMENT_NOT_FOUND", "Document not found: " + *docId);
      return;
    }
    doc_handle = doc_it->second;
  } // 锁在这里自动释放
  
  // 获取options（可选）
  std::string options_json = "{}";
  auto options_it = args->find(flutter::EncodableValue("options"));
  if (options_it != args->end()) {
    const auto* options = std::get_if<std::string>(&options_it->second);
    if (options) {
      options_json = *options;
    }
  }
  
  // 如果动态库已加载且文档句柄有效，调用实际的渲染函数
  if (pn_xournal_doc_render_page_to_png_ != nullptr && doc_handle != nullptr) {
    int ret = pn_xournal_doc_render_page_to_png_(
      doc_handle,
      *pageIndex,
      png_path->c_str(),
      *width,
      *height,
      options_json.c_str()
    );
    if (ret == 0) {
      OutputDebugStringA("[HandwritingNativePlugin] Page rendered successfully\n");
      result->Success(flutter::EncodableValue(*png_path));
    } else {
      sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to render page, error code: %d\n", ret);
      OutputDebugStringA(log_msg);
      result->Error("RENDER_FAILED", "Failed to render page", flutter::EncodableValue(ret));
    }
  } else {
    // 占位实现
    OutputDebugStringA("[HandwritingNativePlugin] Dynamic library not available, using placeholder\n");
    OutputDebugStringA("[HandwritingNativePlugin] Page rendered\n");
    result->Success(flutter::EncodableValue(*png_path));
  }
}

void HandwritingNativePlugin::HandleGetPageCount(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGUMENT", "Missing arguments");
    return;
  }

  auto docId_it = args->find(flutter::EncodableValue("docId"));
  if (docId_it == args->end()) {
    result->Error("INVALID_ARGUMENT", "Missing docId parameter");
    return;
  }

  const auto* docId = std::get_if<std::string>(&docId_it->second);
  if (!docId) {
    result->Error("INVALID_ARGUMENT", "docId must be a string");
    return;
  }
  
  PN_DOC_HANDLE doc_handle = nullptr;
  {
    std::lock_guard<std::mutex> lock(documents_mutex_);
    auto doc_it = documents_.find(*docId);
    if (doc_it == documents_.end()) {
      result->Error("DOCUMENT_NOT_FOUND", "Document not found: " + *docId);
      return;
    }
    doc_handle = doc_it->second;
  } // 锁在这里自动释放
  
  // 如果动态库已加载且文档句柄有效，调用实际的获取页面数量函数
  if (pn_xournal_doc_get_page_count_ != nullptr && doc_handle != nullptr) {
    int count = 0;
    int ret = pn_xournal_doc_get_page_count_(doc_handle, &count);
    if (ret == 0) {
      char log_msg[256];
      sprintf_s(log_msg, "[HandwritingNativePlugin] Page count: %d\n", count);
      OutputDebugStringA(log_msg);
      result->Success(flutter::EncodableValue(count));
    } else {
      char log_msg[256];
      sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to get page count, error code: %d\n", ret);
      OutputDebugStringA(log_msg);
      result->Error("GET_PAGE_COUNT_FAILED", "Failed to get page count", flutter::EncodableValue(ret));
    }
  } else {
    // 占位实现
    OutputDebugStringA("[HandwritingNativePlugin] Dynamic library not available, using placeholder\n");
    result->Success(flutter::EncodableValue(1));
  }
}

void HandwritingNativePlugin::HandleGetPageSize(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGUMENT", "Missing arguments");
    return;
  }

  auto docId_it = args->find(flutter::EncodableValue("docId"));
  auto pageIndex_it = args->find(flutter::EncodableValue("pageIndex"));
  
  if (docId_it == args->end() || pageIndex_it == args->end()) {
    result->Error("INVALID_ARGUMENT", "Missing docId or pageIndex parameter");
    return;
  }

  const auto* docId = std::get_if<std::string>(&docId_it->second);
  const auto* pageIndex = std::get_if<int32_t>(&pageIndex_it->second);
  
  if (!docId || !pageIndex) {
    result->Error("INVALID_ARGUMENT", "docId must be a string and pageIndex must be an int");
    return;
  }
  
  PN_DOC_HANDLE doc_handle = nullptr;
  {
    std::lock_guard<std::mutex> lock(documents_mutex_);
    auto doc_it = documents_.find(*docId);
    if (doc_it == documents_.end()) {
      result->Error("DOCUMENT_NOT_FOUND", "Document not found: " + *docId);
      return;
    }
    doc_handle = doc_it->second;
  } // 锁在这里自动释放
  
  // 如果动态库已加载且文档句柄有效，调用实际的获取页面尺寸函数
  if (pn_xournal_doc_get_page_size_ != nullptr && doc_handle != nullptr) {
    double width = 0;
    double height = 0;
    int ret = pn_xournal_doc_get_page_size_(doc_handle, *pageIndex, &width, &height);
    if (ret == 0) {
      char log_msg[256];
      sprintf_s(log_msg, "[HandwritingNativePlugin] Page %d size: %.2fx%.2f\n", *pageIndex, width, height);
      OutputDebugStringA(log_msg);
      flutter::EncodableMap size_map;
      size_map[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
      size_map[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
      result->Success(flutter::EncodableValue(size_map));
    } else {
      char log_msg[256];
      sprintf_s(log_msg, "[HandwritingNativePlugin] Failed to get page size, error code: %d\n", ret);
      OutputDebugStringA(log_msg);
      result->Error("GET_PAGE_SIZE_FAILED", "Failed to get page size", flutter::EncodableValue(ret));
    }
  } else {
    // 占位实现：返回A4尺寸
    OutputDebugStringA("[HandwritingNativePlugin] Dynamic library not available, using placeholder\n");
    flutter::EncodableMap size_map;
    size_map[flutter::EncodableValue("width")] = flutter::EncodableValue(595.275591);
    size_map[flutter::EncodableValue("height")] = flutter::EncodableValue(841.889764);
    result->Success(flutter::EncodableValue(size_map));
  }
}

