import 'dart:async';

import 'package:appflowy/features/shared_section/data/repositories/rust_shared_pages_repository_impl.dart';
import 'package:appflowy/features/shared_section/logic/shared_section_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../features/workspace/logic/workspace_bloc.dart';
import '../../../../../application/menu/sidebar_sections_bloc.dart';

class SidebarShareButton extends StatefulWidget {
  const SidebarShareButton({super.key});

  @override
  State<SidebarShareButton> createState() => _SidebarShareButtonState();
}

class _SidebarShareButtonState extends State<SidebarShareButton>
    with WidgetsBindingObserver {
  bool _isExpanded = false;
  List<ViewPB> _userSharedNotes = [];
  bool _isLoading = false;
  late final SharedSectionBloc _sharedSectionBloc;
  String _workspaceId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId ??
            '';
    _sharedSectionBloc = _createSharedSectionBloc(_workspaceId);
    _loadUserSharedNotes();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sharedSectionBloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSharedData();
    }
  }

  SharedSectionBloc _createSharedSectionBloc(String workspaceId) {
    return SharedSectionBloc(
      workspaceId: workspaceId,
      repository: RustSharePagesRepositoryImpl(),
      enablePolling: true,
    )..add(const SharedSectionInitEvent());
  }

  Future<void> _handleWorkspaceChanged(String? workspaceId) async {
    final newWorkspaceId = workspaceId ?? '';
    if (newWorkspaceId.isEmpty || newWorkspaceId == _workspaceId) {
      return;
    }

    await _sharedSectionBloc.close();
    if (!mounted) {
      return;
    }

    setState(() {
      _workspaceId = newWorkspaceId;
      _isExpanded = false;
      _isLoading = false;
      _userSharedNotes = [];
      _sharedSectionBloc = _createSharedSectionBloc(newWorkspaceId);
    });
    _refreshSharedData();
  }

  void _refreshSharedData() {
    _loadUserSharedNotes();
    _sharedSectionBloc.add(const SharedSectionRefreshEvent());
  }

  Future<void> _loadUserSharedNotes() async {
    setState(() => _isLoading = true);
    
    try {
      // Get current workspace ID
      final workspaceBloc = context.read<UserWorkspaceBloc>();
      final workspaceId = workspaceBloc.state.currentWorkspace?.workspaceId ?? '';
      
      if (workspaceId.isEmpty) {
        Log.error('Workspace ID is empty');
        setState(() => _isLoading = false);
        return;
      }
      
      // Get private views (these are the ones that are "shared" - hidden from workspace)
      final payload = GetWorkspaceViewPB.create()..value = workspaceId;
      final result = await FolderEventReadPrivateViews(payload).send();
      
      result.fold(
        (privateViews) {
          // Log.debug('Found ${privateViews.items.length} private/shared notes'); // PonyNotes: 关闭非白板日志
          
          // Backend already filters out trash views, so we can use them directly
          setState(() {
            _userSharedNotes = privateViews.items;
            _isLoading = false;
          });
        },
        (error) {
          Log.error('Failed to get private views: $error');
          setState(() {
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      Log.error('Exception in _loadUserSharedNotes: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocProvider.value(
      value: _sharedSectionBloc,
      child: BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
        listenWhen: (previous, current) =>
            previous.currentWorkspace?.workspaceId !=
            current.currentWorkspace?.workspaceId,
        listener: (context, state) async {
          await _handleWorkspaceChanged(state.currentWorkspace?.workspaceId);
        },
        child: BlocListener<SidebarSectionsBloc, SidebarSectionsState>(
          listenWhen: (prev, curr) =>
              prev.section.privateViews.length !=
              curr.section.privateViews.length,
          listener: (context, state) {
            _refreshSharedData();
          },
          child: BlocBuilder<SharedSectionBloc, SharedSectionState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(theme.borderRadius.s),
                      onTap: () {
                        setState(() => _isExpanded = !_isExpanded);
                        if (_isExpanded) {
                          _loadUserSharedNotes(); // Refresh when expanding
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            FlowySvg(
                              FlowySvgs.shared_section_icon_m,
                              size: const Size.square(16.0),
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FlowyText.medium(
                                '共享',
                                fontSize: 14.0,
                                figmaLineHeight: 17.0,
                                color: AppFlowyTheme.of(context)
                                    .textColorScheme
                                    .primary,
                              ),
                            ),
                            Icon(
                              _isExpanded
                                  ? Icons.keyboard_arrow_down
                                  : Icons.keyboard_arrow_right,
                              size: 16,
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_isExpanded)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 8.0,
                        right: 8.0,
                        bottom: 4.0,
                      ),
                      child: _buildUserSharedNotesList(context),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUserSharedNotesList(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    
    if (_userSharedNotes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 20.0, right: 8.0, top: 6.0, bottom: 6.0),
        child: FlowyText.small(
          '暂无分享的笔记',
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    
    return Column(
      children: _userSharedNotes.map((view) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: InkWell(
            borderRadius: BorderRadius.circular(6.0),
            onTap: () {
              context.read<TabsBloc>().openPlugin(view);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  FlowySvg(
                    FlowySvgs.document_s,
                    size: const Size.square(16.0),
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FlowyText.medium(
                      view.name,
                      fontSize: 13.0,
                      figmaLineHeight: 16.0,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
