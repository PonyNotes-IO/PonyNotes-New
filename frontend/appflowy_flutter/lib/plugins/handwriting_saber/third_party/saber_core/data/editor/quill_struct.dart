import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Quill 编辑器结构体，管理富文本编辑状态
/// 
/// 用于手写笔记中的文本编辑功能
class QuillStruct {
  QuillStruct({
    required this.controller,
    required this.focusNode,
  });

  /// Quill 文档控制器
  final QuillController controller;
  
  /// 焦点节点
  final FocusNode focusNode;

  /// 创建默认的 QuillStruct 实例
  factory QuillStruct.createDefault() {
    final controller = QuillController.basic();
    final focusNode = FocusNode();
    return QuillStruct(
      controller: controller,
      focusNode: focusNode,
    );
  }

  /// 从 JSON 数据创建 QuillStruct 实例
  factory QuillStruct.fromJson(Map<String, dynamic> json) {
    try {
      final controller = QuillController(
        document: Document.fromJson(json['document'] ?? []),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final focusNode = FocusNode();
      return QuillStruct(
        controller: controller,
        focusNode: focusNode,
      );
    } catch (e) {
      // 如果解析失败，返回空文档
      return QuillStruct.createDefault();
    }
  }

  /// 转换为 JSON 数据
  Map<String, dynamic> toJson() {
    return {
      'document': controller.document.toDelta().toJson(),
    };
  }

  /// 释放资源
  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }

  /// 获取纯文本内容
  String get plainText {
    return controller.document.toPlainText();
  }

  /// 清空内容
  void clear() {
    controller.clear();
  }

  /// 插入文本
  void insertText(String text) {
    final selection = controller.selection;
    controller.replaceText(
      selection.start,
      selection.end - selection.start,
      text,
      TextSelection.collapsed(offset: selection.start + text.length),
    );
  }
}

