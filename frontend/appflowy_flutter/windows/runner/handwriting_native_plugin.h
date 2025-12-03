#ifndef RUNNER_HANDWRITING_NATIVE_PLUGIN_H_
#define RUNNER_HANDWRITING_NATIVE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <string>
#include <unordered_map>
#include <mutex>
#include <windows.h>

// C API函数指针类型定义（与ponynotes_xournalpp.h对应）
typedef void* PN_DOC_HANDLE;

typedef struct {
  float x;
  float y;
  float pressure;
  long long timestamp;
  int tool;
  int phase;
} PN_STROKE_POINT;

// C API函数指针类型
typedef int (*PN_XournalInitFunc)(const char* config_json);
typedef int (*PN_XournalShutdownFunc)(void);
typedef int (*PN_XournalDocCreateFunc)(PN_DOC_HANDLE* out_doc, const char* options_json);
typedef int (*PN_XournalDocOpenFunc)(PN_DOC_HANDLE* out_doc, const char* xopp_path);
typedef int (*PN_XournalDocSaveFunc)(PN_DOC_HANDLE doc, const char* xopp_path);
typedef int (*PN_XournalDocCloseFunc)(PN_DOC_HANDLE doc);
typedef int (*PN_XournalDocHandleStrokeFunc)(PN_DOC_HANDLE doc, const PN_STROKE_POINT* points, int count);
typedef int (*PN_XournalDocRenderPageToPngFunc)(PN_DOC_HANDLE doc, int page_index, const char* png_path, int width, int height, const char* options_json);
typedef int (*PN_XournalDocGetPageCountFunc)(PN_DOC_HANDLE doc, int* out_count);
typedef int (*PN_XournalDocGetPageSizeFunc)(PN_DOC_HANDLE doc, int page_index, double* out_width, double* out_height);

// 手写笔记原生插件（Windows实现）
class HandwritingNativePlugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar);

  HandwritingNativePlugin();
  virtual ~HandwritingNativePlugin();

 private:
  // 处理MethodChannel调用
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // 各个方法的实现
  void HandleInit(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  
  void HandleCreateDoc(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  
  void HandleOpenDoc(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  
  void HandleSaveDoc(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  
  void HandleCloseDoc(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  
  void HandleStroke(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  
  void HandleRenderPage(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  
  void HandleGetPageCount(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  
  void HandleGetPageSize(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // 动态库加载相关方法
  bool LoadDynamicLibrary();
  bool LoadFunctionPointers();
  void UnloadDynamicLibrary();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unordered_map<std::string, PN_DOC_HANDLE> documents_; // docId -> PN_DOC_HANDLE映射
  std::mutex documents_mutex_;
  
  // 动态库句柄
  HMODULE dll_handle_;
  
  // C API函数指针
  PN_XournalInitFunc pn_xournal_init_;
  PN_XournalShutdownFunc pn_xournal_shutdown_;
  PN_XournalDocCreateFunc pn_xournal_doc_create_;
  PN_XournalDocOpenFunc pn_xournal_doc_open_;
  PN_XournalDocSaveFunc pn_xournal_doc_save_;
  PN_XournalDocCloseFunc pn_xournal_doc_close_;
  PN_XournalDocHandleStrokeFunc pn_xournal_doc_handle_stroke_;
  PN_XournalDocRenderPageToPngFunc pn_xournal_doc_render_page_to_png_;
  PN_XournalDocGetPageCountFunc pn_xournal_doc_get_page_count_;
  PN_XournalDocGetPageSizeFunc pn_xournal_doc_get_page_size_;
};

#endif  // RUNNER_HANDWRITING_NATIVE_PLUGIN_H_

