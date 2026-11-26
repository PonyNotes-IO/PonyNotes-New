import 'dart:io';

import 'package:flowy_infra/platform_extension.dart';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/widgets/flowy_option_tile.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_drop_manager.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/startup/tasks/file_storage_task.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:string_validator/string_validator.dart';
import 'package:universal_platform/universal_platform.dart';

import 'file_block_menu.dart';
import 'file_upload_menu.dart';

class FileBlockKeys {
  const FileBlockKeys._();

  static const String type = 'file';

  /// The src of the file.
  ///
  /// The value is a String.
  /// It can be a url for a network file or a local file path.
  ///
  static const String url = 'url';

  /// The name of the file.
  ///
  /// The value is a String.
  ///
  static const String name = 'name';

  /// The type of the url.
  ///
  /// The value is a FileUrlType enum.
  ///
  static const String urlType = 'url_type';

  /// The date of the file upload.
  ///
  /// The value is a timestamp in ms.
  ///
  static const String uploadedAt = 'uploaded_at';

  /// The user who uploaded the file.
  ///
  /// The value is a String, in form of user id.
  ///
  static const String uploadedBy = 'uploaded_by';

  /// The GlobalKey of the FileBlockComponentState.
  ///
  /// **Note: This value is used in extraInfos of the Node, not in the attributes.**
  static const String globalKey = 'global_key';
}

enum FileUrlType {
  local,
  network,
  cloud;

  static FileUrlType fromIntValue(int value) {
    switch (value) {
      case 0:
        return FileUrlType.local;
      case 1:
        return FileUrlType.network;
      case 2:
        return FileUrlType.cloud;
      default:
        throw UnimplementedError();
    }
  }

  int toIntValue() {
    switch (this) {
      case FileUrlType.local:
        return 0;
      case FileUrlType.network:
        return 1;
      case FileUrlType.cloud:
        return 2;
    }
  }

  FileUploadTypePB toFileUploadTypePB() {
    switch (this) {
      case FileUrlType.local:
        return FileUploadTypePB.LocalFile;
      case FileUrlType.network:
        return FileUploadTypePB.NetworkFile;
      case FileUrlType.cloud:
        return FileUploadTypePB.CloudFile;
    }
  }
}

Node fileNode({
  required String url,
  FileUrlType type = FileUrlType.local,
  String? name,
}) {
  return Node(
    type: FileBlockKeys.type,
    attributes: {
      FileBlockKeys.url: url,
      FileBlockKeys.urlType: type.toIntValue(),
      FileBlockKeys.name: name,
      FileBlockKeys.uploadedAt: DateTime.now().millisecondsSinceEpoch,
    },
  );
}

class FileBlockComponentBuilder extends BlockComponentBuilder {
  FileBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    final extraInfos = node.extraInfos;
    final key = extraInfos?[FileBlockKeys.globalKey] as GlobalKey?;

