import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:appflowy_backend/log.dart';

import 'html_import_dialog.dart';

// FFI函数类型定义
typedef HtmlToMarkdownParseNative = Pointer<Utf8> Function(
  Pointer<Uint8> htmlData, 
  Int htmlSize, 
  Pointer<Utf8> filename, 
  Int mode,
);
typedef HtmlToMarkdownParseDart = Pointer<Utf8> Function(
  Pointer<Uint8> htmlData, 
  int htmlSize, 
  Pointer<Utf8> filename, 
  int mode,
);

typedef HtmlToMarkdownParseStringNative = Pointer<Utf8> Function(
  Pointer<Utf8> htmlContent, 
  Pointer<Utf8> filename, 
  Int mode,
);
typedef HtmlToMarkdownParseStringDart = Pointer<Utf8> Function(
  Pointer<Utf8> htmlContent, 
  Pointer<Utf8> filename, 
  int mode,
);

typedef HtmlToMarkdownCheckAvailabilityNative = Int Function();
typedef HtmlToMarkdownCheckAvailabilityDart = int Function();

typedef HtmlToMarkdownGetVersionNative = Pointer<Utf8> Function();
typedef HtmlToMarkdownGetVersionDart = Pointer<Utf8> Function();

typedef HtmlToMarkdownFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef HtmlToMarkdownFreeStringDart = void Function(Pointer<Utf8> ptr);

/// Rust HTML解析器FFI绑定
/// 专门处理HTML文档的智能解析，保留文档结构、标题、链接、表格等格式
class RustHtmlProcessor {
  static DynamicLibrary? _dylib;
  
  static HtmlToMarkdownParseDart? _htmlToMarkdownParse;
  static HtmlToMarkdownParseStringDart? _htmlToMarkdownParseString;
  static HtmlToMarkdownCheckAvailabilityDart? _htmlToMarkdownCheckAvailability;
  static HtmlToMarkdownGetVersionDart? _htmlToMarkdownGetVersion;
  static HtmlToMarkdownFreeStringDart? _htmlToMarkdownFreeString;

  /// 初始化Rust HTML解析器
  static Future<bool> initialize() async {
    try {
      if (_dylib != null) return true;

      // 查找动态库
      final libraryPath = _getRustProcessorPath();
      if (libraryPath == null) {
        Log.warn('Rust HTML解析器库未找到');
        return false;
      }

      Log.info('加载Rust HTML解析器库: $libraryPath');
      _dylib = DynamicLibrary.open(libraryPath);

      // 获取函数指针
      _htmlToMarkdownParse = _dylib!
          .lookup<NativeFunction<HtmlToMarkdownParseNative>>('html_to_markdown_parse')
          .asFunction();

      _htmlToMarkdownParseString = _dylib!
          .lookup<NativeFunction<HtmlToMarkdownParseStringNative>>('html_to_markdown_parse_string')
          .asFunction();

      _htmlToMarkdownCheckAvailability = _dylib!
          .lookup<NativeFunction<HtmlToMarkdownCheckAvailabilityNative>>('html_to_markdown_check_availability')
          .asFunction();

      _htmlToMarkdownGetVersion = _dylib!
          .lookup<NativeFunction<HtmlToMarkdownGetVersionNative>>('html_to_markdown_get_version')
          .asFunction();

      _htmlToMarkdownFreeString = _dylib!
          .lookup<NativeFunction<HtmlToMarkdownFreeStringNative>>('html_to_markdown_free_string')
          .asFunction();

      Log.info('✅ Rust HTML解析器初始化成功');
      return true;
    } catch (e) {
      Log.error('❌ Rust HTML解析器初始化失败: $e');
      return false;
    }
  }

  /// 检查Rust HTML解析器是否可用
  static Future<bool> isAvailable() async {
    try {
      if (!await initialize()) return false;
      final result = _htmlToMarkdownCheckAvailability!();
      return result == 1;
    } catch (e) {
      Log.error('检查Rust HTML解析器可用性失败: $e');
      return false;
    }
  }

  /// 获取Rust HTML解析器版本
  static Future<String> getVersion() async {
    try {
      if (!await initialize()) return 'Unknown';
      final versionPtr = _htmlToMarkdownGetVersion!();
      final version = versionPtr.toDartString();
      _htmlToMarkdownFreeString!(versionPtr);
      return version;
    } catch (e) {
      Log.error('获取Rust HTML解析器版本失败: $e');
      return 'Unknown';
    }
  }

