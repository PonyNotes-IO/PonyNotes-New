import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
// removed SecondaryTextButton to avoid dependency issues
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../features/workspace/logic/workspace_bloc.dart';

import 'constants.dart';

class ShareTab extends StatelessWidget {
  const ShareTab({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        VSpace(18),
        _ShareTabHeader(),
        VSpace(2),
        _ShareTabDescription(),
        VSpace(14),
        _ShareTabContent(),
      ],
    );
  }
}

class _ShareTabHeader extends StatelessWidget {
  const _ShareTabHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const FlowySvg(FlowySvgs.share_tab_icon_s),
        const HSpace(6),
        FlowyText.medium(
          LocaleKeys.shareAction_shareTabTitle.tr(),
          figmaLineHeight: 18.0,
        ),
      ],
    );
  }
}

class _ShareTabDescription extends StatelessWidget {
  const _ShareTabDescription();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: FlowyText.regular(
        LocaleKeys.shareAction_shareTabDescription.tr(),
        fontSize: 13.0,
        figmaLineHeight: 18.0,
        color: Theme.of(context).hintColor,
      ),
    );
  }
}

class _ShareTabContent extends StatefulWidget {
  const _ShareTabContent();

  @override
  State<_ShareTabContent> createState() => _ShareTabContentState();
}

class _ShareTabContentState extends State<_ShareTabContent> {
  bool _loading = true;
  bool _isPublic = false;
  ViewPB? _viewPB;

  @override
  void initState() {
    super.initState();
    _loadVisibility();
  }

  Future<void> _loadVisibility() async {
    final state = context.read<ShareBloc>().state;
    if (state.viewId.isEmpty) {
      setState(() {
        _loading = false;
        _isPublic = false;
      });
      return;
    }

    // Get the view information
    final result = await ViewBackendService.getView(state.viewId);
    result.fold((view) {
      _viewPB = view;
      
      // Check if the view is in private list (which means it's "shared" - hidden from workspace)
      _checkIfViewIsPrivate(state.viewId);
    }, (err) {
      setState(() {
        _isPublic = false;
        _loading = false;
      });
    });
  }