    return FileBlockComponent(
      key: key ?? node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class FileBlockComponent extends BlockComponentStatefulWidget {
  const FileBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  static const uploadDragKey = 'FileUploadMenu';

  @override
  State<FileBlockComponent> createState() => FileBlockComponentState();
}

class FileBlockComponentState extends State<FileBlockComponent>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  late EditorDropManagerState? dropManagerState =
      PlatformInfo.isMobile ? null : context.read<EditorDropManagerState?>();

  final fileKey = GlobalKey();
  final showActionsNotifier = ValueNotifier<bool>(false);
  final controller = PopoverController();
  final menuController = PopoverController();

  late final editorState = Provider.of<EditorState>(context, listen: false);

  bool alwaysShowMenu = false;
  bool isDragging = false;
  bool isHovering = false;
  bool _isUploadingFromLocal = false;
  String? _preparingFileName;
  String? _preparationError;
  AutoRemoveNotifier<FileProgress>? _uploadProgressNotifier;
  String? _progressFileUrl;

  FileProgress? get _uploadProgress => _uploadProgressNotifier?.value;

  bool get _canOpenFile => _uploadProgress?.isReady ?? true;

  bool get _canChooseFile {
    final url = node.attributes[FileBlockKeys.url] as String?;
    final progress = _uploadProgress;
    return editorState.editable &&
        (url == null ||
            url.isEmpty ||
            progress?.isMissing == true ||
            progress?.error != null);
  }

  String? get _uploadStatus {
    final progress = _uploadProgress;
    if (progress == null || progress.isReady) return null;
    if (progress.isMissing) {
      return 'document.plugins.file.uploadUnavailable'.tr();
    }
    if (progress.error case final error?) {
      final reason = uploadFailureMessage(progress.errorCode, error);
      final failed = LocaleKeys.button_uploadFailed.tr();
      return reason == failed
          ? failed
          : 'document.plugins.file.uploadFailureDetails'.tr(args: [reason]);
    }
    if (progress.progress < 0) {
      return progress.errorCode == null
          ? 'document.plugins.file.uploadChecking'.tr()
          : 'document.plugins.file.uploadStatusUnavailable'.tr();
    }
    return progress.progress == 0
        ? LocaleKeys.document_plugins_pendingSync.tr()
        : 'document.plugins.file.uploadInProgress'.tr();
  }

  void _onUploadProgressChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _disposeUploadProgressNotifier() {
    final notifier = _uploadProgressNotifier;
    if (notifier != null) {
      notifier.removeListener(_onUploadProgressChanged);
      notifier.dispose();
    }
    _uploadProgressNotifier = null;
    _progressFileUrl = null;
  }

  void _syncUploadProgressNotifier() {
    final url = node.attributes[FileBlockKeys.url] as String?;
    final urlType =
        FileUrlType.fromIntValue(node.attributes[FileBlockKeys.urlType] ?? 0);
    final shouldTrack = urlType == FileUrlType.cloud && url?.isNotEmpty == true;
    if (!shouldTrack) {
      _disposeUploadProgressNotifier();
      return;
    }

    final fileUrl = url!;
    if (_progressFileUrl == fileUrl && _uploadProgressNotifier != null) {
      return;
    }

    _disposeUploadProgressNotifier();
    final notifier =
        getIt<FileStorageService>().onFileProgress(fileUrl: fileUrl);
    notifier.addListener(_onUploadProgressChanged);
    _uploadProgressNotifier = notifier;
    _progressFileUrl = fileUrl;
  }

  @override
  void initState() {
    super.initState();
    _syncUploadProgressNotifier();
  }

  @override
  void didChangeDependencies() {
    if (!PlatformInfo.isMobile) {
      dropManagerState = context.read<EditorDropManagerState?>();
    }
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant FileBlockComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncUploadProgressNotifier();
  }

  @override
  Widget build(BuildContext context) {
    _syncUploadProgressNotifier();
    final url = node.attributes[FileBlockKeys.url];
    final uploadProgress = _uploadProgress;
    final canChooseFile = _canChooseFile && !_isUploadingFromLocal;

    Widget child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => isHovering = true);
        showActionsNotifier.value = true;
      },
      onExit: (_) {
        setState(() => isHovering = false);
        if (!alwaysShowMenu) {
          showActionsNotifier.value = false;
        }
      },
      opaque: false,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _isUploadingFromLocal
            ? null
            : canChooseFile
                ? _openMenu
                : url != null && url.isNotEmpty
                    ? () async => _openFile(context, url)
                    : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isHovering
                ? Theme.of(context).colorScheme.secondary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: isDragging
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                const HSpace(10),
                SizedBox.square(
                  dimension: 36,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FlowySvg(
                        FlowySvgs.slash_menu_icon_file_s,
                        color: Theme.of(context).hintColor,
                        size: const Size.square(24),
                      ),
                      if (_isUploadingFromLocal ||
                          (uploadProgress != null &&
                              uploadProgress.error == null &&
                              !uploadProgress.isWaitingForNetwork &&
                              uploadProgress.progress >= 0 &&
                              !uploadProgress.isReady))
                        SizedBox.square(
                          dimension: 34,
                          child: CircularProgressIndicator(
                            value: _isUploadingFromLocal
                                ? null
                                : uploadProgress?.progress,
                            strokeWidth: 3,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.25),
                          ),
                        ),
                    ],
                  ),
                ),
                const HSpace(10),
                ..._buildTrailing(context),
              ],
            ),
          ),
        ),
      ),
    );

    if (PlatformInfo.isDesktopOrTabletOrWeb) {
      if (canChooseFile) {
        child = DropTarget(
          enable: dropManagerState?.isDropEnabled == true ||
              dropManagerState?.contains(FileBlockKeys.type) == true,
          onDragEntered: (_) {
            if (dropManagerState?.isDropEnabled == true) {
              dropManagerState?.add(FileBlockKeys.type);
              setState(() => isDragging = true);
            }
          },
          onDragExited: (_) {
            if (dropManagerState?.contains(FileBlockKeys.type) == true) {
              dropManagerState?.remove(FileBlockKeys.type);
              setState(() => isDragging = false);
            }
          },
          onDragDone: (details) {
            dropManagerState?.remove(FileBlockKeys.type);
            insertFileFromLocal(details.files);
          },
          child: AppFlowyPopover(
            controller: controller,
            direction: PopoverDirection.bottomWithCenterAligned,
            constraints: const BoxConstraints(
              maxWidth: 480,
              maxHeight: 340,
              minHeight: 80,
            ),
            clickHandler: PopoverClickHandler.gestureDetector,
            onOpen: () => dropManagerState?.add(
              FileBlockComponent.uploadDragKey,
            ),
            onClose: () => dropManagerState?.remove(
              FileBlockComponent.uploadDragKey,
            ),
            popupBuilder: (_) => FileUploadMenu(
              onInsertLocalFile: (files) {
                insertFileFromLocal(files);
                controller.close();
                dropManagerState?.remove(FileBlockComponent.uploadDragKey);
              },
              onInsertNetworkFile: (url) {
                insertNetworkFile(url);
                controller.close();
                dropManagerState?.remove(FileBlockComponent.uploadDragKey);
              },
            ),
            child: child,
          ),
        );
      }

      child = BlockSelectionContainer(
        node: node,
        delegate: this,
        listenable: editorState.selectionNotifier,
        blockColor: editorState.editorStyle.selectionColor,
        supportTypes: const [BlockSelectionType.block],
        child: Padding(
          key: fileKey,
          padding: padding,
          child: child,
        ),
      );
    } else {
      return Padding(
        key: fileKey,
        padding: padding,
        child: MobileBlockActionButtons(
          node: widget.node,
          editorState: editorState,
          child: child,
        ),
      );
    }

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    if (!PlatformInfo.isDesktopOrTabletOrWeb) {
      // show a fixed menu on mobile
      child = MobileBlockActionButtons(
        node: node,
        editorState: editorState,
        extendActionWidgets: _buildExtendActionWidgets(context),
        child: child,
      );
    }

    return child;
  }

  Future<void> _openFile(BuildContext context, String url) async {
    final notifier = _uploadProgressNotifier;
    if (notifier != null && notifier.value.progress < 0) {
      await getIt<FileStorageService>().refreshFileProgress(notifier);
    }
    if (!context.mounted || node.attributes[FileBlockKeys.url] != url) return;
    if (!_canOpenFile) {
      final status = _uploadStatus;
      if (status != null) {
        showToastNotification(
          message: status,
          type: _uploadProgress?.error != null
              ? ToastificationType.error
              : ToastificationType.info,
        );
      }
      return;
    }
    await afLaunchUrlString(url, context: context);
  }

  void _openMenu() {
    if (!_canChooseFile || _isUploadingFromLocal) return;
    if (PlatformInfo.isDesktopOrTabletOrWeb) {
      controller.show();
      dropManagerState?.add(FileBlockComponent.uploadDragKey);
    } else {
      editorState.updateSelectionWithReason(null, extraInfo: {});
      showUploadFileMobileMenu();
    }
  }

  List<Widget> _buildTrailing(BuildContext context) {
    final hasUrl = node.attributes[FileBlockKeys.url]?.isNotEmpty == true;
    final isPreparing = _preparingFileName != null;
    final name =
        _preparingFileName ?? (node.attributes[FileBlockKeys.name] as String?);
    if (name != null && (hasUrl || isPreparing)) {
      final status = isPreparing
          ? _preparationError ?? 'document.plugins.file.preparingUpload'.tr()
          : _uploadStatus;
      return [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FlowyText(name, overflow: TextOverflow.ellipsis),
              if (status != null)
                FlowyText(
                  status,
                  fontSize: 12,
                  overflow: TextOverflow.ellipsis,
                  color: (isPreparing
                              ? _preparationError
                              : _uploadProgress?.error) !=
                          null
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).hintColor,
                ),
            ],
          ),
        ),
        const HSpace(8),
        if (PlatformInfo.isDesktopOrTabletOrWeb) ...[
          ValueListenableBuilder<bool>(
            valueListenable: showActionsNotifier,
            builder: (_, value, __) {
              final url = node.attributes[FileBlockKeys.url];
              if (!value || url == null || url.isEmpty) {
                return const SizedBox.shrink();
              }

              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: menuController.show,
                child: AppFlowyPopover(
                  controller: menuController,
                  triggerActions: PopoverTriggerFlags.none,
                  direction: PopoverDirection.bottomWithRightAligned,
                  onClose: () {
                    setState(
                      () {
                        alwaysShowMenu = false;
                        showActionsNotifier.value = false;
                      },
                    );
                  },
                  popupBuilder: (_) {
                    alwaysShowMenu = true;
                    return FileBlockMenu(
                      controller: menuController,
                      node: node,
                      editorState: editorState,
                      canDownload: () => _canOpenFile,
                    );
                  },
                  child: const FileMenuTrigger(),
                ),
              );
            },
          ),
          const HSpace(8),
        ],
        if (PlatformInfo.isMobile) ...[
          const HSpace(36),
        ],
      ];
    } else {
      return [
        Flexible(
          child: FlowyText(
            isDragging
                ? LocaleKeys.document_plugins_file_placeholderDragging.tr()
                : LocaleKeys.document_plugins_file_placeholderText.tr(),
            overflow: TextOverflow.ellipsis,
            color: Theme.of(context).hintColor,
          ),
        ),
      ];
    }
  }

  // only used on mobile platform
  List<Widget> _buildExtendActionWidgets(BuildContext context) {
    final String? url = widget.node.attributes[FileBlockKeys.url];
    if (url == null || url.isEmpty) {
      return [];
    }

    final urlType = FileUrlType.fromIntValue(
      widget.node.attributes[FileBlockKeys.urlType] ?? 0,
    );

    if (urlType != FileUrlType.network) {
      return [];
    }

    return [
      FlowyOptionTile.text(
        showTopBorder: false,
        text: LocaleKeys.editor_copyLink.tr(),
        leftIcon: const FlowySvg(
          FlowySvgs.m_field_copy_s,
        ),
        onTap: () async {
          context.pop();
          showToastNotification(
            message: LocaleKeys.document_plugins_image_copiedToPasteBoard.tr(),
          );
          await getIt<ClipboardService>().setPlainText(url);
        },
      ),
    ];
  }

  void showUploadFileMobileMenu() {
    showMobileBottomSheet(
      context,
      title: LocaleKeys.document_plugins_file_name.tr(),
      showHeader: true,
      showCloseButton: true,
      showDragHandle: true,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.only(top: 12.0),
          constraints: const BoxConstraints(
            maxHeight: 340,
            minHeight: 80,
          ),
          child: FileUploadMenu(
            onInsertLocalFile: (file) async {
              context.pop();
              await insertFileFromLocal(file);
            },
            onInsertNetworkFile: (url) async {
              context.pop();
              await insertNetworkFile(url);
            },
          ),
        );
      },
    );
  }

  Future<void> insertFileFromLocal(List<XFile> files) async {
    if (files.isEmpty || _isUploadingFromLocal || !_canChooseFile) {
      return;
    }

    final file = files.first;
    final documentBloc = context.read<DocumentBloc>();
    final isLocalMode = documentBloc.isLocalMode;
    final editor = editorState;
    final targetNode = node;
    final previousUrl = targetNode.attributes[FileBlockKeys.url];
    setState(() {
      _isUploadingFromLocal = true;
      _preparingFileName = file.name;
      _preparationError = null;
      isDragging = false;
    });

    try {
      String? url;
      String? errorMsg;
      if (isLocalMode) {
        url = await saveFileToLocalStorage(file.path);
      } else if (await File(file.path).length() > kMaxUploadFileSizeBytes) {
        errorMsg = LocaleKeys.sideBar_singleFileSizeLimitExceeded.tr();
      } else {
        (url, errorMsg) =
            await saveFileToCloudStorage(file.path, documentBloc.documentId);
      }
      if (url == null) {
        _preparationError = errorMsg ?? LocaleKeys.button_uploadFailed.tr();
        return;
      }

      final currentNode = editor.getNodeAtPath(targetNode.path);
      if (editor.isDisposed ||
          !editor.editable ||
          currentNode == null ||
          currentNode.id != targetNode.id ||
          currentNode.attributes[FileBlockKeys.url] != previousUrl) {
        if (!isLocalMode && currentNode?.attributes[FileBlockKeys.url] != url) {
          await DocumentService().deleteFile(url: url);
        }
        return;
      }

      dropManagerState?.remove(FileBlockKeys.type);
      final transaction = editor.transaction
        ..updateNode(currentNode, {
          FileBlockKeys.url: url,
          FileBlockKeys.urlType:
              (isLocalMode ? FileUrlType.local : FileUrlType.cloud)
                  .toIntValue(),
          FileBlockKeys.name: file.name,
          FileBlockKeys.uploadedAt: DateTime.now().millisecondsSinceEpoch,
          FileBlockKeys.uploadedBy:
              documentBloc.state.userProfilePB?.id.toString(),
        });
      await editor.apply(transaction);
      _preparingFileName = null;
    } catch (error, stackTrace) {
      Log.error('Failed to prepare document attachment', error, stackTrace);
      _preparationError = LocaleKeys.button_uploadFailed.tr();
    } finally {
      if (mounted) {
        setState(() => _isUploadingFromLocal = false);
      }
    }
  }

  Future<void> insertNetworkFile(String url) async {
    if (!_canChooseFile || _isUploadingFromLocal) return;
    if (url.isEmpty || !isURL(url)) {
      // show error
      showToastNotification(
        message: LocaleKeys.document_plugins_file_networkUrlInvalid.tr(),
        type: ToastificationType.error,
      );
      return;
    }

    // Remove the file block from the drop state manager
    dropManagerState?.remove(FileBlockKeys.type);

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }

    String name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : "";
    if (name.isEmpty && uri.pathSegments.length > 1) {
      name = uri.pathSegments[uri.pathSegments.length - 2];
    } else if (name.isEmpty) {
      name = uri.host;
    }

    final transaction = editorState.transaction;
    final currentUserId =
        context.read<DocumentBloc?>()?.state.userProfilePB?.id.toString();
    transaction.updateNode(widget.node, {
      FileBlockKeys.url: url,
      FileBlockKeys.urlType: FileUrlType.network.toIntValue(),
      FileBlockKeys.name: name,
      FileBlockKeys.uploadedAt: DateTime.now().millisecondsSinceEpoch,
      FileBlockKeys.uploadedBy: currentUserId,
    });
    await editorState.apply(transaction);
    if (mounted) {
      setState(() {
        _preparingFileName = null;
        _preparationError = null;
      });
    }
  }

  @override
  Position start() => Position(path: widget.node.path);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final renderBox = fileKey.currentContext?.findRenderObject();
    if (renderBox is RenderBox) {
      return padding.topLeft & renderBox.size;
    }
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final rects = getRectsInSelection(Selection.collapsed(position));
    return rects.firstOrNull;
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) {
      return [];
    }
    final parentBox = context.findRenderObject();
    final renderBox = fileKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && renderBox is RenderBox) {
      return [
        renderBox.localToGlobal(Offset.zero, ancestor: parentBox) &
            renderBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox!.localToGlobal(offset);

  @override
  void dispose() {
    _disposeUploadProgressNotifier();
    showActionsNotifier.dispose();
    super.dispose();
  }
}

@visibleForTesting
class FileMenuTrigger extends StatelessWidget {
  const FileMenuTrigger({super.key});

  @override
  Widget build(BuildContext context) {
    return const FlowyHover(
      resetHoverOnRebuild: false,
      child: Padding(
        padding: EdgeInsets.all(4),
        child: FlowySvg(
          FlowySvgs.three_dots_s,
        ),
      ),
    );
  }
}
