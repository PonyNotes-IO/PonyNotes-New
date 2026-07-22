import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/view/expanded_views_cache.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/util/expand_views.dart';
import 'package:appflowy/workspace/application/favorite/favorite_listener.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_room_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_space_util.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:protobuf/protobuf.dart';

part 'view_bloc.freezed.dart';

class ViewBloc extends Bloc<ViewEvent, ViewState> {
  ViewBloc({
    required this.view,
    this.shouldLoadChildViews = true,
    this.engagedInExpanding = false,
  })  : viewBackendSvc = ViewBackendService(),
        listener = ViewListener(viewId: view.id),
        favoriteListener = FavoriteListener(),
        super(ViewState.init(view)) {
    _dispatch();
    if (engagedInExpanding) {
      expander = ViewExpander(
        () => state.isExpanded,
        () => add(const ViewEvent.setIsExpanded(true)),
      );
      getIt<ViewExpanderRegistry>().register(view.id, expander);
    }
  }

  final ViewPB view;
  final ViewBackendService viewBackendSvc;
  final ViewListener listener;
  final FavoriteListener favoriteListener;
  final bool shouldLoadChildViews;
  final bool engagedInExpanding;
  late ViewExpander expander;

  @override
  Future<void> close() async {
    await listener.stop();
    await favoriteListener.stop();
    if (engagedInExpanding) {
      getIt<ViewExpanderRegistry>().unregister(view.id, expander);
    }
    return super.close();
  }

