import 'package:appflowy/workspace/application/favorite/favorite_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:fixnum/fixnum.dart' as fixnum;

import 'favorite_listener.dart';

part 'favorite_bloc.freezed.dart';

class FavoriteBloc extends Bloc<FavoriteEvent, FavoriteState> {
  FavoriteBloc({String? workspaceId, UserProfilePB? userProfile}) 
      : super(FavoriteState.initial()) {
    _workspaceId = workspaceId;
    _userProfile = userProfile;
    _dispatch();
  }

  final _service = FavoriteService();
  final _listener = FavoriteListener();
  bool isReordering = false;
  String? _workspaceId;
  UserProfilePB? _userProfile;
  
  /// 设置当前工作区ID，用于过滤收藏
  void setWorkspaceId(String? workspaceId, {UserProfilePB? userProfile}) {
    if (_workspaceId != workspaceId) {
      _workspaceId = workspaceId;
      if (userProfile != null) {
        _userProfile = userProfile;
      }
      // 工作区切换时，重新加载收藏
      if (!isClosed) {
        add(const FavoriteEvent.fetchFavorites());
      }
    }
  }

  @override
  Future<void> close() async {
    await _listener.stop();
    return super.close();
  }

  void _dispatch() {
    on<FavoriteEvent>(
      (event, emit) async {
        await event.when(
          initial: () async {
            _listener.start(
              favoritesUpdated: _onFavoritesUpdated,
            );
            add(const FavoriteEvent.fetchFavorites());
          },
          fetchFavorites: () async {
            final result = await _service.readFavorites();
            await result.fold(
              (favoriteViews) async {
                // 如果没有设置工作区ID，返回所有收藏（向后兼容）
                if (_workspaceId == null || _workspaceId!.isEmpty) {
                  final views = favoriteViews.items.toList();
                  final pinnedViews =
                      views.where((v) => v.item.isPinned).toList();
                  final unpinnedViews =
                      views.where((v) => !v.item.isPinned).toList();
                  emit(state.copyWith(
                    isLoading: false,
                    views: views,
                    pinnedViews: pinnedViews,
                    unpinnedViews: unpinnedViews,
                  ));
                  return;
                }
                
                // 获取当前工作区的所有视图ID集合
                final workspaceViewIds = await _getWorkspaceViewIds(_workspaceId!);
                
                // 过滤收藏：只保留属于当前工作区的视图
                final filteredViews = <SectionViewPB>[];
                for (final sectionView in favoriteViews.items) {
                  final view = sectionView.item;
                  // 检查视图是否属于当前工作区
                  if (await _isViewInWorkspace(view.id, workspaceViewIds)) {
                    filteredViews.add(sectionView);
                  }
                }
                
                final pinnedViews =
                    filteredViews.where((v) => v.item.isPinned).toList();
                final unpinnedViews =
                    filteredViews.where((v) => !v.item.isPinned).toList();
                emit(state.copyWith(
                  isLoading: false,
                  views: filteredViews,
                  pinnedViews: pinnedViews,
                  unpinnedViews: unpinnedViews,
                ));
              },
              (error) async {
                emit(state.copyWith(
                  isLoading: false,
                  views: [],
                ));
              },
            );
          },
          toggle: (view) async {
            final isFavorited = state.views.any((v) => v.item.id == view.id);
            if (isFavorited) {
              await _service.unpinFavorite(view);
            } else if (state.pinnedViews.length < 3) {
              // pin the view if there are less than 3 pinned views
              await _service.pinFavorite(view);
            }

            await _service.toggleFavorite(view.id);
          },
          pin: (view) async {
            await _service.pinFavorite(view);
            add(const FavoriteEvent.fetchFavorites());
          },
          unpin: (view) async {
            await _service.unpinFavorite(view);
            add(const FavoriteEvent.fetchFavorites());
          },
          reorder: (oldIndex, newIndex) async {
            /// TODO: this is a workaround to reorder the favorite views
            isReordering = true;
            final pinnedViews = state.pinnedViews.toList();
            if (oldIndex < newIndex) newIndex -= 1;
            final target = pinnedViews.removeAt(oldIndex);
            pinnedViews.insert(newIndex, target);
            emit(state.copyWith(pinnedViews: pinnedViews));
            for (final view in pinnedViews) {
              await _service.toggleFavorite(view.item.id);
              await _service.toggleFavorite(view.item.id);
            }
            if (!isClosed) {
              add(const FavoriteEvent.fetchFavorites());
            }
            isReordering = false;
          },
        );
      },
    );
  }

