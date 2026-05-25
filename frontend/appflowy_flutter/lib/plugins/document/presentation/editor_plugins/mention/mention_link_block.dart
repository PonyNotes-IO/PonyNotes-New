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
import 'mention_block.dart';

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

    final viewId = _getViewIdFromUrl(url);
    if (viewId != null && viewId.isNotEmpty) {
      final inAppLink = _toInAppLinkIfShareUrl(url);
      ViewBackendService.getMentionPageStatus(viewId).then((result) {
        final (view, _, _) = result;
        if (mounted && view != null && view.name.isNotEmpty) {
          setState(() {
            linkInfo = LinkInfo(url: url, title: view.name, siteName: inAppLink);
            status = _LoadingStatus.idle;
          });
          return;
        }
        if (mounted) parser.start(url);
      });
    } else {
      parser.start(url);
    }
  }

  /// 从分享链接或 ponynotes://open?viewId=xxx 中解析出 viewId；否则返回 null。
  static String? _getViewIdFromUrl(String url) {
    try {
      if (url.startsWith('ponynotes://open?')) {
        final match = RegExp(r'viewId=([^\s&]+)').firstMatch(url);
        return match?.group(1);
      }
      final uri = Uri.parse(url);
      final path = uri.path;
      final queryParams = uri.queryParameters;
      final linkType = queryParams['type'];
      var viewId = queryParams['viewId'];
      if (viewId != null && (viewId.contains('&') || viewId.contains('?'))) {
        final match = RegExp(r'[?&]viewId=([^&]+)').firstMatch(url);
        if (match != null) viewId = match.group(1);
      }
      final isSharePath = path == '/share' || path == 'share';
      final isShareOrPublish = linkType == 'share' || linkType == 'publish';
      if (isSharePath && isShareOrPublish && viewId != null && viewId.isNotEmpty) {
        return viewId;
      }
    } catch (_) {}
    return null;
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
    // 若 siteName 为本地应用链接（ponynotes://），则不显示，只显示标题
    final siteName = (linkInfo.siteName?.startsWith('ponynotes://') ?? false)
        ? null
        : linkInfo.siteName;
    final linkTitle = linkInfo.title ?? url;

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

  /// 若 [url] 为分享链接（/share?viewId=xxx&type=share），返回应用内链接 ponynotes://open?viewId=xxx；
  /// 否则返回原 [url]。
  String _toInAppLinkIfShareUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final queryParams = uri.queryParameters;
      final linkType = queryParams['type'];
      var viewId = queryParams['viewId'];
      if (viewId != null && (viewId.contains('&') || viewId.contains('?'))) {
        final match = RegExp(r'[?&]viewId=([^&]+)').firstMatch(url);
        if (match != null) viewId = match.group(1);
      }
      final isSharePath = path == '/share' || path == 'share';
      final isShareOrPublish = linkType == 'share' || linkType == 'publish';
      if (isSharePath && isShareOrPublish && viewId != null && viewId.isNotEmpty) {
        return 'ponynotes://open?viewId=$viewId';
      }
    } catch (_) {}
    return url;
  }

  Future<void> copyLink(BuildContext context) async {
    final linkToCopy = _toInAppLinkIfShareUrl(url);
    await context.copyLink(linkToCopy);
    previewController.close();
  }

  Future<void> openLink() async {
    await _handleLinkClick(url);
  }

  /// 处理链接点击事件
  /// 如果是分享链接（type=share），则尝试在应用内打开目标笔记
  /// 否则使用外部浏览器打开
  Future<void> _handleLinkClick(String url) async {
    // 支持 ponynotes://open?viewId=xxx 格式的链接
    if (url.startsWith('ponynotes://open?viewId=')) {
      final uri = Uri.parse(url);
      final viewId = uri.queryParameters['viewId'];
      if (viewId != null && viewId.isNotEmpty) {
        await _openViewInApp(viewId, null);
        return;
      }
    }

    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final queryParams = uri.queryParameters;
      final linkType = queryParams['type'];
      var viewId = queryParams['viewId'];

      // 兼容处理：若 viewId 包含 & 或 ?，说明 query string 解析有问题
      if (viewId != null && (viewId.contains('&') || viewId.contains('?') || viewId.contains('/'))) {
        final match = RegExp(r'[?&]viewId=([^&]+)').firstMatch(url);
        if (match != null) {
          viewId = match.group(1);
        }
      }

      // 检查是否为分享链接：path 包含 /share 且 type 为 share 或 publish
      final isSharePath = path == '/share' || path == 'share';
      final isShareOrPublishType = linkType == 'share' || linkType == 'publish';

      if (isSharePath && isShareOrPublishType && viewId != null && viewId.isNotEmpty) {
        // 这是分享链接，尝试在应用内打开
        await _openViewInApp(viewId, queryParams['workspaceId']);
      } else {
        // 不是分享链接，使用外部浏览器打开
        await afLaunchUrlString(url, addingHttpSchemeWhenFailed: true);
      }
    } catch (e) {
      // 解析失败，使用外部浏览器打开
      await afLaunchUrlString(url, addingHttpSchemeWhenFailed: true);
    }
  }

  /// 在应用内打开笔记视图
  Future<void> _openViewInApp(String viewId, String? workspaceId) async {
    try {
      // 通过 ViewBackendService 获取视图信息
      final result = await ViewBackendService.getView(viewId);
      final view = result.fold(
        (view) => view,
        (error) {
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
    // 尝试获取原始文字来恢复
    final attributes = widget.node.delta?.toList();
    String? originalText;
    if (attributes != null && widget.index < attributes.length) {
      final op = attributes[widget.index];
      if (op is TextInsert) {
        final mention = op.attributes?[MentionBlockKeys.mention];
        if (mention is Map) {
          originalText = mention[MentionBlockKeys.originalText] as String?;
        }
      }
    }

    // 如果有原始文字就恢复，否则保留 @ 字符作为纯文本
    final textToRestore = originalText ?? MentionBlockKeys.mentionChar;
    final transaction = editorState.transaction
      ..replaceText(widget.node, widget.index, 1, textToRestore, attributes: {});
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