  void _dispatch() {
    on<ViewEvent>(
      (event, emit) async {
        await event.map(
          initial: (e) async {
            listener.start(
              onViewUpdated: (result) {
                add(ViewEvent.viewDidUpdate(FlowyResult.success(result)));
              },
              onViewChildViewsUpdated: (result) async {
                Log.info('[ViewBloc] onViewChildViewsUpdated: viewId=${this.view.id}, update=$result');
                final updatedView = await _updateChildViews(result);
                if (!isClosed && updatedView != null) {
                  Log.info('[ViewBloc] Child views updated, emitting new view with ${updatedView.childViews.length} children');
                  add(ViewEvent.viewUpdateChildView(updatedView));
                } else {
                  Log.warn('[ViewBloc] Child views update returned null or bloc is closed');
                }
              },
            );
            favoriteListener.start(
              favoritesUpdated: (result, isFavorite) {
                result.fold(
                  (result) {
                    final current = result.items
                        .firstWhereOrNull((v) => v.id == state.view.id);
                    if (current != null) {
                      add(
                        ViewEvent.viewDidUpdate(
                          FlowyResult.success(current),
                        ),
                      );
                    }
                  },
                  (error) {},
                );
              },
            );
            final isExpanded = await _getViewIsExpanded(view);
            emit(state.copyWith(isExpanded: isExpanded, view: view));
            if (shouldLoadChildViews) {
              await _loadChildViews(emit);
            }
          },
          setIsEditing: (e) {
            emit(state.copyWith(isEditing: e.isEditing));
          },
          setIsExpanded: (e) async {
            if (e.isExpanded && !state.isExpanded) {
              await _loadViewsWhenExpanded(emit, true);
            } else {
              emit(state.copyWith(isExpanded: e.isExpanded));
            }
            await _setViewIsExpanded(view, e.isExpanded);
          },
          viewDidUpdate: (e) async {
            final result = await ViewBackendService.getView(view.id);
            final view_ = result.fold((l) => l, (r) => null);
            e.result.fold(
              (view) async {
                // ignore child view changes because it only contains one level
                // children data.
                if (_isSameViewIgnoreChildren(view, state.view)) {
                  // do nothing.
                }
                emit(
                  state.copyWith(
                    view: view_ ?? view,
                    successOrFailure: FlowyResult.success(null),
                  ),
                );
              },
              (error) => emit(
                state.copyWith(successOrFailure: FlowyResult.failure(error)),
              ),
            );
          },
          rename: (e) async {
            // 检查用户是否有重命名权限（Guest 角色无法重命名）
            final canRename = await _checkRenamePermission();
            if (!canRename) {
              showToastNotification(
                message: '受限成员无法重命名文档',
                type: ToastificationType.error,
              );
              return;
            }

            final result = await ViewBackendService.updateView(
              viewId: view.id,
              name: e.newName,
            );
            await result.fold(
              (l) async {
                final view = state.view;
                view.freeze();
                final newView = view.rebuild(
                  (b) => b.name = e.newName,
                );
                Log.info('rename view: ${newView.id} to ${newView.name}');
                await getIt<CachedRecentService>().reset();
                return emit(
                  state.copyWith(
                    successOrFailure: FlowyResult.success(null),
                    view: newView,
                  ),
                );
              },
              (error) async {
                Log.error('rename view failed: $error');
                return emit(
                  state.copyWith(
                    successOrFailure: FlowyResult.failure(error),
                  ),
                );
              },
            );
          },
          delete: (e) async {
            // 检查用户是否有删除权限（Guest 角色无法删除）
            final canDelete = await _checkDeletePermission();
            if (!canDelete) {
              showToastNotification(
                message: '受限成员无法删除文档',
                type: ToastificationType.error,
              );
              return;
            }

            // AI chat views are not publishable, so skip unpublish for chat only.
            if (view.layout != ViewLayoutPB.Chat) {
              try {
                await _unpublishPage(view);
              } catch (e) {
                Log.error('unpublish before delete failed: $e');
              }
            }

            final result = await ViewBackendService.deleteView(viewId: view.id);

            emit(
              result.fold(
                (l) {
                  return state.copyWith(
                    successOrFailure: FlowyResult.success(null),
                    isDeleted: true,
                  );
                },
                (error) => state.copyWith(
                  successOrFailure: FlowyResult.failure(error),
                ),
              ),
            );
            await getIt<CachedRecentService>().updateRecentViews(
              [view.id],
              false,
            );
          },
          duplicate: (e) async {
            // 检查用户是否有创建权限（复制文档需要创建权限）
            final canCreate = await _checkCreatePermission();
            if (!canCreate) {
              showToastNotification(
                message: '受限成员无法复制文档',
                type: ToastificationType.error,
              );
              return;
            }

            final result = await ViewBackendService.duplicate(
              view: view,
              openAfterDuplicate: true,
              syncAfterDuplicate: true,
              includeChildren: true,
              suffix: ' (${LocaleKeys.menuAppHeader_pageNameSuffix.tr()})',
              parentViewId: e.parentViewId,
            );
            emit(
              result.fold(
                (l) =>
                    state.copyWith(successOrFailure: FlowyResult.success(null)),
                (error) => state.copyWith(
                  successOrFailure: FlowyResult.failure(error),
                ),
              ),
            );
            result.fold(
              (_) {
                showToastNotification(
                  message: LocaleKeys.disclosureAction_duplicateSuccess.tr(),
                );
              },
              (_) {},
            );
          },
          duplicateToMySpace: (e) async {
            // 获取当前用户信息
            final userResult = await UserBackendService.getCurrentUserProfile();
            final userProfile = userResult.fold(
              (user) => user,
              (error) => null,
            );

            if (userProfile == null) {
              emit(
                state.copyWith(
                  successOrFailure: FlowyResult.failure(
                    FlowyError(msg: '无法获取当前用户信息'),
                  ),
                ),
              );
              return;
            }

            // 获取当前工作区ID
            final workspaceResult = await UserBackendService.getCurrentWorkspace();
            final workspace = workspaceResult.fold(
              (w) => w,
              (error) => null,
            );

            if (workspace == null) {
              emit(
                state.copyWith(
                  successOrFailure: FlowyResult.failure(
                    FlowyError(msg: '无法获取当前工作区'),
                  ),
                ),
              );
              return;
            }

            // 获取或创建"我的空间"
            final workspaceService = WorkspaceService(
              workspaceId: workspace.id,
              userId: userProfile.id,
            );

            // 先尝试获取私有空间
            final privateViewsResult = await workspaceService.getPrivateViews();
            final privateViews = privateViewsResult.fold(
              (views) => views,
              (error) => <ViewPB>[],
            );

            ViewPB? mySpace = privateViews.firstWhereOrNull(
              (v) => v.isSpace && v.spacePermission == SpacePermission.private,
            );

            // 如果没有找到，尝试从公共视图查找
            if (mySpace == null) {
              final publicViewsResult = await workspaceService.getPublicViews();
              final publicViews = publicViewsResult.fold(
                (views) => views,
                (error) => <ViewPB>[],
              );

              // 查找第一个空间作为目标（如果没有私有空间，使用工作区根目录）
              mySpace = publicViews.firstWhereOrNull((v) => v.isSpace);
            }

            // 使用工作区ID作为父视图ID（如果没有找到空间）
            final targetParentId = mySpace?.id ?? workspace.id;

            final result = await ViewBackendService.duplicate(
              view: view,
              openAfterDuplicate: true,
              syncAfterDuplicate: true,
              includeChildren: true,
              suffix: ' (副本)',
              parentViewId: targetParentId,
            );

            emit(
              result.fold(
                (l) {
                  Log.info('成功将笔记复制到我的空间: ${l.name}');
                  return state.copyWith(
                    successOrFailure: FlowyResult.success(null),
                  );
                },
                (error) {
                  Log.error('复制笔记到我的空间失败: ${error.msg}');
                  return state.copyWith(
                    successOrFailure: FlowyResult.failure(error),
                  );
                },
              ),
            );
          },
          move: (value) async {
            // 检查用户是否有移动权限（Guest 角色无法移动）
            final canMove = await _checkMovePermission();
            if (!canMove) {
              showToastNotification(
                message: '受限成员无法移动文档',
                type: ToastificationType.error,
              );
              return;
            }

            final result = await ViewBackendService.moveViewV2(
              viewId: value.from.id,
              newParentId: value.newParentId,
              prevViewId: value.prevId,
              fromSection: value.fromSection,
              toSection: value.toSection,
            );
            emit(
              result.fold(
                (l) {
                  return state.copyWith(
                    successOrFailure: FlowyResult.success(null),
                  );
                },
                (error) => state.copyWith(
                  successOrFailure: FlowyResult.failure(error),
                ),
              ),
            );
          },
          createView: (e) async {
            // 检查用户是否有创建权限（Guest 角色无法创建）
            final canCreate = await _checkCreatePermission();
            if (!canCreate) {
              showToastNotification(
                message: '受限成员无法创建文档',
                type: ToastificationType.error,
              );
              return;
            }

            String? roomId;
            String? roomKey;

            if (e.layoutType == ViewLayoutPB.Whiteboard) {
              // 阶段1：仅协作空间白板生成 room（走 A 套 room 协作）；
              // 私有空间白板走纯本地存储 + 静默云备份（B 套本地 collab），不生成 room。
              // section 与空间权限一一对应，优先用它快速判定；
              // section 未指定时回退到父视图所属空间（默认协作，保持既有行为）。
              bool isPrivateSpace = isPrivateSectionOrNull(e.section) ??
                  await isViewInPrivateSpace(view);

              if (isPrivateSpace) {
                Log.info(
                  '🔒 [Whiteboard] 私有空间白板，跳过 room 生成（走本地存储 + 云备份）: parent=${view.id}',
                );
              } else {
                roomId = WhiteboardRoomService.generateRoomId();
                roomKey = WhiteboardRoomService.generateRoomKey();
                Log.debug('🔑 [Whiteboard] 协作空间白板，生成 roomId=$roomId (length=${roomId.length}), roomKey=$roomKey (length=${roomKey.length})');
              }
            }

            final result = await ViewBackendService.createView(
              parentViewId: view.id,
              name: e.name,
              layoutType: e.layoutType,
              ext: {},
              openAfterCreate: e.openAfterCreated,
              section: e.section,
              index: 0,
            );
            await result.fold((createdView) async {
              if (createdView.layout == ViewLayoutPB.Whiteboard && roomId != null && roomKey != null) {
                await WhiteboardRoomService.saveRoom(createdView.id, roomId, roomKey);
                Log.debug('✅ [Whiteboard] Saved room to local storage: viewId=${createdView.id}, roomId=$roomId');
              }
            }, (_) {});

            // If the caller supplied an `extra` payload (e.g. mobile
            // marks the view as handwriting_saber via
            // `{"view_type":"handwriting_saber"}`), write it into the
            // view's `extra` field in a follow-up update. This only
            // runs when `extra != null` so existing desktop callers
            // that do not pass `extra` are unaffected.
            var emittedView = result.fold(
              (v) => v,
              (_) => null,
            );
            FlowyResult<void, FlowyError>? extraResult;
            if (emittedView != null && e.extra != null) {
              final updateResult = await ViewBackendService.updateView(
                viewId: emittedView.id,
                extra: e.extra,
              );
              extraResult = updateResult.fold(
                (_) => FlowyResult<void, FlowyError>.success(null),
                (err) => FlowyResult<void, FlowyError>.failure(err),
              );
            }
            emit(
              result.fold(
                (view) => state.copyWith(
                  lastCreatedView: view,
                  successOrFailure: extraResult ?? FlowyResult.success(null),
                ),
                (error) => state.copyWith(
                  successOrFailure: FlowyResult<void, FlowyError>.failure(
                    error,
                  ),
                ),
              ),
            );
          },
          viewUpdateChildView: (e) async {
            emit(
              state.copyWith(
                view: e.result,
              ),
            );
          },
          updateViewVisibility: (value) async {
            final view = value.view;
            await ViewBackendService.updateViewsVisibility(
              [view],
              value.isPublic,
            );
          },
          updateIcon: (value) async {
            await ViewBackendService.updateViewIcon(
              view: view,
              viewIcon: view.icon.toEmojiIconData(),
            );
          },
          collapseAllPages: (value) async {
            for (final childView in view.childViews) {
              await _setViewIsExpanded(childView, false);
            }
            add(const ViewEvent.setIsExpanded(false));
          },
          unpublish: (value) async {
            if (value.sync) {
              await _unpublishPage(view);
            } else {
              unawaited(_unpublishPage(view));
            }
          },
        );
      },
    );
  }

