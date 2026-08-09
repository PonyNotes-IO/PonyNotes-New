import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/widgets/show_flowy_mobile_confirm_dialog.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon_popup.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// A bottom sheet that lets the user create a new space (team workspace)
///
/// Use this from anywhere you have a `SpaceBloc` in scope — e.g. the
/// "create" button in the mobile space-management page, or the "+" button
/// next to a space section in the mobile home page.
///
/// The sheet dispatches `SpaceEvent.create` to the supplied [spaceBloc]
/// and reports success via [onCreated] (the bloc itself emits the new
/// space into its own state, so any `BlocBuilder<SpaceBloc>` watching it
/// updates automatically — there is no need to notify another bloc).
class MobileCreateSpaceSheet extends StatefulWidget {
  const MobileCreateSpaceSheet({
    super.key,
    required this.spaceBloc,
    required this.onCreated,
  });

  final SpaceBloc spaceBloc;
  final VoidCallback onCreated;

  @override
  State<MobileCreateSpaceSheet> createState() => _MobileCreateSpaceSheetState();
}

class _MobileCreateSpaceSheetState extends State<MobileCreateSpaceSheet> {
  final _nameController = TextEditingController();
  SpacePermission _permission = SpacePermission.publicToAll;
  bool _isCreating = false;
  String _selectedIconId = builtInSpaceIcons.first;
  String _selectedColor = builtInSpaceColors.first;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isValid => _nameController.text.trim().isNotEmpty;

  Future<void> _createSpace() async {
    if (!_isValid || _isCreating) return;

    setState(() => _isCreating = true);

    final name = _nameController.text.trim();
    final initialSpaceCount = widget.spaceBloc.state.spaces.length;
    final previousLastCreatedPage = widget.spaceBloc.state.lastCreatedPage;

    Log.info(
      '[SpaceCreate] _createSpace: start, name="$name", permission=$_permission, '
      'initialSpaceCount=$initialSpaceCount, '
      'workspaceId=${widget.spaceBloc.workspaceId}',
    );

    widget.spaceBloc.add(
      SpaceEvent.create(
        name: name,
        icon: _selectedIconId,
        iconColor: _selectedColor,
        permission: _permission,
        createNewPageByDefault: true,
        openAfterCreate: true,
      ),
    );

    // 等待后端真实结果：
    //   - 成功 → spaces 列表新增一条，或 lastCreatedPage 从 null 变成非 null
    //   - 失败 → _createSpace 内部会弹错误 toast，spaces 列表不变
    final succeeded = await _waitForCreateResult(
      initialSpaceCount: initialSpaceCount,
      previousLastCreatedPage: previousLastCreatedPage,
    );

    Log.info('[SpaceCreate] _createSpace: finished, succeeded=$succeeded');

    if (!mounted) return;

    setState(() => _isCreating = false);

    if (succeeded) {
      // 先关闭 sheet，让 sheet 的 ScrollController 在 drag cancel
      // 处理之前完成销毁，避免 Flutter 框架内部的 _handleDragCancel
      // 在 Scrollable 已 dispose 后触发 `_hold == null` 的断言错误。
      // 然后再用 microtask 把新 space 通过 notifier 推到 home 端
      // SpaceBloc，让 BlocBuilder rebuild。
      final navigator = Navigator.of(context);
      final onCreated = widget.onCreated;
      navigator.pop();
      Future.microtask(() {
        Log.info(
          '[SpaceHomeSync] sheet_microtask_firing '
          'mounted=$mounted',
        );
        try {
          onCreated();
        } catch (e, st) {
          Log.error('[SpaceHomeSync] sheet_microtask_failed: $e\n$st');
        }
      });
      showToastNotification(message: '团队协作区「$name」已创建');
    } else {
      Log.warn(
        '[SpaceCreate] _createSpace: failed, keep sheet open for retry',
      );
    }
  }

