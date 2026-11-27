import 'dart:async';

import 'package:appflowy/features/version_history/version_history_page.dart';
import 'package:appflowy/features/version_history/version_history_service.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class VersionHistoryIndexPage extends StatefulWidget {
  const VersionHistoryIndexPage({
    super.key,
    required this.workspaces,
    this.service,
  });

  final Map<String, String> workspaces;
  final VersionHistoryService? service;

  @override
  State<VersionHistoryIndexPage> createState() =>
      _VersionHistoryIndexPageState();
}

class _VersionHistoryIndexPageState extends State<VersionHistoryIndexPage> {
  late final service = widget.service ?? VersionHistoryService();
  late final workspaces = Map<String, String>.of(widget.workspaces);
  final items = <DocumentHistorySummaryPB>[];
  final scrollController = ScrollController();
  Timer? searchDelay;
  String search = '';
  String workspace = '';
  String? error;
  int request = 0;
  bool loading = true;
  bool hasMore = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    searchDelay?.cancel();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final currentRequest = ++request;
    if (!more && scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    final after = more ? items.last : null;
    setState(() {
      loading = true;
      error = null;
      if (!more) {
        items.clear();
        hasMore = false;
      }
    });
    try {
      final page = await service.listDocuments(
        search: search,
        workspace: workspace,
        after: after,
      );
      if (!mounted || currentRequest != request) return;
      setState(() {
        if (!more) items.clear();
        final existing = items.map((item) => item.documentId).toSet();
        items.addAll(page.items.where((item) => existing.add(item.documentId)));
        hasMore = page.hasMore;
        for (final item in page.items) {
          workspaces.putIfAbsent(
            item.workspaceId,
            () => item.workspaceName.isEmpty
                ? 'versionHistory.sharedWorkspace'.tr()
                : item.workspaceName,
          );
        }
      });
    } catch (failure) {
      if (!mounted || currentRequest != request) return;
      setState(() {
        error = failure is FlowyError && failure.code == ErrorCode.NetworkError
            ? 'versionHistory.offline'.tr()
            : 'versionHistory.indexFailed'.tr();
      });
    } finally {
      if (mounted && currentRequest == request) setState(() => loading = false);
    }
  }

  void searchChanged(String value) {
    search = value;
    searchDelay?.cancel();
    request++;
    setState(() {
      items.clear();
      error = null;
      loading = true;
      hasMore = false;
    });
    searchDelay = Timer(const Duration(milliseconds: 250), load);
  }

  Future<void> openDocument(DocumentHistorySummaryPB item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VersionHistoryPage(
          workspaceId: item.workspaceId,
          view: ViewPB(
            id: item.documentId,
            name: item.name,
            layout: ViewLayoutPB.Document,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dates = DateFormat.yMMMd(context.locale.toString()).add_jm();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('versionHistory.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'versionHistory.close'.tr(),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 340,
                      child: TextField(
                        onChanged: searchChanged,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: 'versionHistory.searchDocuments'.tr(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: workspace,
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text('versionHistory.allWorkspaces'.tr()),
                          ),
                          for (final entry in workspaces.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null || value == workspace) return;
                          searchDelay?.cancel();
                          setState(() => workspace = value);
                          load();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(error!),
                      TextButton(
                        onPressed: () => load(more: items.isNotEmpty),
                        child: Text('versionHistory.retry'.tr()),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: items.isEmpty && !loading && error == null
                    ? Center(
                        child: Text(
                          (search.trim().isEmpty
                                  ? 'versionHistory.noHistoryDocuments'
                                  : 'versionHistory.noMatchingDocuments')
                              .tr(),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount:
                            items.length + (hasMore && error == null ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == items.length) {
                            return Center(
                              child: TextButton(
                                onPressed:
                                    loading ? null : () => load(more: true),
                                child: Text('versionHistory.more'.tr()),
                              ),
                            );
                          }
                          final item = items[index];
                          final location = [
                            workspaces[item.workspaceId] ?? '',
                            ...item.path,
                          ].where((part) => part.isNotEmpty).join(' / ');
                          final time = dates.format(
                            DateTime.fromMillisecondsSinceEpoch(
                              item.latestVersionAt.toInt(),
                            ),
                          );
                          return ListTile(
                            key: ValueKey(item.documentId),
                            leading: const Icon(Icons.description_outlined),
                            title: Text(
                              item.name.isEmpty
                                  ? 'versionHistory.untitled'.tr()
                                  : item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(time),
                            onTap: () => openDocument(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