  Future<void> _loadViewsWhenExpanded(
    Emitter<ViewState> emit,
    bool isExpanded,
  ) async {
    if (!isExpanded) {
      emit(
        state.copyWith(
          view: view,
          isExpanded: false,
          isLoading: false,
        ),
      );
      return;
    }

    final viewsOrFailed =
        await ViewBackendService.getChildViews(viewId: state.view.id);

    viewsOrFailed.fold(
      (childViews) {
        state.view.freeze();
        final viewWithChildViews = state.view.rebuild((b) {
          b.childViews.clear();
          b.childViews.addAll(childViews);
        });
        emit(
          state.copyWith(
            view: viewWithChildViews,
            isExpanded: true,
            isLoading: false,
          ),
        );
      },
      (error) => emit(
        state.copyWith(
          successOrFailure: FlowyResult.failure(error),
          isExpanded: true,
          isLoading: false,
        ),
      ),
    );
  }

  Future<void> _loadChildViews(
    Emitter<ViewState> emit,
  ) async {
    final viewsOrFailed =
        await ViewBackendService.getChildViews(viewId: state.view.id);

    viewsOrFailed.fold(
      (childViews) {
        state.view.freeze();
        final viewWithChildViews = state.view.rebuild((b) {
          b.childViews.clear();
          b.childViews.addAll(childViews);
        });
        emit(
          state.copyWith(
            view: viewWithChildViews,
          ),
        );
      },
      (error) => emit(
        state.copyWith(
          successOrFailure: FlowyResult.failure(error),
        ),
      ),
    );
  }

