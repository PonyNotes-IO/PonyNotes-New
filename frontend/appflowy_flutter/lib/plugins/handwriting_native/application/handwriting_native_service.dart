import 'package:appflowy/plugins/handwriting_native/platform/handwriting_native_platform.dart';

/// 手写笔记数据服务
class HandwritingNativeService {
  static final HandwritingNativeService _instance = HandwritingNativeService._internal();
  factory HandwritingNativeService() => _instance;
  HandwritingNativeService._internal();

  bool _initialized = false;
  final Map<String, String> _docIdMap = {}; // viewId -> docId映射

  /// 初始化服务
  Future<bool> init() async {
    if (_initialized) {
      return true;
    }

    print('🔧 [HandwritingNativeService] Initializing...');
    final success = await HandwritingNativePlatform.init('{}');
    
    if (success) {
      _initialized = true;
      print('✅ [HandwritingNativeService] Initialized successfully');
    } else {
      print('❌ [HandwritingNativeService] Initialization failed');
    }
    
    return success;
  }

  /// 为视图创建或打开文档
  Future<String?> getOrCreateDoc(String viewId, {String? xoppPath}) async {
    // 如果已有docId，直接返回
    if (_docIdMap.containsKey(viewId)) {
      return _docIdMap[viewId];
    }

    await init();

    String? docId;
    if (xoppPath != null && xoppPath.isNotEmpty) {
      // 打开现有文档
      print('📂 [HandwritingNativeService] Opening document for view: $viewId');
      docId = await HandwritingNativePlatform.openDoc(xoppPath);
    } else {
      // 创建新文档
      print('📄 [HandwritingNativeService] Creating document for view: $viewId');
      docId = await HandwritingNativePlatform.createDoc('{}');
    }

    if (docId != null) {
      _docIdMap[viewId] = docId;
      print('✅ [HandwritingNativeService] Document ready for view: $viewId, docId: $docId');
    } else {
      print('❌ [HandwritingNativeService] Failed to get/create document for view: $viewId');
    }

    return docId;
  }

  /// 保存文档
  Future<bool> saveDoc(String viewId, String xoppPath) async {
    final docId = _docIdMap[viewId];
    if (docId == null) {
      print('❌ [HandwritingNativeService] No document found for view: $viewId');
      return false;
    }

    print('💾 [HandwritingNativeService] Saving document for view: $viewId');
    return await HandwritingNativePlatform.saveDoc(docId, xoppPath);
  }

  /// 关闭文档
  Future<bool> closeDoc(String viewId) async {
    final docId = _docIdMap[viewId];
    if (docId == null) {
      print('⚠️ [HandwritingNativeService] No document found for view: $viewId');
      return true; // 没有文档也算成功
    }

    print('🗑️ [HandwritingNativeService] Closing document for view: $viewId');
    final success = await HandwritingNativePlatform.closeDoc(docId);
    
    if (success) {
      _docIdMap.remove(viewId);
    }
    
    return success;
  }

  /// 处理笔迹
  Future<bool> handleStroke(String viewId, List<Map<String, dynamic>> points) async {
    final docId = await getOrCreateDoc(viewId);
    if (docId == null) {
      return false;
    }

    return await HandwritingNativePlatform.handleStroke(docId, points);
  }

  /// 渲染页面
  Future<String?> renderPage(String viewId, int pageIndex, String pngPath, int width, int height) async {
    final docId = await getOrCreateDoc(viewId);
    if (docId == null) {
      return null;
    }

    return await HandwritingNativePlatform.renderPage(docId, pageIndex, pngPath, width, height);
  }

  /// 获取页面数量
  Future<int?> getPageCount(String viewId) async {
    final docId = await getOrCreateDoc(viewId);
    if (docId == null) {
      return null;
    }

    return await HandwritingNativePlatform.getPageCount(docId);
  }

  /// 获取页面尺寸
  Future<Map<String, double>?> getPageSize(String viewId, int pageIndex) async {
    final docId = await getOrCreateDoc(viewId);
    if (docId == null) {
      return null;
    }

    return await HandwritingNativePlatform.getPageSize(docId, pageIndex);
  }
}