  void _onFavoritesUpdated(
    FlowyResult<RepeatedViewPB, FlowyError> favoriteOrFailed,
    bool didFavorite,
  ) {
    if (!isReordering) {
      favoriteOrFailed.fold(
        (favorite) => add(const FetchFavorites()),
        (error) => Log.error(error),
      );
    }
  }
  
  /// 获取工作区的根视图ID集合（只获取根视图，不递归子视图）
  Future<Set<String>> _getWorkspaceViewIds(String workspaceId) async {
    try {
      if (_userProfile == null) {
        Log.warn('用户信息为空，无法获取工作区视图');
        return <String>{};
      }
      
      // 使用 WorkspaceService 获取工作区的公共视图和私有视图（根视图）
      final workspaceService = WorkspaceService(
        workspaceId: workspaceId,
        userId: _userProfile!.id,
      );
      
      final publicViewsResult = await workspaceService.getPublicViews();
      final privateViewsResult = await workspaceService.getPrivateViews();
      
      final publicViews = publicViewsResult.fold(
        (views) => views,
        (_) => <ViewPB>[],
      );
      
      final privateViews = privateViewsResult.fold(
        (views) => views,
        (_) => <ViewPB>[],
      );
      
      // 只获取根视图的ID集合
      final rootViewIds = <String>{};
      for (final rootView in [...publicViews, ...privateViews]) {
        rootViewIds.add(rootView.id);
      }
      
      Log.debug('工作区 $workspaceId 共有 ${rootViewIds.length} 个根视图');
      return rootViewIds;
    } catch (e) {
      Log.error('获取工作区视图ID失败: $e');
      return <String>{};
    }
  }
  
  /// 检查视图是否属于指定工作区
  /// 通过检查视图的祖先链，看是否有祖先属于当前工作区的根视图
  Future<bool> _isViewInWorkspace(String viewId, Set<String> workspaceRootViewIds) async {
    // 如果视图ID直接是工作区的根视图，直接返回true
    if (workspaceRootViewIds.contains(viewId)) {
      return true;
    }
    
    // 先获取视图信息，检查 parentViewId
    try {
      final viewResult = await ViewBackendService.getView(viewId);
      final view = viewResult.fold(
        (view) => view,
        (_) => null,
      );
      
      // 如果视图不存在，返回false
      if (view == null) {
        return false;
      }
      
      // 如果视图的 parentViewId 为空或等于自己，说明它是根视图
      // 检查是否在工作区的根视图列表中
      if (view.parentViewId.isEmpty || view.parentViewId == viewId) {
        return workspaceRootViewIds.contains(viewId);
      }
      
      // 获取视图的祖先链，检查是否有祖先属于当前工作区的根视图
      final ancestorsResult = await ViewBackendService.getViewAncestors(viewId);
      final ancestors = ancestorsResult.fold(
        (ancestors) => ancestors.items,
        (_) => <ViewPB>[],
      );
      
      // 检查祖先链中是否有属于当前工作区的根视图
      // 祖先链中的任何一个祖先如果是工作区的根视图，则该视图属于该工作区
      for (final ancestor in ancestors) {
        if (workspaceRootViewIds.contains(ancestor.id)) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      Log.error('检查视图工作区归属失败: $e');
      // 如果获取失败，保守处理：返回false（不显示）
      return false;
    }
  }
}

@freezed
class FavoriteEvent with _$FavoriteEvent {
  const factory FavoriteEvent.initial() = Initial;

  const factory FavoriteEvent.toggle(ViewPB view) = ToggleFavorite;

  const factory FavoriteEvent.fetchFavorites() = FetchFavorites;

  const factory FavoriteEvent.pin(ViewPB view) = PinFavorite;

  const factory FavoriteEvent.unpin(ViewPB view) = UnpinFavorite;

  const factory FavoriteEvent.reorder(int oldIndex, int newIndex) =
      ReorderFavorite;
}

@freezed
class FavoriteState with _$FavoriteState {
  const factory FavoriteState({
    @Default([]) List<SectionViewPB> views,
    @Default([]) List<SectionViewPB> pinnedViews,
    @Default([]) List<SectionViewPB> unpinnedViews,
    @Default(true) bool isLoading,
  }) = _FavoriteState;

  factory FavoriteState.initial() => const FavoriteState();
}