  /// 设置视图展开状态（使用缓存，性能优化）
  Future<void> _setViewIsExpanded(ViewPB view, bool isExpanded) async {
    ExpandedViewsCache.instance.setExpanded(view.id, isExpanded);
  }

  /// 获取视图展开状态（使用缓存，同步快速访问）
  Future<bool> _getViewIsExpanded(ViewPB view) async {
    // 确保缓存已初始化
    await ExpandedViewsCache.instance.initialize();
    return ExpandedViewsCache.instance.isExpanded(view.id);
  }

  Future<ViewPB?> _updateChildViews(
    ChildViewUpdatePB update,
  ) async {
    Log.info('[ViewBloc] _updateChildViews: viewId=${this.view.id}, parentViewId=${update.parentViewId}, createCount=${update.createChildViews.length}, deleteCount=${update.deleteChildViews.length}, updateCount=${update.updateChildViews.length}');

    if (update.createChildViews.isNotEmpty) {
      // refresh the child views if the update isn't empty
      // because there's no info to get the inserted index.
      assert(update.parentViewId == this.view.id);
      final fetchedView = await ViewBackendService.getView(
        update.parentViewId,
      );
      return fetchedView.fold((l) => l, (r) => null);
    }

    final currentView = state.view;
    currentView.freeze();
    final childViews = [...currentView.childViews];
    Log.info('[ViewBloc] _updateChildViews: current childViews count=${childViews.length}');

    if (update.deleteChildViews.isNotEmpty) {
      Log.info('[ViewBloc] _updateChildViews: deleting child views: ${update.deleteChildViews}');
      childViews.removeWhere((v) => update.deleteChildViews.contains(v.id));
      Log.info('[ViewBloc] _updateChildViews: after deletion, childViews count=${childViews.length}');
      return currentView.rebuild((p0) {
        p0.childViews.clear();
        p0.childViews.addAll(childViews);
      });
    }

    if (update.updateChildViews.isNotEmpty && update.parentViewId.isNotEmpty) {
      final fetchedView = await ViewBackendService.getView(update.parentViewId);
      final childViews = fetchedView.fold((l) => l.childViews, (r) => []);
      bool isSameOrder = true;
      if (childViews.length == update.updateChildViews.length) {
        for (var i = 0; i < childViews.length; i++) {
          if (childViews[i].id != update.updateChildViews[i].id) {
            isSameOrder = false;
            break;
          }
        }
      } else {
        isSameOrder = false;
      }
      if (!isSameOrder) {
        return fetchedView.fold((l) => l, (r) => null);
      }
    }

    return null;
  }

