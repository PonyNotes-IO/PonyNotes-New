import 'dart:async';
import 'dart:math';
import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/desktop_toolbar/link/link_hover_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/link_embed_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/custom_link_parser.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/paste_as/paste_as_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/shared.dart';
import 'package:appflowy/plugins/shared/share/constants.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_platform/universal_platform.dart';

import 'mention_link_error_preview.dart';
import 'mention_link_preview.dart';

class MentionLinkBlock extends StatefulWidget {
  const MentionLinkBlock({
    super.key,
    required this.url,
    required this.editorState,
    required this.node,
    required this.index,
    this.delayToShow = const Duration(milliseconds: 50),
    this.delayToHide = const Duration(milliseconds: 300),
  });

  final String url;
  final Duration delayToShow;
  final Duration delayToHide;
  final EditorState editorState;
  final Node node;
  final int index;

  @override
  State<MentionLinkBlock> createState() => _MentionLinkBlockState();
}

class _MentionLinkBlockState extends State<MentionLinkBlock> {
  final parser = LinkParser();
  _LoadingStatus status = _LoadingStatus.loading;
  late LinkInfo linkInfo = LinkInfo(url: url);
  final previewController = PopoverController();
  bool isHovering = false;
  int previewFocusNum = 0;
  bool isPreviewHovering = false;
  bool showAtBottom = false;
  final key = GlobalKey();

  bool get isPreviewShowing => previewFocusNum > 0;
  String get url => widget.url;

  EditorState get editorState => widget.editorState;

  bool get editable => editorState.editable;

  Node get node => widget.node;

  int get index => widget.index;

  bool get readyForPreview =>
      status == _LoadingStatus.idle && !linkInfo.isEmpty();

  @override
  void initState() {
    super.initState();

    parser.addLinkInfoListener((v) {
      final hasNewInfo = !v.isEmpty(), hasOldInfo = !linkInfo.isEmpty();
      if (mounted) {
        setState(() {
          if (hasNewInfo) {
            linkInfo = v;
            status = _LoadingStatus.idle;
          } else if (!hasOldInfo) {
            status = _LoadingStatus.error;
          }
        });
      }
    });
    parser.start(url);
  }

  @override
  void dispose() {
    super.dispose();
    parser.dispose();
    previewController.close();
  }

  @override
  Widget build(BuildContext context) {
    final child = buildIconWithTitle(context);

    if (UniversalPlatform.isMobile) return child;

    return AppFlowyPopover(
      key: ValueKey(showAtBottom),
      controller: previewController,
      direction: showAtBottom
          ? PopoverDirection.bottomWithLeftAligned
          : PopoverDirection.topWithLeftAligned,
      offset: Offset(0, showAtBottom ? -20 : 20),
      onOpen: () {
        keepEditorFocusNotifier.increase();
        previewFocusNum++;
      },
      onClose: () {
        keepEditorFocusNotifier.decrease();
        previewFocusNum--;
      },
      decorationColor: Colors.transparent,
      popoverDecoration: BoxDecoration(),
      margin: EdgeInsets.zero,
      constraints: getConstraints(),
      borderRadius: BorderRadius.circular(16),
      popupBuilder: (context) => readyForPreview
          ? MentionLinkPreview(
              linkInfo: linkInfo,
              editable: editable,
              showAtBottom: showAtBottom,
              triggerSize: getSizeFromKey(),
              onEnter: (e) {
                isPreviewHovering = true;
              },
              onExit: (e) {
                isPreviewHovering = false;
                tryToDismissPreview();
              },
              onCopyLink: () => copyLink(context),
              onConvertTo: (s) => convertTo(s),
              onRemoveLink: removeLink,
              onOpenLink: openLink,
            )
          : MentionLinkErrorPreview(
              url: url,
              editable: editable,
              triggerSize: getSizeFromKey(),
              onEnter: (e) {
                isPreviewHovering = true;
              },
              onExit: (e) {
                isPreviewHovering = false;
                tryToDismissPreview();
              },
              onCopyLink: () => copyLink(context),
              onConvertTo: (s) => convertTo(s),
              onRemoveLink: removeLink,
              onOpenLink: openLink,
            ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: onEnter,
        onExit: onExit,
        child: child,
      ),
    );
  }

