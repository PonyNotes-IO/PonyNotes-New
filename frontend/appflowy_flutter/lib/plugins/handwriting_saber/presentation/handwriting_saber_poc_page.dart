import 'dart:io';

import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

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
      setState(() {
        _status = '本地文件已就绪：$_localPath';
      });
    } catch (e) {
      setState(() {
        _status = '本地文件初始化失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.view.name),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Handwriting Saber PoC',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _status,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              '当前阶段：仅创建/校验本地 .sbn2 占位文件。\n'
              '后续会在这里嵌入 Saber 编辑器并接入本地存储与 Cloud 同步。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}


