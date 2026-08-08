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
      widget.onCreated();
      Navigator.of(context).pop();
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

    // 键盘弹起时可用高度变小 —— 外层 showMobileBottomSheet 用
    // `enableScrollable: true` 时已经用 Flexible(SingleChildScrollView)
    // 把我们包了一层；这里直接返回 Column 让外层 scroll 接管。
    // 这样不会出现"双层 SingleChildScrollView"，键盘弹起时只有一层滚动。
    //
    // 如果外层 sheet 没开 enableScrollable，则回退到内部滚动。
    return _ScrollableColumn(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
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
        const SizedBox(height: 8),
      ],
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

/// Column that becomes scrollable as soon as its children no longer fit
/// in the available height — without forcing a `SingleChildScrollView`
/// when there's plenty of space.
///
/// This is the right primitive for a bottom-sheet body:
///   * If the parent already wrapped us in a `SingleChildScrollView`
///     (e.g. `showMobileBottomSheet(enableScrollable: true)`), then we
///     are inside an unbounded vertical constraint and we don't need to
///     scroll ourselves. Returning a plain `Column` keeps a single,
///     smooth scroll layer.
///   * If the parent did *not* wrap us, then we're inside the sheet's
///     intrinsic column whose height is capped at the sheet's max height
///     — and when the keyboard pops up, that cap shrinks and our
///     children would overflow the fixed-size parent. In that case the
///     `LayoutBuilder` detects the overflow and wraps in a
///     `SingleChildScrollView` so the user can still scroll to the
///     confirm button.
class _ScrollableColumn extends StatelessWidget {
  const _ScrollableColumn({
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Unbounded vertical → parent is already scrollable, don't nest.
        if (constraints.hasBoundedHeight == false ||
            constraints.maxHeight == double.infinity) {
          return body;
        }

        // Bounded → only scroll if we'd actually overflow.
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: IntrinsicHeight(
            child: body,
          ),
        );
      },
    );
  }
}
