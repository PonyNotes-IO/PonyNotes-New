import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/plugins/handwriting_native/application/handwriting_native_service.dart';

class HandwritingNativePage extends StatefulWidget {
  const HandwritingNativePage({
    super.key,
    required this.view,
    required this.onViewChanged,
  });

  final ViewPB view;
  final Function(ViewPB) onViewChanged;

  @override
  State<HandwritingNativePage> createState() => _HandwritingNativePageState();
}

class _HandwritingNativePageState extends State<HandwritingNativePage> {
  final HandwritingNativeService _service = HandwritingNativeService();
  bool _isInitializing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    print('🎨 [HandwritingNativePage] initState called');
    print('🎨 [HandwritingNativePage] view.id: ${widget.view.id}');
    print('🎨 [HandwritingNativePage] view.name: ${widget.view.name}');
    print('🎨 [HandwritingNativePage] view.layout: ${widget.view.layout}');
    
    _initializeDocument();
  }

  Future<void> _initializeDocument() async {
    try {
      print('🔧 [HandwritingNativePage] Initializing document...');
      final docId = await _service.getOrCreateDoc(widget.view.id);
      
      if (mounted) {
        setState(() {
          _isInitializing = false;
          if (docId == null) {
            _errorMessage = '无法创建或打开文档';
          }
        });
      }
    } catch (e) {
      print('❌ [HandwritingNativePage] Initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '初始化失败: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    print('🗑️ [HandwritingNativePage] dispose called for view: ${widget.view.id}');
    // 关闭文档
    _service.closeDoc(widget.view.id).then((success) {
      if (success) {
        print('✅ [HandwritingNativePage] Document closed');
      } else {
        print('⚠️ [HandwritingNativePage] Failed to close document');
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('🖼️ [HandwritingNativePage] build() called');
    
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.view.name),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化手写笔记...'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.view.name),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        toolbarHeight: 64,
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.view.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 保存按钮（占位）
          Container(
            margin: const EdgeInsets.only(left: 4, right: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.save_outlined, size: 22),
              onPressed: () async {
                // TODO: 获取xopp文件路径并保存
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('保存功能待实现（需要xopp文件路径）'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              tooltip: '保存',
              style: IconButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.edit_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '手写笔记（原生）',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '功能开发中...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
            ),
            const SizedBox(height: 32),
            Text(
              '视图ID: ${widget.view.id}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