  // unpublish the page and all its child pages
  Future<void> _unpublishPage(ViewPB views) async {
    final (_, publishedPages) = await ViewBackendService.containPublishedPage(
      view,
    );

    await Future.wait(
      publishedPages.map((view) async {
        Log.info('unpublishing page: ${view.id}, ${view.name}');
        await ViewBackendService.unpublish(view);
      }),
    );
  }

  bool _isSameViewIgnoreChildren(ViewPB from, ViewPB to) {
    return _hash(from) == _hash(to);
  }

  int _hash(ViewPB view) => Object.hash(
        view.id,
        view.name,
        view.createTime,
        view.icon,
        view.parentViewId,
        view.layout,
      );

  // ==================== 权限检查方法 ====================

  /// 获取当前用户信息和工作区ID
  Future<(UserProfilePB?, String?)> _getCurrentUserInfo() async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      final workspaceResult = await UserBackendService.getCurrentWorkspace();
      final userProfile = userResult.fold((l) => l, (r) => null);
      final workspace = workspaceResult.fold((l) => l, (r) => null);
      return (userProfile, workspace?.id);
    } catch (e, st) {
      Log.error('Exception when getting current user info: $e\n$st');
      return (null, null);
    }
  }

  /// 检查当前用户是否有创建权限（用于创建文档、复制文档）
  /// Guest（受限成员）无法创建文档
  Future<bool> _checkCreatePermission() async {
    try {
      final (userProfile, workspaceId) = await _getCurrentUserInfo();
      if (userProfile == null || workspaceId == null) {
        // 无法获取用户信息时，默认允许（后端会执行最终检查）
        return true;
      }

      final membersRes = await UserBackendService(userId: userProfile.id)
          .getWorkspaceMembers(workspaceId);
      return await membersRes.fold(
        (members) {
          final myMember = members.items.firstWhereOrNull(
            (m) => m.uid.toInt() == userProfile.id.toInt(),
          );
          // Guest 角色无法创建
          if (myMember?.role == AFRolePB.Guest) {
            return false;
          }
          return true;
        },
        (e) async {
          Log.error('Failed to check create permission: ${e.msg}');
          // 获取失败时允许创建（后端会执行最终检查）
          return true;
        },
      );
    } catch (e, st) {
      Log.error('Exception when checking create permission: $e\n$st');
      return true;
    }
  }

  /// 检查当前用户是否有删除权限
  /// Guest（受限成员）无法删除文档
  Future<bool> _checkDeletePermission() async {
    try {
      final (userProfile, workspaceId) = await _getCurrentUserInfo();
      if (userProfile == null || workspaceId == null) {
        return true;
      }

      final membersRes = await UserBackendService(userId: userProfile.id)
          .getWorkspaceMembers(workspaceId);
      return await membersRes.fold(
        (members) {
          final myMember = members.items.firstWhereOrNull(
            (m) => m.uid.toInt() == userProfile.id.toInt(),
          );
          // Guest 角色无法删除
          if (myMember?.role == AFRolePB.Guest) {
            return false;
          }
          return true;
        },
        (e) async {
          Log.error('Failed to check delete permission: ${e.msg}');
          return true;
        },
      );
    } catch (e, st) {
      Log.error('Exception when checking delete permission: $e\n$st');
      return true;
    }
  }

  /// 检查当前用户是否有重命名/修改权限
  /// Guest（受限成员）无法重命名文档
  Future<bool> _checkRenamePermission() async {
    try {
      final (userProfile, workspaceId) = await _getCurrentUserInfo();
      if (userProfile == null || workspaceId == null) {
        return true;
      }

      final membersRes = await UserBackendService(userId: userProfile.id)
          .getWorkspaceMembers(workspaceId);
      return await membersRes.fold(
        (members) {
          final myMember = members.items.firstWhereOrNull(
            (m) => m.uid.toInt() == userProfile.id.toInt(),
          );
          // Guest 角色无法重命名
          if (myMember?.role == AFRolePB.Guest) {
            return false;
          }
          return true;
        },
        (e) async {
          Log.error('Failed to check rename permission: ${e.msg}');
          return true;
        },
      );
    } catch (e, st) {
      Log.error('Exception when checking rename permission: $e\n$st');
      return true;
    }
  }

  /// 检查当前用户是否有移动权限
  /// Guest（受限成员）无法移动文档
  Future<bool> _checkMovePermission() async {
    try {
      final (userProfile, workspaceId) = await _getCurrentUserInfo();
      if (userProfile == null || workspaceId == null) {
        return true;
      }

      final membersRes = await UserBackendService(userId: userProfile.id)
          .getWorkspaceMembers(workspaceId);
      return await membersRes.fold(
        (members) {
          final myMember = members.items.firstWhereOrNull(
            (m) => m.uid.toInt() == userProfile.id.toInt(),
          );
          // Guest 角色无法移动
          if (myMember?.role == AFRolePB.Guest) {
            return false;
          }
          return true;
        },
        (e) async {
          Log.error('Failed to check move permission: ${e.msg}');
          return true;
        },
      );
    } catch (e, st) {
      Log.error('Exception when checking move permission: $e\n$st');
      return true;
    }
  }
}

