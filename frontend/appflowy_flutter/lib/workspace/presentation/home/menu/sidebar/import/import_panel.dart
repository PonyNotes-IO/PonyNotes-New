import 'dart:convert';
import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/plugins/import_page/enhanced_html_import_dialog.dart';
import 'package:appflowy/plugins/import_page/enhanced_pdf_import_dialog.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/migration/editor_migration.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/share/import_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/import/import_type.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

typedef ImportCallback = void Function(
  ImportType type,
  String name,
  List<int>? document,
  List<ViewPB>? importedViews,
);

const _importOptionIconSize = Size.square(20);

Future<void> showImportPanel(
  String parentViewId,
  BuildContext context,
  ImportCallback callback, {
  bool isMobile = false,
}) async {
  if (isMobile) {
    await showMobileBottomSheet<void>(
      context,
      showHeader: true,
      showCloseButton: true,
      showDivider: false,
      useRootNavigator: true,
      title: LocaleKeys.moreAction_import.tr(),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      builder: (_) => ImportPanel(
        parentViewId: parentViewId,
        importCallback: callback,
        isMobile: true,
      ),
    );
    return;
  }

  await FlowyOverlay.show(
    context: context,
    builder: (context) => FlowyDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      expandHeight: false,
      title: FlowyText.semibold(
        LocaleKeys.moreAction_import.tr(),
        fontSize: 20,
        color: Theme.of(context).colorScheme.tertiary,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 10.0,
          horizontal: 20.0,
        ),
        child: ImportPanel(
          parentViewId: parentViewId,
          importCallback: callback,
          isMobile: isMobile,
        ),
      ),
    ),
  );
}

class ImportPanel extends StatefulWidget {
  const ImportPanel({
    super.key,
    required this.parentViewId,
    required this.importCallback,
    this.isMobile = false,
  });

  final String parentViewId;
  final ImportCallback importCallback;
  final bool isMobile;

  @override
  State<ImportPanel> createState() => _ImportPanelState();
}

class _ImportPanelState extends State<ImportPanel> {
  final flowyContainerFocusNode = FocusNode();
  final ValueNotifier<bool> showLoading = ValueNotifier(false);

  @override
  void dispose() {
    flowyContainerFocusNode.dispose();
    showLoading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMobile) {
      return _buildMobilePanel(context);
    }

