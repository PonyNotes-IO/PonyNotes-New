import 'package:appflowy/features/version_history/version_history_service.dart';
import 'package:appflowy/features/version_history/version_history_diff.dart';
import 'package:appflowy/features/version_history/version_history_diff_view.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:protobuf/protobuf.dart';

class VersionHistoryPage extends StatefulWidget {
  const VersionHistoryPage({
    super.key,
    required this.view,
    this.service,
  });
  final ViewPB view;
  final VersionHistoryService? service;

  @override
  State<VersionHistoryPage> createState() => _VersionHistoryPageState();
}

class _VersionHistoryPageState extends State<VersionHistoryPage> {
  late final service = widget.service ?? VersionHistoryService();
  final items = <DocumentSnapshotMetaPB>[];
  bool loading = true;
  bool saving = false;
  bool restoring = false;
  bool showDiff = true;
  bool loadingPreview = false;
  bool hasMore = false;
  int days = 0;
  String? error;
  String? previewError;
  String? selectedId;
  DocumentDataPB? selectedDocument;
  HistoryDiff? difference;
  EditorState? editor;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    editor?.dispose();
    super.dispose();
  }

  String errorText(Object value) {
    if (value is InvalidProtocolBufferException) {
      return 'versionHistory.componentMismatch'.tr();
    }
    if (value is FlowyError &&
        value.msg.contains('version_history_unavailable')) {
      return 'versionHistory.membershipRequired'.tr();
    }
    if (value is FlowyError && value.msg.contains('cloud_storage_full')) {
      return 'versionHistory.storageFull'.tr();
    }
    if (value is FlowyError && value.msg.contains('history_document_changed')) {
      return 'versionHistory.documentChanged'.tr();
    }
    return 'versionHistory.failed'.tr();
  }

  void notify(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> load({bool more = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result =
          await service.list(widget.view.id, offset: more ? items.length : 0);
      if (!mounted) return;
      setState(() {
        if (!more) items.clear();
        items.addAll(result.items);
        hasMore = result.hasMore;
        days = result.retentionDays;
      });
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => saving = true);
    try {
      final saved = await service.save(widget.view.id);
      if (!mounted) return;
      notify(
        (saved.reused ? 'versionHistory.alreadySaved' : 'versionHistory.saved')
            .tr(),
      );
      await load();
    } catch (e) {
      if (mounted) {
        notify(errorText(e));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> select(DocumentSnapshotMetaPB item) async {
    setState(() {
      selectedId = item.snapshotId;
      selectedDocument = null;
      difference = null;
      loadingPreview = true;
      previewError = null;
    });
    try {
      final data = await service.get(widget.view.id, item.snapshotId);
      final current = await service.readCurrent(widget.view.id);
      final diff = await compute(compareHistory, (current, data));
      if (!mounted || selectedId != item.snapshotId) return;
      final document = data.toDocument();
      if (document == null) throw StateError('Invalid document');
      final next = EditorState(document: document)..editable = false;
      final previous = editor;
      setState(() {
        selectedDocument = data;
        difference = diff;
        editor = next;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
    } catch (e) {
      if (mounted && selectedId == item.snapshotId) {
        setState(() => previewError = errorText(e));
      }
    } finally {
      if (mounted && selectedId == item.snapshotId) {
        setState(() => loadingPreview = false);
      }
    }
  }

  Future<void> restore() async {
    final id = selectedId;
    if (id == null || restoring) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => restoring = true);
    try {
      await service.restore(widget.view.id, id);
      if (mounted) {
        notify('versionHistory.restored'.tr());
        final selected =
            items.where((item) => item.snapshotId == id).firstOrNull;
        if (selected != null) await select(selected);
      }
    } catch (e) {
      if (mounted) {
        notify(errorText(e));
      }
    } finally {
      if (mounted) {
        await load();
        if (mounted) setState(() => restoring = false);
      }
    }
  }

  String dateLabel(DocumentSnapshotMetaPB item) =>
      DateFormat.yMMMd(context.locale.toString()).add_Hms().format(
            DateTime.fromMillisecondsSinceEpoch(item.createdAt.toInt()),
          );

  Widget list() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('save-document-version'),
                onPressed:
                    saving || restoring || loading || days <= 0 ? null : save,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text('versionHistory.save'.tr()),
              ),
            ),
          ),
          if (days > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'versionHistory.retention'.tr(namedArgs: {'days': '$days'}),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(error!),
                  TextButton(
                    onPressed: () => load(),
                    child: Text('versionHistory.retry'.tr()),
                  ),
                ],
              ),
            ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: items.isEmpty && !loading && error == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'versionHistory.empty'.tr(),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return TextButton(
                          onPressed: loading ? null : () => load(more: true),
                          child: Text('versionHistory.more'.tr()),
                        );
                      }
                      final item = items[index];
                      final date = DateTime.fromMillisecondsSinceEpoch(
                        item.createdAt.toInt(),
                      );
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final group = !date.isBefore(today)
                          ? 'versionHistory.today'
                          : !date.isBefore(
                              today.subtract(const Duration(days: 1)),
                            )
                              ? 'versionHistory.yesterday'
                              : 'versionHistory.earlier';
                      final previous = index == 0
                          ? null
                          : DateTime.fromMillisecondsSinceEpoch(
                              items[index - 1].createdAt.toInt(),
                            );
                      final showGroup = previous == null ||
                          (previous.isBefore(today) != date.isBefore(today)) ||
                          (previous.isBefore(
                                today.subtract(const Duration(days: 1)),
                              ) !=
                              date.isBefore(
                                today.subtract(const Duration(days: 1)),
                              ));
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showGroup)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(
                                group.tr(),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ListTile(
                            selected: selectedId == item.snapshotId,
                            leading: const Icon(Icons.history, size: 20),
                            title: Text(dateLabel(item)),
                            onTap:
                                saving || restoring ? null : () => select(item),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      );

  Widget preview() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  'versionHistory.preview'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: selectedDocument == null ||
                          restoring ||
                          saving ||
                          loadingPreview ||
                          difference?.hasChanges != true
                      ? null
                      : restore,
                  icon: const Icon(Icons.restore, size: 18),
                  label: Text(
                    (restoring
                            ? 'versionHistory.restoring'
                            : 'versionHistory.restore')
                        .tr(),
                  ),
                ),
              ],
            ),
          ),
          if (selectedId != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('versionHistory.restoreHint'.tr()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SegmentedButton<bool>(
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(
                    Theme.of(context).colorScheme.onSurface,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : null,
                  ),
                ),
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text('versionHistory.compare'.tr()),
                    icon: const Icon(Icons.difference_outlined),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('versionHistory.previewTab'.tr()),
                    icon: const Icon(Icons.article_outlined),
                  ),
                ],
                selected: {showDiff},
                onSelectionChanged: (value) =>
                    setState(() => showDiff = value.single),
              ),
            ),
          ],
          const Divider(height: 1),
          Expanded(
            child: loadingPreview
                ? const Center(child: CircularProgressIndicator())
                : previewError != null
                    ? Center(child: Text(previewError!))
                    : editor == null
                        ? Center(child: Text('versionHistory.select'.tr()))
                        : showDiff && difference != null
                            ? HistoryDiffView(difference: difference!)
                            : HistoryDocumentPreview(
                                key: ValueKey(selectedId),
                                editor: editor!,
                                view: widget.view,
                              ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('versionHistory.title'.tr()),
          automaticallyImplyLeading: false,
          leading: selectedId != null && MediaQuery.sizeOf(context).width < 760
              ? IconButton(
                  tooltip: 'versionHistory.back'.tr(),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: restoring
                      ? null
                      : () => setState(() {
                            selectedId = null;
                            selectedDocument = null;
                          }),
                )
              : null,
          actions: [
            IconButton(
              tooltip: 'versionHistory.close'.tr(),
              icon: const Icon(Icons.close),
              onPressed: restoring || saving
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: PopScope(
          canPop: !restoring && !saving,
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 760
                ? Row(
                    children: [
                      SizedBox(width: 300, child: list()),
                      const VerticalDivider(width: 1),
                      Expanded(child: preview()),
                    ],
                  )
                : selectedId == null
                    ? list()
                    : preview(),
          ),
        ),
      );
}

class HistoryDocumentPreview extends StatelessWidget {
  const HistoryDocumentPreview({
    super.key,
    required this.editor,
    required this.view,
  });
  final EditorState editor;
  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    final live = DocumentBloc.findOpen(view.id);
    Widget child = MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => DocumentAppearanceCubit()),
        BlocProvider(create: (_) => DocumentPageStyleBloc(view: view)),
      ],
      child: Builder(
        builder: (context) {
          final style = EditorStyleCustomizer(
            context: context,
            padding: const EdgeInsets.all(24),
            editorState: editor,
          );
          final builders = buildBlockComponentBuilders(
            context: context,
            editorState: editor,
            styleCustomizer: style,
            editable: false,
          );
          for (final type in [
            'grid',
            'board',
            'calendar',
            'sub_page',
            'ai_writer',
          ]) {
            builders[type] = _HistoryReferenceBuilder();
          }
          return AppFlowyEditor(
            editorState: editor,
            editable: false,
            disableKeyboardService: true,
            disableSelectionService: true,
            editorStyle: style.style(),
            blockComponentBuilders: builders,
            blockWrapper: (context, {required node, required child}) =>
                IgnorePointer(child: child),
          );
        },
      ),
    );
    if (live != null) {
      child = BlocProvider<DocumentBloc>.value(value: live, child: child);
    }
    return child;
  }
}

class _HistoryReferenceBuilder extends BlockComponentBuilder {
  @override
  BlockComponentWidget build(BlockComponentContext context) =>
      _HistoryReference(node: context.node);
}

class _HistoryReference extends BlockComponentStatelessWidget {
  const _HistoryReference({required super.node})
      : super(configuration: const BlockComponentConfiguration());
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('versionHistory.reference'.tr()),
      );
}