@freezed
class ViewEvent with _$ViewEvent {
  const factory ViewEvent.initial() = Initial;

  const factory ViewEvent.setIsEditing(bool isEditing) = SetEditing;

  const factory ViewEvent.setIsExpanded(bool isExpanded) = SetIsExpanded;

  const factory ViewEvent.rename(String newName) = Rename;

  const factory ViewEvent.delete() = Delete;

  const factory ViewEvent.duplicate({String? parentViewId}) = Duplicate;

  const factory ViewEvent.duplicateToMySpace() = DuplicateToMySpace;

  const factory ViewEvent.move(
    ViewPB from,
    String newParentId,
    String? prevId,
    ViewSectionPB? fromSection,
    ViewSectionPB? toSection,
  ) = Move;

  const factory ViewEvent.createView(
    String name,
    ViewLayoutPB layoutType, {
    /// open the view after created
    @Default(true) bool openAfterCreated,
    ViewSectionPB? section,
    /// Optional JSON string to be written into the created view's
    /// `extra` field right after creation. Used by mobile to mark
    /// special view types (e.g. HandwritingSaber uses
    /// `{"view_type":"handwriting_saber"}`). Null = no follow-up
    /// `updateView` call. Has no effect on desktop code paths that
    /// do not pass this argument.
    String? extra,
  }) = CreateView;

  const factory ViewEvent.viewDidUpdate(
    FlowyResult<ViewPB, FlowyError> result,
  ) = ViewDidUpdate;

  const factory ViewEvent.viewUpdateChildView(ViewPB result) =
      ViewUpdateChildView;

  const factory ViewEvent.updateViewVisibility(
    ViewPB view,
    bool isPublic,
  ) = UpdateViewVisibility;

  const factory ViewEvent.updateIcon(String? icon) = UpdateIcon;

  const factory ViewEvent.collapseAllPages() = CollapseAllPages;

  // this event will unpublish the page and all its child pages if they are published
  const factory ViewEvent.unpublish({required bool sync}) = Unpublish;
}

@freezed
class ViewState with _$ViewState {
  const factory ViewState({
    required ViewPB view,
    required bool isEditing,
    required bool isExpanded,
    required FlowyResult<void, FlowyError> successOrFailure,
    @Default(false) bool isDeleted,
    @Default(true) bool isLoading,
    @Default(null) ViewPB? lastCreatedView,
  }) = _ViewState;

  factory ViewState.init(ViewPB view) => ViewState(
        view: view,
        isExpanded: false,
        isEditing: false,
        successOrFailure: FlowyResult.success(null),
      );
}