    final width = MediaQuery.of(context).size.width * 0.7;
    final isNarrow = width < 360;
    final height = isNarrow ? 240.0 : width * 0.5;
    final importTypes = [
      ImportType.csv,
      ImportType.pdf,
      ImportType.markdownOrText,
      ImportType.html,
      ImportType.historyDocument,
      ImportType.historyDatabase,
      ImportType.afDatabase,
    ].where((type) => type.enableOnRelease);
    return KeyboardListener(
      autofocus: true,
      focusNode: flowyContainerFocusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.physicalKey == PhysicalKeyboardKey.escape) {
          _dismissPanel();
        }
      },
      child: Stack(
        children: [
          FlowyContainer(
            Theme.of(context).colorScheme.surface,
            height: height,
            width: width,
            child: GridView.count(
              childAspectRatio: isNarrow ? 4 : 3,
              crossAxisCount: isNarrow ? 1 : 3,
              children: importTypes
                  .map(
                    (e) => Card(
                      child: FlowyButton(
                        leftIcon: e.icon(context),
                        leftIconSize: _importOptionIconSize,
                        text: FlowyText.medium(
                          e.toString(),
                          fontSize: 14,
                          overflow: TextOverflow.ellipsis,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                        onTap: () async {
                          await _importFile(widget.parentViewId, e);
                          if (context.mounted) {
                            _dismissPanel();
                          }
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: showLoading,
            builder: (context, showLoading, child) {
              if (!showLoading) {
                return const SizedBox.shrink();
              }
              return const Center(
                child: CircularProgressIndicator(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMobilePanel(BuildContext context) {
    const importTypes = [
      ImportType.csv,
      ImportType.pdf,
      ImportType.markdownOrText,
      ImportType.html,
    ];

    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < importTypes.length; index++) ...[
              _MobileImportOption(
                key: ValueKey(
                  'mobile-import-option-${importTypes[index].name}',
                ),
                type: importTypes[index],
                onTap: () async {
                  await _importFile(widget.parentViewId, importTypes[index]);
                  if (context.mounted) {
                    _dismissPanel();
                  }
                },
              ),
              if (index != importTypes.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
        ValueListenableBuilder(
          valueListenable: showLoading,
          builder: (context, isLoading, child) {
            if (!isLoading) {
              return const SizedBox.shrink();
            }
            return const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          },
        ),
      ],
    );
  }

  void _dismissPanel() {
    if (widget.isMobile) {
      Navigator.of(context).pop();
    } else {
      FlowyOverlay.pop(context);
    }
  }

  Future<void> _importFile(String parentViewId, ImportType importType) async {
    if (importType == ImportType.pdf || importType == ImportType.html) {
      await showDialog<void>(
        context: context,
        builder: (context) => importType == ImportType.pdf
            ? EnhancedPdfImportDialog(parentViewId: parentViewId)
            : EnhancedHtmlImportDialog(
                parentViewId: parentViewId,
                isMobile: widget.isMobile,
              ),
      );
      return;
    }

    final result = await getIt<FilePickerService>().pickFiles(
      type: FileType.custom,
      allowMultiple: importType.allowMultiSelect,
      allowedExtensions: importType.allowedExtensions,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    showLoading.value = true;

    final importValues = <ImportItemPayloadPB>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) {
        continue;
      }
      final name = p.basenameWithoutExtension(path);

      // 先读字节再用系统编码解码，兼容 GBK 等非 UTF-8 文件
      final fileBytes = await File(path).readAsBytes();
      final data = systemEncoding.decode(fileBytes);

      switch (importType) {
        case ImportType.historyDatabase:
          importValues.add(
            ImportItemPayloadPB.create()
              ..name = name
              ..data = utf8.encode(data)
              ..viewLayout = ViewLayoutPB.Grid
              ..importType = ImportTypePB.HistoryDatabase,
          );
          break;
        case ImportType.historyDocument:
        case ImportType.markdownOrText:
          final bytes = _documentDataFrom(importType, data);
          if (bytes != null) {
            importValues.add(
              ImportItemPayloadPB.create()
                ..name = name
                ..data = bytes
                ..viewLayout = ViewLayoutPB.Document
                ..importType = ImportTypePB.Markdown,
            );
          }
          break;
        case ImportType.csv:
          importValues.add(
            ImportItemPayloadPB.create()
              ..name = name
              ..data = utf8.encode(data)
              ..viewLayout = ViewLayoutPB.Grid
              ..importType = ImportTypePB.CSV,
          );
          break;
        case ImportType.afDatabase:
          importValues.add(
            ImportItemPayloadPB.create()
              ..name = name
              ..data = utf8.encode(data)
              ..viewLayout = ViewLayoutPB.Grid
              ..importType = ImportTypePB.AFDatabase,
          );
          break;
        case ImportType.pdf:
        case ImportType.html:
          break;
      }
    }

    List<ViewPB> importedViews = [];
    if (importValues.isNotEmpty) {
      final result = await ImportBackendService.importPages(
        parentViewId,
        importValues,
      );
      result.fold(
        (views) => importedViews = views.items,
        (_) {},
      );
    }

    showLoading.value = false;
    widget.importCallback(importType, '', null, importedViews);
  }
}

class _MobileImportOption extends StatelessWidget {
  const _MobileImportOption({
    super.key,
    required this.type,
    required this.onTap,
  });

  final ImportType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(8));

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox.fromSize(
                  size: _importOptionIconSize,
                  child: Icon(
                    type.cardIcon,
                    size: 22,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FlowyText.medium(
                    type.toString(),
                    fontSize: 16,
                    overflow: TextOverflow.ellipsis,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Uint8List? _documentDataFrom(ImportType importType, String data) {
  switch (importType) {
    case ImportType.historyDocument:
      final document = EditorMigration.migrateDocument(data);
      return DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
    case ImportType.markdownOrText:
      final document = customMarkdownToDocument(data);
      return DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
    case ImportType.pdf:
    case ImportType.html:
    default:
      assert(false, 'Unsupported Type $importType');
      return null;
  }
}
