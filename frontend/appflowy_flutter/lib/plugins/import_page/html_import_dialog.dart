import 'package:flutter/material.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';

enum HtmlImportMode {
  smartParse,      // 智能解析（推荐）
  showSource,      // 显示HTML源代码
  legacyParse,     // 传统解析（html2md）
}

class HtmlImportDialog extends StatefulWidget {
  final HtmlImportMode? initialMode;
  final Function(HtmlImportMode)? onModeSelected;
  
  const HtmlImportDialog({
    super.key,
    this.initialMode,
    this.onModeSelected,
  });

  @override
  State<HtmlImportDialog> createState() => _HtmlImportDialogState();

  /// 显示HTML导入选项对话框
  static Future<HtmlImportMode?> show(
    BuildContext context, {
    HtmlImportMode? initialMode,
    Function(HtmlImportMode)? onModeSelected,
  }) {
    return showDialog<HtmlImportMode>(
      context: context,
      builder: (context) => HtmlImportDialog(
        initialMode: initialMode,
        onModeSelected: onModeSelected,
      ),
    );
  }
}

class _HtmlImportDialogState extends State<HtmlImportDialog> {
  late HtmlImportMode _selectedMode;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode ?? HtmlImportMode.smartParse;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const FlowyText.medium('HTML导入选项', fontSize: 16),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FlowyText.regular(
              'HTML文件可以用不同方式导入，请选择最适合您需求的方式：',
              fontSize: 14,
            ),
            const SizedBox(height: 16),
            
            // 智能解析选项
            RadioListTile<HtmlImportMode>(
              value: HtmlImportMode.smartParse,
              groupValue: _selectedMode,
              onChanged: (value) {
                setState(() {
                  _selectedMode = value!;
                });
              },
              title: const FlowyText.medium('智能解析（推荐）', fontSize: 14),
              subtitle: const FlowyText.regular(
                '使用专业HTML解析器，保留文档结构、标题、链接、表格等格式',
                fontSize: 12,
              ),
            ),
            
            // 显示源代码选项
            RadioListTile<HtmlImportMode>(
              value: HtmlImportMode.showSource,
              groupValue: _selectedMode,
              onChanged: (value) {
                setState(() {
                  _selectedMode = value!;
                });
              },
              title: const FlowyText.medium('显示HTML源代码', fontSize: 14),
              subtitle: const FlowyText.regular(
                '直接显示HTML源代码，适合复杂页面或需要查看原始代码',
                fontSize: 12,
              ),
            ),
            
            // 传统解析选项
            RadioListTile<HtmlImportMode>(
              value: HtmlImportMode.legacyParse,
              groupValue: _selectedMode,
              onChanged: (value) {
                setState(() {
                  _selectedMode = value!;
                });
              },
              title: const FlowyText.medium('传统解析', fontSize: 14),
              subtitle: const FlowyText.regular(
                '使用Flutter html2md库进行转换，适合简单HTML文档，可能丢失部分格式',
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: const FlowyText.regular('取消', fontSize: 14),
        ),
        ElevatedButton(
          onPressed: () {
            // 调用回调函数（如果提供）
            widget.onModeSelected?.call(_selectedMode);
            // 返回选中的模式
            Navigator.of(context).pop(_selectedMode);
          },
          child: const FlowyText.regular('确定', fontSize: 14),
        ),
      ],
    );
  }
}