  Widget buildIconWithTitle(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final siteName = linkInfo.siteName, linkTitle = linkInfo.title ?? url;

    return GestureDetector(
      onTap: () async {
        await _handleLinkClick(url);
      },
      child: FlowyHoverContainer(
        style: HoverStyle(hoverColor: Theme.of(context).colorScheme.secondary),
        applyStyle: isHovering,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          key: key,
          children: [
            HSpace(2),
            buildIcon(),
            HSpace(4),
            Flexible(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    if (siteName != null) ...[
                      TextSpan(
                        text: siteName,
                        style: theme.textStyle.body
                            .standard(color: theme.textColorScheme.secondary),
                      ),
                      WidgetSpan(child: HSpace(2)),
                    ],
                    TextSpan(
                      text: linkTitle,
                      style: theme.textStyle.body
                          .standard(color: theme.textColorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            HSpace(2),
          ],
        ),
      ),
    );
  }

  Widget buildIcon() {
    const defaultWidget = FlowySvg(FlowySvgs.toolbar_link_earth_m);
    Widget icon = defaultWidget;
    if (status == _LoadingStatus.loading) {
      icon = Padding(
        padding: const EdgeInsets.all(2.0),
        child: const CircularProgressIndicator(strokeWidth: 1),
      );
    } else {
      icon = linkInfo.buildIconWidget();
    }
    return SizedBox(
      height: 20,
      width: 20,
      child: icon,
    );
  }

  RenderBox? get box => key.currentContext?.findRenderObject() as RenderBox?;

  Size getSizeFromKey() => box?.size ?? Size.zero;

  Future<void> copyLink(BuildContext context) async {
    await context.copyLink(url);
    previewController.close();
  }

  Future<void> openLink() async {
    await _handleLinkClick(url);
  }

  /// 处理链接点击事件
  /// 如果是分享链接（type=share），则尝试在应用内打开目标笔记
  /// 否则使用外部浏览器打开
  Future<void> _handleLinkClick(String url) async {
    Log.info('[MentionLinkBlock] _handleLinkClick called with url: $url');
    try {
      final uri = Uri.parse(url);
      Log.info('[MentionLinkBlock] URI parsed - host: ${uri.host}, path: ${uri.path}, query: ${uri.query}');
      final path = uri.path;
      final queryParams = uri.queryParameters;
      final linkType = queryParams['type'];
      var viewId = queryParams['viewId'];

      Log.info('[MentionLinkBlock] Before fix - path: $path, type: $linkType, viewId: $viewId');

      // 兼容处理：若 viewId 包含 & 或 ?，说明 query string 解析有问题
      // 例如：URL 可能被错误编码或者 query 参数格式异常
      if (viewId != null && (viewId.contains('&') || viewId.contains('?') || viewId.contains('/'))) {
        Log.info('[MentionLinkBlock] viewId contains invalid chars, trying to extract correct viewId');
        // 尝试从整个 URL 中提取正确的 viewId
        final match = RegExp(r'[?&]viewId=([^&]+)').firstMatch(url);
        if (match != null) {
          viewId = match.group(1);
          Log.info('[MentionLinkBlock] After fix - extracted viewId: $viewId');
        }
      }

      // 检查是否为分享链接：path 包含 /share 且 type 为 share 或 publish
      final isSharePath = path == '/share' || path == 'share';
      final isShareOrPublishType = linkType == 'share' || linkType == 'publish';

      if (isSharePath && isShareOrPublishType && viewId != null && viewId.isNotEmpty) {
        // 这是分享链接，尝试在应用内打开
        Log.info('[MentionLinkBlock] Opening view in app: $viewId');
        await _openViewInApp(viewId, queryParams['workspaceId']);
      } else {
        // 不是分享链接，使用外部浏览器打开
        Log.info('[MentionLinkBlock] Not a share link, opening in browser');
        await afLaunchUrlString(url, addingHttpSchemeWhenFailed: true);
      }
    } catch (e) {
      Log.error('[MentionLinkBlock] Error: $e');
      // 解析失败，使用外部浏览器打开
      await afLaunchUrlString(url, addingHttpSchemeWhenFailed: true);
    }
  }

  /// 在应用内打开笔记视图
  Future<void> _openViewInApp(String viewId, String? workspaceId) async {
    Log.info('[MentionLinkBlock] _openViewInApp called with viewId: $viewId, workspaceId: $workspaceId');
    try {
      // 通过 ViewBackendService 获取视图信息
      final result = await ViewBackendService.getView(viewId);
      final view = result.fold(
        (view) => view,
        (error) {
          Log.error('Failed to get view: $viewId, error: $error');
          return null;
        },
      );

      if (view != null) {
        // 找到了视图，使用 tabsBloc 打开
        final tabsBloc = getIt<TabsBloc>();
        tabsBloc.openPlugin(view);
      } else {
        // 视图不存在，使用外部浏览器打开
        await afLaunchUrlString(widget.url, addingHttpSchemeWhenFailed: true);
      }
    } catch (e) {
      Log.error('Error opening view in app: $e');
      // 打开失败，尝试使用外部浏览器打开
      await afLaunchUrlString(widget.url, addingHttpSchemeWhenFailed: true);
    }
  }

  Future<void> removeLink() async {
    final transaction = editorState.transaction
      ..replaceText(widget.node, widget.index, 1, url, attributes: {});
    await editorState.apply(transaction);
  }

  Future<void> convertTo(PasteMenuType type) async {
    if (type == PasteMenuType.url) {
      await toUrl();
    } else if (type == PasteMenuType.bookmark) {
      await toLinkPreview();
    } else if (type == PasteMenuType.embed) {
      await toLinkPreview(previewType: LinkEmbedKeys.embed);
    }
  }

  Future<void> toUrl() async {
    final transaction = editorState.transaction
      ..replaceText(
        widget.node,
        widget.index,
        1,
        url,
        attributes: {
          AppFlowyRichTextKeys.href: url,
        },
      );
    await editorState.apply(transaction);
  }

  Future<void> toLinkPreview({String? previewType}) async {
    final selection = Selection(
      start: Position(path: node.path, offset: index),
      end: Position(path: node.path, offset: index + 1),
    );
    await convertUrlToLinkPreview(
      editorState,
      selection,
      url,
      previewType: previewType,
    );
  }

  void changeHovering(bool hovering) {
    if (isHovering == hovering) return;
    if (mounted) {
      setState(() {
        isHovering = hovering;
      });
    }
  }

  void changeShowAtBottom(bool bottom) {
    if (showAtBottom == bottom) return;
    if (mounted) {
      setState(() {
        showAtBottom = bottom;
      });
    }
  }

  void tryToDismissPreview() {
    Future.delayed(widget.delayToHide, () {
      if (isHovering || isPreviewHovering) {
        return;
      }
      previewController.close();
    });
  }

  void onEnter(PointerEnterEvent e) {
    changeHovering(true);
    final location = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    if (readyForPreview) {
      if (location.dy < 300) {
        changeShowAtBottom(true);
      } else {
        changeShowAtBottom(false);
      }
    }
    Future.delayed(widget.delayToShow, () {
      if (isHovering && !isPreviewShowing && status != _LoadingStatus.loading) {
        showPreview();
      }
    });
  }

  void onExit(PointerExitEvent e) {
    changeHovering(false);
    tryToDismissPreview();
  }

  void showPreview() {
    if (!mounted) return;
    keepEditorFocusNotifier.increase();
    previewController.show();
    previewFocusNum++;
  }

  BoxConstraints getConstraints() {
    final size = getSizeFromKey();
    if (!readyForPreview) {
      return BoxConstraints(
        maxWidth: max(320, size.width),
        maxHeight: 48 + size.height,
      );
    }
    final hasImage = linkInfo.imageUrl?.isNotEmpty ?? false;
    return BoxConstraints(
      maxWidth: max(300, size.width),
      maxHeight: hasImage ? 300 : 180,
    );
  }
}

enum _LoadingStatus {
  loading,
  idle,
  error,
}