  Future<void> _checkIfViewIsPrivate(String viewId) async {
    try {
      // Get current workspace ID
      final workspaceBloc = context.read<UserWorkspaceBloc>();
      final workspaceId = workspaceBloc.state.currentWorkspace?.workspaceId ?? '';
      
      if (workspaceId.isEmpty) {
        setState(() {
          _isPublic = false;
          _loading = false;
        });
        return;
      }
      
      // Get private views to check if current view is in the list
      final payload = GetWorkspaceViewPB.create()..value = workspaceId;
      final result = await FolderEventReadPrivateViews(payload).send();
      
      result.fold(
        (privateViews) {
          // If the view is in private list, it means it's "shared" (hidden from workspace)
          final isInPrivateList = privateViews.items.any((view) => view.id == viewId);
          setState(() {
            _isPublic = isInPrivateList;
            _loading = false;
          });
        },
        (error) {
          setState(() {
            _isPublic = false;
            _loading = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _isPublic = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ShareBloc, ShareState>(
      listener: (context, state) {
        // whenever share state changes (e.g., viewId), reload visibility
        _loadVisibility();
      },
      child: BlocBuilder<ShareBloc, ShareState>(
        builder: (context, state) {
        if (_loading) {
          return const SizedBox(
            height: 36,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final shareUrl = ShareConstants.buildShareUrl(
          workspaceId: state.workspaceId,
          viewId: state.viewId,
        );

        if (!_isPublic) {
          return Container(
            width: double.infinity,
            alignment: Alignment.centerLeft,
            child: PrimaryRoundedButton(
              margin: const EdgeInsets.symmetric(vertical: 9.0),
              text: '共享',
              useIntrinsicWidth: false,
              figmaLineHeight: 18.0,
              onTap: () async {
                await _setVisibility(false);
              },
            ),
          );
        }

        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: FlowyTextField(
                  text: shareUrl,
                  readOnly: true,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const HSpace(8.0),
            PrimaryRoundedButton(
              margin: const EdgeInsets.symmetric(vertical: 9.0, horizontal: 14.0),
              text: LocaleKeys.button_copyLink.tr(),
              figmaLineHeight: 18.0,
              leftIcon: FlowySvg(
                FlowySvgs.share_tab_copy_s,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              onTap: () => _copy(context, shareUrl),
            ),
            const HSpace(8.0),
            TextButton(
              onPressed: () async {
                await _setVisibility(true);
              },
              child: const Text('取消共享'),
            ),
          ],
        );
        },
      ),
    );
  }

  Future<void> _setVisibility(bool public) async {
    if (_viewPB == null) {
      await _loadVisibility();
      if (_viewPB == null) return;
    }
    
    // 保存操作前的状态，以便失败时恢复
    final previousIsPublic = _isPublic;
    
    // 先更新UI状态（乐观更新）
    setState(() {
      _loading = true;
      _isPublic = !public; // UI状态与实际可见性相反
    });
    
    // 修复逻辑：public=true时显示在工作区，public=false时隐藏在工作区
    // 但UI状态_isPublic表示是否显示分享链接，与实际的可见性相反
    final result = await ViewBackendService.updateViewsVisibility([_viewPB!], public);
    
    result.fold(
      (_) {
        // 成功：保持当前状态
        setState(() {
          _loading = false;
        });
        // 重新加载状态以确认实际状态
        _checkIfViewIsPrivate(_viewPB!.id);
        // Note: Sidebar will automatically refresh via BlocListener in SidebarShareButton
        // which listens to SidebarSectionsBloc state changes. No manual refresh needed.
      },
      (err) async {
        // 失败：恢复之前的状态
        setState(() {
          _loading = false;
          _isPublic = previousIsPublic; // 恢复操作前的状态
        });
        
        // 提供详细的错误提示，包括权限原因
        String errorMessage = await _getDetailedErrorMessage(err);
        
        showToastNotification(
          message: errorMessage,
          type: ToastificationType.error,
        );
        
        // 重新加载状态以确认实际状态
        _checkIfViewIsPrivate(_viewPB!.id);
      },
    );
  }


  /// 获取详细的错误消息，包括权限原因
  Future<String> _getDetailedErrorMessage(FlowyError err) async {
    // 如果有错误消息，优先使用
    if (err.msg.isNotEmpty) {
      return '分享失败: ${err.msg}';
    }
    
    // 根据错误代码提供更友好的提示
    switch (err.code) {
      case ErrorCode.Internal:
        return '分享失败: 服务器内部错误，请稍后重试';
        
      case ErrorCode.RecordNotFound:
        return '分享失败: 笔记不存在或已被删除';
        
      case ErrorCode.ViewIsLocked:
        return '分享失败: 笔记已锁定，无法分享。请先解锁笔记后再试';
        
      case ErrorCode.NotEnoughPermissions:
      case ErrorCode.UserUnauthorized:
        // 检查具体的权限原因
        return await _getPermissionErrorMessage();
        
      case ErrorCode.NetworkError:
      case ErrorCode.RequestTimeout:
        return '分享失败: 网络连接超时，请检查网络后重试';
        
      default:
        return '分享失败: 未知错误，请稍后重试';
    }
  }
  
  /// 获取权限错误的详细原因
  Future<String> _getPermissionErrorMessage() async {
    if (_viewPB == null) {
      return '分享失败: 没有权限执行此操作';
    }
    
    try {
      // 检查笔记是否被锁定
      if (_viewPB!.isLocked) {
        return '分享失败: 笔记已锁定，无法分享。请先解锁笔记后再试';
      }
      
      // 获取当前用户信息
      final userResult = await UserBackendService.getCurrentUserProfile();
      final user = userResult.fold(
        (user) => user,
        (_) => null,
      );
      
      if (user == null) {
        return '分享失败: 无法获取用户信息，请重新登录后重试';
      }
      
      // 检查用户是否是笔记的创建者
      final isCreator = _viewPB!.createdBy == user.id;
      
      // 检查用户类型
      final isLocalUser = user.userAuthType == AuthTypePB.Local;
      final isLocalWorkspace = user.workspaceType == WorkspaceTypePB.LocalW;
      
      // 构建详细的错误消息
      if (isLocalUser || isLocalWorkspace) {
        // 本地用户或本地工作空间应该有权限，可能是其他原因
        return '分享失败: 权限不足。请确认您有权限分享此笔记';
      }
      
      if (!isCreator) {
        // 不是创建者，可能是只读权限
        return '分享失败: 您不是此笔记的创建者，没有分享权限。只有笔记创建者或拥有完整权限的用户才能分享笔记';
      }
      
      // 是创建者但仍然没有权限，可能是其他限制
      return '分享失败: 权限不足。即使您是笔记创建者，也可能因为工作空间权限设置而无法分享。请联系工作空间管理员';
      
    } catch (e) {
      return '分享失败: 没有权限执行此操作。请确认您有权限分享此笔记';
    }
  }

  void _copy(BuildContext context, String url) {
    getIt<ClipboardService>().setData(
      ClipboardServiceData(plainText: url),
    );

    showToastNotification(
      message: LocaleKeys.message_copy_success.tr(),
    );
  }
}