  /// 处理HTML字节数据
  static Future<String> processHtmlBytes(
    Uint8List htmlBytes, 
    String filename, 
    HtmlImportMode mode,
  ) async {
    try {
      if (!await initialize()) {
        throw Exception('Rust HTML解析器未初始化');
      }

      final modeValue = _convertModeToInt(mode);
      
      // 分配内存并复制数据
      final htmlDataPtr = malloc.allocate<Uint8>(htmlBytes.length);
      for (int i = 0; i < htmlBytes.length; i++) {
        htmlDataPtr[i] = htmlBytes[i];
      }

      final filenamePtr = filename.toNativeUtf8();

      try {
        // 调用Rust函数
        final resultPtr = _htmlToMarkdownParse!(
          htmlDataPtr,
          htmlBytes.length,
          filenamePtr,
          modeValue,
        );

        // 获取结果
        final result = resultPtr.toDartString();
        
        // 释放内存
        _htmlToMarkdownFreeString!(resultPtr);
        
        Log.info('✅ Rust HTML解析完成，内容长度: ${result.length}');
        return result;
      } finally {
        malloc.free(htmlDataPtr);
        malloc.free(filenamePtr);
      }
    } catch (e) {
      Log.error('❌ Rust HTML解析失败: $e');
      rethrow;
    }
  }

  /// 处理HTML字符串
  static Future<String> processHtmlString(
    String htmlContent, 
    String filename, 
    HtmlImportMode mode,
  ) async {
    try {
      if (!await initialize()) {
        throw Exception('Rust HTML解析器未初始化');
      }

      final modeValue = _convertModeToInt(mode);
      
      final htmlContentPtr = htmlContent.toNativeUtf8();
      final filenamePtr = filename.toNativeUtf8();

      try {
        // 调用Rust函数
        final resultPtr = _htmlToMarkdownParseString!(
          htmlContentPtr,
          filenamePtr,
          modeValue,
        );

        // 获取结果
        final result = resultPtr.toDartString();
        
        // 释放内存
        _htmlToMarkdownFreeString!(resultPtr);
        
        Log.info('✅ Rust HTML字符串解析完成，内容长度: ${result.length}');
        return result;
      } finally {
        malloc.free(htmlContentPtr);
        malloc.free(filenamePtr);
      }
    } catch (e) {
      Log.error('❌ Rust HTML字符串解析失败: $e');
      rethrow;
    }
  }

  /// 转换模式枚举为整数
  static int _convertModeToInt(HtmlImportMode mode) {
    switch (mode) {
      case HtmlImportMode.smartParse:
        return 0; // 智能解析
      case HtmlImportMode.showSource:
        return 1; // 显示源代码
      case HtmlImportMode.legacyParse:
        return 2; // 传统解析
    }
  }

  /// 获取Rust处理器路径
  static String? _getRustProcessorPath() {
    // 检查环境变量
    final envPath = Platform.environment['RUST_HTML_PROCESSOR_PATH'];
    if (envPath != null) {
      final file = File(envPath);
      if (file.existsSync()) {
        return envPath;
      }
    }

    // 根据平台查找库文件
    String libraryName;
    String? libraryPath;

    if (Platform.isWindows) {
      libraryName = 'html_to_markdown.dll';
    } else if (Platform.isMacOS) {
      libraryName = 'libhtml_to_markdown.dylib';
    } else if (Platform.isLinux) {
      libraryName = 'libhtml_to_markdown.so';
    } else {
      Log.warn('不支持的操作系统: ${Platform.operatingSystem}');
      return null;
    }

    // 查找库文件
    final searchPaths = [
      // 当前目录
      libraryName,
      // 相对于项目根目录
      'frontend/rust-lib/target/release/$libraryName',
      'frontend/rust-lib/target/debug/$libraryName',
      // 相对于工作目录
      '../frontend/rust-lib/target/release/$libraryName',
      '../frontend/rust-lib/target/debug/$libraryName',
    ];

    for (final path in searchPaths) {
      final file = File(path);
      if (file.existsSync()) {
        libraryPath = path;
        break;
      }
    }

    if (libraryPath != null) {
      Log.info('找到Rust HTML解析器库: $libraryPath');
    } else {
      Log.warn('未找到Rust HTML解析器库: $libraryName');
    }

    return libraryPath;
  }
}