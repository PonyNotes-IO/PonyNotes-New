import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// 视图发布状态服务
/// 用于检查视图是否已发布，以及管理发布状态
class ViewPublishService {
  static final ViewPublishService _instance = ViewPublishService._internal();
  factory ViewPublishService() => _instance;
  ViewPublishService._internal();

  // 缓存已发布视图的ID列表，避免重复查询
  final Set<String> _publishedViewIds = <String>{};
  bool _isInitialized = false;

  /// 初始化服务，加载已发布的视图列表
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final result = await FolderEventListPublishedViews().send();
      result.fold(
        (response) {
          _publishedViewIds.clear();
          for (final item in response.items) {
            _publishedViewIds.add(item.info.viewId);
          }
          _isInitialized = true;
          Log.info('ViewPublishService initialized with ${_publishedViewIds.length} published views');
        },
        (error) {
          Log.error('Failed to initialize ViewPublishService: $error');
          _isInitialized = true; // 即使失败也标记为已初始化，避免重复尝试
        },
      );
    } catch (e) {
      Log.error('ViewPublishService initialization error: $e');
      _isInitialized = true;
    }
  }

  /// 检查视图是否已发布
  bool isViewPublished(String viewId) {
    return _publishedViewIds.contains(viewId);
  }

  /// 检查视图是否已发布（异步方式，更准确）
  Future<bool> isViewPublishedAsync(ViewPB view) async {
    try {
      final result = await ViewBackendService.getPublishInfo(view);
      return result.isSuccess;
    } catch (e) {
      Log.error('Failed to check publish status for view ${view.id}: $e');
      return false;
    }
  }

  /// 过滤掉已发布的视图
  List<ViewPB> filterOutPublishedViews(List<ViewPB> views) {
    return views.where((view) => !isViewPublished(view.id)).toList();
  }

  /// 只保留已发布的视图
  List<ViewPB> filterOnlyPublishedViews(List<ViewPB> views) {
    return views.where((view) => isViewPublished(view.id)).toList();
  }

  /// 标记视图为已发布
  void markViewAsPublished(String viewId) {
    _publishedViewIds.add(viewId);
  }

  /// 标记视图为未发布
  void markViewAsUnpublished(String viewId) {
    _publishedViewIds.remove(viewId);
  }

  /// 刷新已发布视图列表
  Future<void> refreshPublishedViews() async {
    _isInitialized = false;
    await initialize();
  }

  /// 获取已发布视图ID列表
  Set<String> get publishedViewIds => Set.from(_publishedViewIds);

  /// 清空缓存
  void clearCache() {
    _publishedViewIds.clear();
    _isInitialized = false;
  }
}


