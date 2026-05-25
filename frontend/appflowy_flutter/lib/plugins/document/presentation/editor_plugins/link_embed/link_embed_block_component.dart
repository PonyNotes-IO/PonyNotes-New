import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/callout/callout_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/custom_link_parser.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/default_selectable_mixin.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

import 'link_embed_menu.dart';

class LinkEmbedKeys {
  const LinkEmbedKeys._();
  static const String previewType = 'preview_type';
  static const String embed = 'embed';
  static const String align = 'align';
  static const String originalText = 'original_text';
}

Node linkEmbedNode({required String url, String? originalText}) => Node(
      type: LinkPreviewBlockKeys.type,
      attributes: {
        LinkPreviewBlockKeys.url: url,
        LinkEmbedKeys.previewType: LinkEmbedKeys.embed,
        if (originalText != null) LinkEmbedKeys.originalText: originalText,
      },
    );

class LinkEmbedBlockComponent extends BlockComponentStatefulWidget {
  const LinkEmbedBlockComponent({
    super.key,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
    required super.node,
  });

  @override
  DefaultSelectableMixinState<LinkEmbedBlockComponent> createState() =>
      LinkEmbedBlockComponentState();
}

class LinkEmbedBlockComponentState
    extends DefaultSelectableMixinState<LinkEmbedBlockComponent>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  String get url => widget.node.attributes[LinkPreviewBlockKeys.url] ?? '';

  LinkLoadingStatus status = LinkLoadingStatus.loading;
  final parser = LinkParser();
  late LinkInfo linkInfo = LinkInfo(url: url);

  // 本地笔记的 viewId
  String? pageViewId;
  ViewPB? pageView;
  String? blockContent;

  final showActionsNotifier = ValueNotifier<bool>(false);
  bool isMenuShowing = false, isHovering = false;

  @override
  void initState() {
    super.initState();
    parser.addLinkInfoListener((v) {
      final hasNewInfo = !v.isEmpty(), hasOldInfo = !linkInfo.isEmpty();
      if (mounted) {
        setState(() {
          if (hasNewInfo) {
            linkInfo = v;
            status = LinkLoadingStatus.idle;
          } else if (!hasOldInfo) {
            status = LinkLoadingStatus.error;
          }
        });
      }
    });

    // 检查 URL 是否是本地笔记链接
    final viewId = _getViewIdFromUrl(url);
    if (viewId != null && viewId.isNotEmpty) {
      pageViewId = viewId;
      ViewBackendService.getMentionPageStatus(viewId).then((result) async {
        final (view, _, _) = result;
        if (mounted && view != null) {
          // 获取文档内容
          String? content;
          try {
            final docService = DocumentService();
            final docResult = await docService.getDocument(documentId: viewId);
            docResult.fold((doc) {
              // 提取文档中的文本内容
              content = _extractTextFromDocument(doc);
            }, (err) {
              // 忽略错误
            });
          } catch (e) {
            // 忽略获取文档内容的错误
          }

          if (mounted) {
            setState(() {
              pageView = view;
              blockContent = content;
              if (view.name.isNotEmpty) {
                linkInfo = LinkInfo(
                  url: url,
                  title: view.name,
                  siteName: view.name,
                );
              }
              status = LinkLoadingStatus.idle;
            });
          }
          return;
        }
        if (mounted) {
          parser.start(url);
        }
      });
    } else {
      parser.start(url);
    }
  }

  /// 从 DocumentDataPB 中提取纯文本内容
  String? _extractTextFromDocument(DocumentDataPB document) {
    try {
      // 将 DocumentDataPB 转换为 Document 对象
      final doc = document.toDocument();
      if (doc == null) {
        return null;
      }

      // 使用 NodeIterator 遍历所有节点并提取文本
      final buffer = StringBuffer();
      final startNode = doc.root.children.firstOrNull;
      if (startNode == null) {
        return null;
      }

      final iterator = NodeIterator(
        document: doc,
        startNode: startNode,
        endNode: doc.last,
      ).toList();

      for (final node in iterator) {
        // 提取 delta 中的文本
        final delta = node.delta;
        if (delta != null) {
          final text = delta.toPlainText();
          if (text.isNotEmpty) {
            if (buffer.isNotEmpty) {
              buffer.write('\n');
            }
            buffer.write(text);
          }
        }
      }

      final result = buffer.toString();
      return result.isEmpty ? null : result;
    } catch (e) {
      return null;
    }
  }

  /// 从分享链接或 ponynotes://open?viewId=xxx 中解析出 viewId；否则返回 null。
  String? _getViewIdFromUrl(String url) {
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
    parser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget result = MouseRegion(
      onEnter: (_) {
        isHovering = true;
        showActionsNotifier.value = true;
      },
      onExit: (_) {
        isHovering = false;
        Future.delayed(const Duration(milliseconds: 200), () {
          if (isMenuShowing || isHovering) return;
          if (mounted) showActionsNotifier.value = false;
        });
      },
      child: buildChild(context),
    );
    final parent = node.parent;
    EdgeInsets newPadding = padding;
    if (parent?.type == CalloutBlockKeys.type) {
      newPadding = padding.copyWith(right: padding.right + 10);
    }

    result = Padding(padding: newPadding, child: result);

    if (widget.showActions && widget.actionBuilder != null) {
      result = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: result,
      );
    }
    return result;
  }

  Widget buildChild(BuildContext context) {
    final theme = AppFlowyTheme.of(context),
        fillScheme = theme.fillColorScheme,
        borderScheme = theme.borderColorScheme;
    Widget child;

    // 如果是本地笔记链接，显示笔记内容
    if (pageView != null) {
      child = _buildPageEmbedContent(context, fillScheme: fillScheme);
    } else {
      final isIdle = status == LinkLoadingStatus.idle;
      if (isIdle) {
        child = buildContent(context, fillScheme: fillScheme);
      } else {
        child = buildErrorLoadingWidget(context, fillScheme: fillScheme);
      }
    }
    return Container(
      height: 450,
      key: widgetKey,
      decoration: BoxDecoration(
        color: fillScheme.content,
        borderRadius: BorderRadius.all(Radius.circular(16)),
        border: Border.all(color: borderScheme.primary),
      ),
      child: Stack(
        children: [
          child,
          buildMenu(context),
        ],
      ),
    );
  }

  /// 构建本地笔记嵌入内容
  Widget _buildPageEmbedContent(BuildContext context, {required AppFlowyFillColorScheme fillScheme}) {
    final view = pageView!;
    final content = blockContent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 笔记标题栏
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: fillScheme.secondary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              FlowySvg(
                FlowySvgs.document_s,
                size: const Size(20, 20),
                color: fillScheme.primary,
              ),
              const HSpace(8),
              Expanded(
                child: FlowyText(
                  view.name,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // 笔记内容
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: content != null && content.isNotEmpty
                ? FlowyText(
                    content,
                    fontSize: 14,
                    lineHeight: 1.6,
                    maxLines: 12,
                    overflow: TextOverflow.ellipsis,
                  )
                : Center(
                    child: FlowyText(
                      LocaleKeys.document_plugins_linkPreview_emptyPage.tr(),
                      color: fillScheme.tertiary,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget buildMenu(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: ValueListenableBuilder<bool>(
        valueListenable: showActionsNotifier,
        builder: (context, showActions, child) {
          if (!showActions || UniversalPlatform.isMobile) {
            return SizedBox.shrink();
          }
          return LinkEmbedMenu(
            editorState: context.read<EditorState>(),
            node: node,
            onReload: () {
              setState(() {
                status = LinkLoadingStatus.loading;
              });
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted) parser.start(url);
              });
            },
            onMenuShowed: () {
              isMenuShowing = true;
            },
            onMenuHided: () {
              isMenuShowing = false;
              if (!isHovering && mounted) {
                showActionsNotifier.value = false;
              }
            },
          );
        },
      ),
    );
  }

  Widget buildContent(BuildContext context, {required AppFlowyFillColorScheme fillScheme}) {
    final theme = AppFlowyTheme.of(context), textScheme = theme.textColorScheme;
    final hasSiteName = linkInfo.siteName?.isNotEmpty ?? false;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => afLaunchUrlString(url, addingHttpSchemeWhenFailed: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: linkInfo.imageUrl != null && linkInfo.imageUrl!.isNotEmpty
                    ? FlowyNetworkImage(
                        url: linkInfo.imageUrl!,
                        width: MediaQuery.of(context).size.width,
                      )
                    : Container(
                        color: fillScheme.content,
                        child: Center(
                          child: Icon(
                            Icons.image_outlined,
                            size: 48,
                            color: fillScheme.tertiary,
                          ),
                        ),
                      ),
              ),
            ),
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 40,
                    child: Center(
                      child: linkInfo.buildIconWidget(size: Size.square(32)),
                    ),
                  ),
                  HSpace(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasSiteName) ...[
                          FlowyText(
                            linkInfo.siteName ?? '',
                            color: textScheme.primary,
                            fontSize: 14,
                            figmaLineHeight: 20,
                            fontWeight: FontWeight.w600,
                            overflow: TextOverflow.ellipsis,
                          ),
                          VSpace(4),
                        ],
                        FlowyText.regular(
                          url,
                          color: textScheme.secondary,
                          fontSize: 12,
                          figmaLineHeight: 16,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildErrorLoadingWidget(BuildContext context, {required AppFlowyFillColorScheme fillScheme}) {
    final theme = AppFlowyTheme.of(context), textScheme = theme.textColorScheme;
    final isLoading = status == LinkLoadingStatus.loading;
    return isLoading
        ? Center(
            child: SizedBox.square(
              dimension: 64,
              child: CircularProgressIndicator.adaptive(),
            ),
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: !UniversalPlatform.isMobile
                ? null
                : () =>
                    afLaunchUrlString(url, addingHttpSchemeWhenFailed: true),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    FlowySvgs.embed_error_xl.path,
                  ),
                  VSpace(4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$url ',
                            style: TextStyle(
                              color: textScheme.secondary,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: LocaleKeys
                                .document_plugins_linkPreview_linkPreviewMenu_unableToDisplay
                                .tr(),
                            style: TextStyle(
                              color: textScheme.secondary,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
  }

  @override
  Node get currentNode => node;

  @override
  EdgeInsets get boxPadding => padding;
}