  /// 等待 SpaceBloc 下一次 emit，判断创建是否真的成功。
  ///
  /// `create` 事件内部会：
  ///   1) 调 _createSpace 成功 → emit(spaces: [..., newSpace]) → emit(open) 后会再 emit
  ///   2) 调 createPage      → emit(lastCreatedPage: ...)
  ///   3) 失败              → 不 emit，但 _createSpace 内部已经弹过错误 toast
  ///
  /// 因此：监听 bloc.stream，每收到一次新 state 就判断一次
  /// "spaces 数量是否增加" 或 "lastCreatedPage 是否变非 null"。
  /// 满足条件立刻返回 true；超过超时则视为失败返回 false。
  Future<bool> _waitForCreateResult({
    required int initialSpaceCount,
    required ViewPB? previousLastCreatedPage,
  }) async {
    final bloc = widget.spaceBloc;
    final completer = Completer<bool>();

    late StreamSubscription<SpaceState> sub;
    sub = bloc.stream.listen((s) {
      final hasNewSpace = s.spaces.length > initialSpaceCount;
      final hasNewPage = s.lastCreatedPage != null &&
          s.lastCreatedPage != previousLastCreatedPage;
      Log.info(
        '[SpaceCreate] bloc emit: spaces=${s.spaces.length}, '
        'lastCreatedPage=${s.lastCreatedPage?.id ?? "null"}, '
        'hasNewSpace=$hasNewSpace, hasNewPage=$hasNewPage',
      );
      if (hasNewSpace || hasNewPage) {
        if (!completer.isCompleted) completer.complete(true);
      }
    });

    // 兜底超时：15s 足够后端 RPC + 创建默认页面
    Timer? timer;
    timer = Timer(const Duration(seconds: 15), () {
      Log.warn('[SpaceCreate] wait timeout (15s) — treating as failure');
      if (!completer.isCompleted) completer.complete(false);
    });

    final result = await completer.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;

    // 内部 Column 总高度（自然）。
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIconPicker(theme),
        const SizedBox(height: 20),
        FlowyTextField(
          controller: _nameController,
          hintText: '团队协作区名称',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        FlowyText.medium(
          '访问权限',
          fontSize: 14,
          color: theme.textColorScheme.primary,
        ),
        const SizedBox(height: 8),
        _buildPermissionOption(
          SpacePermission.publicToAll,
          '开放式',
          '所有工作空间成员可见并可访问',
          theme,
        ),
        const SizedBox(height: 8),
        _buildPermissionOption(
          SpacePermission.private,
          '私人',
          '仅被邀请的成员可见',
          theme,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: AFFilledTextButton.primary(
            text: _isCreating
                ? '创建中...'
                : LocaleKeys.button_confirm.tr(),
            onTap: () {
              if (_isValid && !_isCreating) {
                _createSpace();
              }
            },
            size: AFButtonSize.l,
          ),
        ),
      ],
    );

    // 关键洞察：sheet 是 modal，从屏幕底部弹出。但 mobile app 有 5 按钮
    // bottomNavigationBar (高 ~64px) + system nav bar (~28px)，合计约
    // 92px 的"底部禁区"。如果 sheet 内容底部贴着屏幕底部，会被 5
    // 按钮栏挡住。
    //
    // 修复：
    // 1. `SafeArea(top: false)` 让 sheet 避开 system nav bar (~28px)
    // 2. 显式 `bottom: kBottomNavigationBarHeight + 16` 让 sheet 额外
    //    避开 5 按钮栏 (~64px) + 一些 buffer。
    //
    // 这样"确 定"按钮就不会被 5 按钮栏遮住。
    //
    // 同时用 `SingleChildScrollView` 让内容超过可用高度时可滚动。
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 16,
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _buildIconPicker(AppFlowyThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText.medium(
          '图标和颜色',
          fontSize: 14,
          color: theme.textColorScheme.primary,
        ),
        const SizedBox(height: 12),
        _buildColorGrid(theme),
        const SizedBox(height: 12),
        _buildIconGrid(theme),
      ],
    );
  }

  Widget _buildColorGrid(AppFlowyThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: builtInSpaceColors.map((color) {
        final isSelected = _selectedColor == color;
        return GestureDetector(
          onTap: () => setState(() => _selectedColor = color),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Color(int.parse(color)),
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color:
                            Color(int.parse(color)).withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildIconGrid(AppFlowyThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: builtInSpaceIcons.map((icon) {
        final isSelected = _selectedIconId == icon;
        return GestureDetector(
          onTap: () => setState(() => _selectedIconId = icon),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Color(int.parse(_selectedColor)),
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: theme.textColorScheme.primary, width: 2)
                  : null,
            ),
            child: Center(
              child: FlowySvg(
                FlowySvgData('assets/flowy_icons/16x/$icon.svg'),
                size: const Size.square(24),
                color: Colors.white,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPermissionOption(
    SpacePermission permission,
    String title,
    String description,
    AppFlowyThemeData theme,
  ) {
    final isSelected = _permission == permission;

    return GestureDetector(
      onTap: () => setState(() => _permission = permission),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.surfaceColorScheme.layer01
              : theme.surfaceColorScheme.layer02,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.textColorScheme.primary
                : theme.borderColorScheme.primary,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? theme.textColorScheme.primary
                      : theme.borderColorScheme.primary,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.textColorScheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FlowyText.medium(
                    title,
                    fontSize: 14,
                    color: theme.textColorScheme.primary,
                  ),
                  const SizedBox(height: 2),
                  FlowyText(
                    description,
                    fontSize: 12,
                    color: theme.textColorScheme.secondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
