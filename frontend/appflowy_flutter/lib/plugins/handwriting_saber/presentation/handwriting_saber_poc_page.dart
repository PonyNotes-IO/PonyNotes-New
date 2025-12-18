import 'dart:io';

import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

import '../third_party/saber_core/components/canvas/saber_core_canvas.dart';
import '../third_party/saber_core/data/editor/editor_core_info.dart';
import '../third_party/saber_core/data/editor/page.dart';

/// PoC 页面：暂时只展示占位 UI，并在本地创建一个占位的 .sbn2 文件。
///
/// 后续会在此处嵌入从 Saber 抽取的编辑器与画布。
class HandwritingSaberPocPage extends StatefulWidget {
  const HandwritingSaberPocPage({
    super.key,
    required this.view,
    required this.onViewChanged,
  });

  final ViewPB view;
  final ValueChanged<ViewPB> onViewChanged;

  @override
  State<HandwritingSaberPocPage> createState() =>
      _HandwritingSaberPocPageState();
}

class _HandwritingSaberPocPageState extends State<HandwritingSaberPocPage> {
  late final String _localPath;
  String _status = '初始化中...';

  /// 简化版 Saber 核心数据
  EditorCoreInfo _coreInfo = EditorCoreInfo.empty();

  /// 当前正在绘制的一笔
  Stroke? _currentStroke;

  @override
  void initState() {
    super.initState();
    _localPath = _buildLocalPath(widget.view.id);
    _initLocalFile();
  }

  String _buildLocalPath(String viewId) {
    final directory = Directory.systemTemp;
    return '${directory.path}/handwriting_saber_$viewId.sbn2';
  }

  Future<void> _initLocalFile() async {
    try {
      final file = File(_localPath);
      if (!await file.exists()) {
        await file.writeAsBytes(const <int>[]);
      }
      await _loadFromFile();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      setState(() {
        _status = '本地文件初始化失败：$e';
      });
    }
  }

  Future<void> _loadFromFile() async {
    try {
      final file = File(_localPath);
      if (!await file.exists()) {
        _coreInfo = EditorCoreInfo.empty();
        _status = '本地文件已创建：$_localPath';
        return;
      }
      final content = await file.readAsString();
      _coreInfo = EditorCoreInfo.fromJsonString(content);
      _status = '本地文件已就绪：$_localPath';
    } catch (e) {
      _coreInfo = EditorCoreInfo.empty();
      _status = '读取本地文件失败：$e';
    }
  }

  Future<void> _saveToFile() async {
    try {
      final file = File(_localPath);
      await file.writeAsString(_coreInfo.toJsonString());
      if (mounted) {
        setState(() {
          _status = '已保存到：$_localPath';
        });
      } else {
        _status = '已保存到：$_localPath';
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '保存失败：$e';
        });
      } else {
        _status = '保存失败：$e';
      }
    }
  }

  void _startStroke(Offset position) {
    final Stroke stroke = Stroke(<Offset>[position]);
    setState(() {
      _currentStroke = stroke;
    });
  }

  void _updateStroke(Offset position) {
    final Stroke? stroke = _currentStroke;
    if (stroke == null) {
      return;
    }
    setState(() {
      stroke.points.add(position);
    });
  }

  Future<void> _endStroke() async {
    final Stroke? stroke = _currentStroke;
    if (stroke == null || stroke.points.isEmpty) {
      return;
    }
    if (_coreInfo.pages.isEmpty) {
      _coreInfo = EditorCoreInfo.empty();
    }
    _coreInfo.pages.first.strokes.add(
      Stroke(List<Offset>.from(stroke.points)),
    );
    setState(() {
      _currentStroke = null;
    });
    await _saveToFile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.view.name),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Handwriting Saber PoC',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _status,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (DragStartDetails details) =>
                      _startStroke(details.localPosition),
                  onPanUpdate: (DragUpdateDetails details) =>
                      _updateStroke(details.localPosition),
                  onPanEnd: (DragEndDetails details) => _endStroke(),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: SaberCoreCanvas(
                      coreInfo: _coreInfo,
                      currentStroke: _currentStroke,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


