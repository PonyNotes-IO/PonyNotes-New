import 'package:flutter/material.dart';
import 'package:flowy_infra/theme_extension.dart';

/// A simple todo item model for the calendar todo list.
class CalendarTodoItem {
  CalendarTodoItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.dueTime,
  });

  final String id;
  final String title;
  bool isCompleted;
  final String? dueTime; // e.g. "14:00"
}

/// Right-side panel showing todo items for the selected date.
class TodoListPanel extends StatefulWidget {
  const TodoListPanel({
    super.key,
    required this.todos,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
  });

  final List<CalendarTodoItem> todos;
  final ValueChanged<String> onAdd; // title
  final ValueChanged<CalendarTodoItem> onToggle;
  final ValueChanged<CalendarTodoItem> onDelete;

  @override
  State<TodoListPanel> createState() => _TodoListPanelState();
}

class _TodoListPanelState extends State<TodoListPanel> {
  final _addController = TextEditingController();
  final _addFocusNode = FocusNode();
  bool _isAdding = false;

  @override
  void dispose() {
    _addController.dispose();
    _addFocusNode.dispose();
    super.dispose();
  }

  void _submitAdd() {
    final title = _addController.text.trim();
    if (title.isNotEmpty) {
      widget.onAdd(title);
      _addController.clear();
    }
    setState(() => _isAdding = false);
  }

  @override
  Widget build(BuildContext context) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.checklist, size: 18, color: af.lightIconColor),
              const SizedBox(width: 8),
              Text(
                '待办事项',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: af.onBackground,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  setState(() => _isAdding = true);
                  _addFocusNode.requestFocus();
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.add, size: 18, color: af.lightIconColor),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: af.borderColor),
        // Add input
        if (_isAdding)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    focusNode: _addFocusNode,
                    style: TextStyle(fontSize: 13, color: af.onBackground),
                    decoration: InputDecoration(
                      hintText: '添加待办...',
                      hintStyle: TextStyle(color: af.secondaryTextColor),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: af.borderColor),
                      ),
                    ),
                    onSubmitted: (_) => _submitAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _submitAdd,
                  child: Icon(Icons.check, size: 20, color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
        // Todo list
        Expanded(
          child: widget.todos.isEmpty
              ? Center(
                  child: Text(
                    '暂无待办',
                    style: TextStyle(
                      fontSize: 13,
                      color: af.secondaryTextColor,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: widget.todos.length,
                  itemBuilder: (ctx, i) => _buildTodoItem(af, theme, widget.todos[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildTodoItem(AFThemeExtension af, ThemeData theme, CalendarTodoItem todo) {
    return InkWell(
      onTap: () => widget.onToggle(todo),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: todo.isCompleted,
                onChanged: (_) => widget.onToggle(todo),
                activeColor: theme.colorScheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                todo.title,
                style: TextStyle(
                  fontSize: 13,
                  color: todo.isCompleted
                      ? af.secondaryTextColor
                      : af.onBackground,
                  decoration: todo.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            if (todo.dueTime != null)
              Text(
                todo.dueTime!,
                style: TextStyle(
                  fontSize: 12,
                  color: af.secondaryTextColor,
                ),
              ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => widget.onDelete(todo),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 14, color: af.lightIconColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
