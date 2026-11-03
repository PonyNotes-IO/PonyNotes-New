import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/document/application/note_relations_controller.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NoteRelationsScope extends StatefulWidget {
  const NoteRelationsScope({
    super.key,
    required this.pageId,
    required this.editorState,
    required this.child,
  });
  final String pageId;
  final EditorState editorState;
  final Widget child;
  @override
  State<NoteRelationsScope> createState() => _NoteRelationsScopeState();
}

class _NoteRelationsScopeState extends State<NoteRelationsScope> {
  NoteRelationsController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workspace = context.watch<UserWorkspaceBloc>().state;
    final id = workspace.currentWorkspace?.workspaceId;
    final identity = '${workspace.userProfile.id}/$id';
    if (id == null) {
      _controller?.dispose();
      _controller = null;
    } else if (_controller?.identity != identity ||
        _controller?.editorState != widget.editorState ||
        _controller?.pageId != widget.pageId) {
      _controller?.dispose();
      _controller = NoteRelationsController(
        pageId: widget.pageId,
        workspaceId: id,
        identity: identity,
        editorState: widget.editorState,
      )..start();
    }
  }

  @override
  void didUpdateWidget(covariant NoteRelationsScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorState != widget.editorState ||
        oldWidget.pageId != widget.pageId) {
      _controller?.dispose();
      final workspace = context.read<UserWorkspaceBloc>().state;
      final id = workspace.currentWorkspace?.workspaceId;
      if (id == null) {
        _controller = null;
      } else {
        _controller = NoteRelationsController(
          pageId: widget.pageId,
          workspaceId: id,
          identity: '${workspace.userProfile.id}/$id',
          editorState: widget.editorState,
        )..start();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider<NoteRelationsController?>.value(
        value: _controller,
        child: widget.child,
      );
}
