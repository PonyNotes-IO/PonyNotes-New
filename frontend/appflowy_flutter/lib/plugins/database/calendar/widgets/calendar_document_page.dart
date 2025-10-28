
// 日历文档视图组件 - 参考回收站的实现
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../workspace/application/settings/appearance/appearance_cubit.dart';
import '../../../../workspace/application/view/view_bloc.dart';
import '../../../document/application/document_bloc.dart';
import '../../../document/presentation/editor_page.dart';
import '../../../document/presentation/editor_style.dart';
import 'dart:ui' as ui;

class CalendarDocumentView extends StatefulWidget {
  const CalendarDocumentView({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<CalendarDocumentView> createState() => _CalendarDocumentViewState();
}

class _CalendarDocumentViewState extends State<CalendarDocumentView> {
  late DocumentBloc _documentBloc;
  late ViewBloc _viewBloc;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _initializeBlocs();
  }

  @override
  void didUpdateWidget(CalendarDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当view改变时，重新初始化blocs
    if (oldWidget.view.id != widget.view.id) {
      _disposeBlocs();
      _initializeBlocs();
    }
  }

  void _initializeBlocs() {
    _documentBloc = DocumentBloc(documentId: widget.view.id);
    _viewBloc = ViewBloc(view: widget.view);

    // 延迟初始化，确保系统完全准备好
    _retryInitialization();
  }

  void _retryInitialization() {
    Future.delayed(Duration(milliseconds: 200 * (_retryCount + 1)), () {
      if (mounted) {
        _documentBloc.add(const DocumentEvent.initial());
        _viewBloc.add(const ViewEvent.initial());

        // 确保编辑器状态是可编辑的
        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted && _documentBloc.state.editorState != null) {
            _documentBloc.state.editorState!.editable = true;
          }
        });
      }
    });
  }

  void _disposeBlocs() {
    _documentBloc.close();
    _viewBloc.close();
  }

  @override
  void dispose() {
    _disposeBlocs();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _documentBloc),
        BlocProvider.value(value: _viewBloc),
      ],
      child: BlocBuilder<DocumentBloc, DocumentState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }

          final editorState = state.editorState;
          final error = state.error;
          if (error != null || editorState == null) {
            return _buildErrorView(context, error);
          }

          // 确保编辑器状态是可编辑的
          editorState.editable = true;

          return _buildDocumentView(context, editorState);
        },
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, FlowyError? error) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '无法加载文档内容',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '此文档可能已被删除或损坏',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '错误信息: ${error.msg}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_retryCount < _maxRetries)
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _retryCount++;
                          });
                          _retryInitialization();
                        },
                        icon: Icon(Icons.refresh),
                        label: Text('重试 (${_retryCount + 1}/$_maxRetries)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          Theme.of(context).colorScheme.primary,
                          foregroundColor:
                          Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentView(BuildContext context, EditorState editorState) {
    // 检查文档是否为空或只有空内容
    final hasContent = editorState.document.root.children.any((node) {
      final text = node.delta?.toPlainText() ?? '';
      return text.trim().isNotEmpty;
    });

    // 强制设置编辑器为可编辑状态
    editorState.editable = true;

    // 确保编辑器能够接收焦点
    editorState.selection ??= Selection.collapsed(
      Position(path: [0], offset: 0),
    );

    return Column(
      children: [
        _buildHeader(context),
        const SizedBox(height: 16),
        Expanded(
          child: _buildAppFlowyEditor(context, editorState),
        ),
      ],
    );
  }

  Widget _buildAppFlowyEditor(BuildContext context, EditorState editorState) {
    final isRTL =
        context.read<AppearanceSettingsCubit>().state.layoutDirection ==
            LayoutDirection.rtlLayout;
    final textDirection = isRTL ? ui.TextDirection.rtl : ui.TextDirection.ltr;

    return Directionality(
      textDirection: textDirection,
      child: AppFlowyEditorPage(
        editorState: editorState,
        autoFocus: true,
        // 启用自动焦点
        useViewInfoBloc: false,
        styleCustomizer: EditorStyleCustomizer(
          context: context,
          width: MediaQuery.of(context).size.width,
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          editorState: editorState,
        ),
        placeholderText: (node) {
          // 为空的段落节点提供占位符文本
          if (node.type == ParagraphBlockKeys.type &&
              (node.delta?.toPlainText() ?? '').trim().isEmpty) {
            return '此文档暂无内容，点击编辑按钮开始添加内容';
          }
          return '';
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            widget.view.name.isEmpty ? '无标题笔记' : widget.view.name,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // 创建时间
          Text(
            '创建时间：${_formatCreateTime(widget.view.createTime.toInt())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color:
              Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCreateTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy/MM/dd HH:mm').format(date);
  }
}