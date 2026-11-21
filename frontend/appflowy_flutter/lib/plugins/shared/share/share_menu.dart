import 'package:appflowy/features/share_tab/presentation/share_tab.dart'
    as share_section;
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/shared/share/export_tab.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'publish_tab.dart';

enum ShareMenuTab {
  share,
  publish,
  exportAs;

  String get i18n {
    switch (this) {
      case ShareMenuTab.share:
        return 'shareTab.documentShare'.tr();
      case ShareMenuTab.publish:
        return LocaleKeys.shareAction_publishTab.tr();
      case ShareMenuTab.exportAs:
        return LocaleKeys.shareAction_exportAsTab.tr();
    }
  }
}

class ShareMenu extends StatefulWidget {
  const ShareMenu({
    super.key,
    required this.tabs,
    required this.viewName,
    required this.onClose,
  });

  final List<ShareMenuTab> tabs;
  final String viewName;
  final VoidCallback onClose;

  @override
  State<ShareMenu> createState() => _ShareMenuState();
}

class _ShareMenuState extends State<ShareMenu> {
  late ShareMenuTab selectedTab = widget.tabs.contains(ShareMenuTab.share)
      ? ShareMenuTab.share
      : widget.tabs.first;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final tab in widget.tabs)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Semantics(
                            selected: tab == selectedTab,
                            child: InkWell(
                              onTap: () => setState(() => selectedTab = tab),
                              child: Container(
                                height: 53,
                                alignment: Alignment.center,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: tab == selectedTab
                                          ? accent
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  tab.i18n,
                                  style: theme.textStyle.body.enhanced(
                                    weight: tab == selectedTab
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: tab == selectedTab
                                        ? theme.textColorScheme.primary
                                        : theme.textColorScheme.secondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                tooltip: LocaleKeys.button_close.tr(),
                iconSize: 18,
                color: theme.iconColorScheme.secondary,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Divider(
            height: 1,
            color: theme.borderColorScheme.primary.withValues(alpha: .25)),
        Flexible(child: _buildTab(context)),
      ],
    );
  }

  Widget _buildTab(BuildContext context) {
    bool isReadOnly = false;
    try {
      final pageAccessLevelBloc = context.read<PageAccessLevelBloc>();
      isReadOnly = !pageAccessLevelBloc.state.isLoadingLockStatus &&
          pageAccessLevelBloc.state.isReadOnly;
    } catch (_) {
      isReadOnly = false;
    }

    switch (selectedTab) {
      case ShareMenuTab.publish:
        if (isReadOnly) {
          return _scrollNonShareTab(_buildReadonlyHint(context));
        }
        return _scrollNonShareTab(PublishTab(viewName: widget.viewName));
      case ShareMenuTab.exportAs:
        return _scrollNonShareTab(const ExportTab());
      case ShareMenuTab.share:
        if (isReadOnly) {
          return _scrollNonShareTab(_buildReadonlyHint(context));
        }
        return const share_section.ShareTab();
    }
  }

  Widget _buildReadonlyHint(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.m,
        vertical: theme.spacing.m,
      ),
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: BorderRadius.circular(10),
      ),
      child: FlowyText.regular(
        '该文档为接收的只读发布内容，不能再次共享或发布。',
        color: theme.textColorScheme.secondary,
      ),
    );
  }

  Widget _scrollNonShareTab(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      );
}
