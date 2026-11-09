import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hotkey_manager/hotkey_manager.dart' show KeyCodeParser;

/// Shared by native hotkeys, editor commands and focused component shortcuts.
final shortcutChanges = ValueNotifier(0);
void notifyShortcutChanges() => shortcutChanges.value++;
bool isRecordingShortcut = false;

String get _primary =>
    defaultTargetPlatform == TargetPlatform.macOS ? 'cmd' : 'ctrl';

final Map<String, (String, String)> componentShortcutDefaults = {
  'app.sidebar': ('应用 · 折叠 / 展开侧边栏', '$_primary+backslash,$_primary+period'),
  'app.theme': ('应用 · 切换浅色 / 深色主题', '$_primary+alt+shift+l'),
  'app.closeTab': ('应用 · 关闭当前标签页', '$_primary+w'),
  'app.previousTab': ('应用 · 上一个标签页', '$_primary+page up'),
  'app.nextTab': ('应用 · 下一个标签页', '$_primary+page down'),
  'app.rename': ('应用 · 重命名当前页面', 'f2'),
  'app.zoomIn': (
    '应用 · 放大界面',
    '$_primary+equal,$_primary+numpad add,$_primary+add'
  ),
  'app.zoomOut': ('应用 · 缩小界面', '$_primary+minus,$_primary+numpad subtract'),
  'app.resetZoom': ('应用 · 重置缩放', '$_primary+digit 0,$_primary+numpad 0'),
  'app.nextSpace': ('应用 · 下一个空间', '$_primary+o'),
  'app.newPage': ('应用 · 新建页面', '$_primary+n'),
  'app.settings': ('应用 · 打开 / 关闭设置', '$_primary+comma'),
  'app.palette': ('应用 · 打开 / 关闭命令面板', '$_primary+p'),
  'editor.find': ('编辑器 · 查找', '$_primary+f'),
  'editor.replace': ('编辑器 · 查找和替换', '$_primary+h'),
  'board.previous': ('看板 · 上一张卡片', 'arrow up'),
  'board.next': ('看板 · 下一张卡片', 'arrow down'),
  'board.selectPrevious': ('看板 · 向上扩展选择', 'shift+arrow up'),
  'board.selectNext': ('看板 · 向下扩展选择', 'shift+arrow down'),
  'board.clear': ('看板 · 清除选择', 'escape'),
  'board.delete': ('看板 · 删除卡片', 'delete,backspace'),
  'board.open': ('看板 · 打开卡片', 'enter,numpad enter'),
  'board.createAfter': ('看板 · 在下方新建卡片', 'shift+enter'),
  'board.createBefore': ('看板 · 在上方新建卡片', '$_primary+shift+arrow up'),
  'board.previousGroup': ('看板 · 移到上一个分组', 'comma'),
  'board.nextGroup': ('看板 · 移到下一个分组', 'period'),
  'board.edit': ('看板 · 编辑卡片标题', 'e'),
  'board.createBottom': ('看板 · 分组底部新建卡片', 'n'),
  'cell.submit': ('数据库单元格 · 提交编辑', 'enter'),
  'cell.cancel': ('数据库单元格 · 结束编辑', 'escape'),
  'cell.copy': ('数据库单元格 · 复制', '$_primary+c'),
  'checklist.select': ('清单 · 选中任务', '$_primary+enter'),
  'row.submit': ('行标题 · 提交编辑', 'enter'),
  'row.cancel': ('行标题 · 结束编辑', 'escape'),
  'dropdown.previous': ('下拉菜单 · 上一项', 'arrow up'),
  'dropdown.next': ('下拉菜单 · 下一项', 'arrow down'),
  'dialog.close': ('弹窗 · 关闭', 'escape'),
};

final componentShortcutEvents = componentShortcutDefaults.entries.map((entry) {
  return CommandShortcutEvent(
    key: entry.key,
    command: entry.value.$2,
    getDescription: () => entry.value.$1,
    handler: (_) => KeyEventResult.ignored,
  );
}).toList();

final allShortcutEvents = [
  // Snapshot defaults before any saved overrides are applied.
  ..._editorEventsWithDefaults(),
  ...componentShortcutEvents,
];

List<CommandShortcutEvent> _editorEventsWithDefaults() {
  defaultCommandShortcutEvents;
  return commandShortcutEvents;
}

final allDefaultShortcutEvents = [
  ...defaultCommandShortcutEvents.map((e) => e.copyWith()),
  ...componentShortcutDefaults.entries.map(
    (entry) => CommandShortcutEvent(
      key: entry.key,
      command: entry.value.$2,
      getDescription: () => entry.value.$1,
      handler: (_) => KeyEventResult.ignored,
    ),
  ),
];

CommandShortcutEvent shortcutFor(String id) =>
    allShortcutEvents.firstWhere((event) => event.key == id);

void setShortcutCommand(CommandShortcutEvent event, String command) {
  if (command.isEmpty) {
    event.clearCommand();
  } else {
    event.updateCommand(command: command);
  }
}

bool isValidShortcutCommand(String command) =>
    command.isEmpty ||
    command.split(',').every((part) {
      final binding = Keybinding.parse(part);
      return keyToCodeMapping.containsKey(binding.keyLabel) &&
          !RegExp(r'^(control|shift|alt|meta)( left| right)?$')
              .hasMatch(binding.keyLabel);
    });

bool isSupportedShortcutCommand(CommandShortcutEvent event, String command) =>
    isValidShortcutCommand(command) &&
    (command.isEmpty ||
        !event.key.startsWith('app.') ||
        command.split(',').every(
              (part) =>
                  KeyCodeParser.fromLogicalKey(
                    LogicalKeyboardKey(Keybinding.parse(part).keyCode),
                  ) !=
                  null,
            ));

String shortcutScope(CommandShortcutEvent event) {
  if (componentShortcutDefaults.containsKey(event.key)) {
    return event.key.split('.').first;
  }
  if (localizedCodeBlockCommands.any((e) => e.key == event.key)) return 'code';
  if (simpleTableCommands.any((e) => e.key == event.key)) return 'table';
  return 'editor';
}

bool shortcutScopesOverlap(CommandShortcutEvent a, CommandShortcutEvent b) {
  final first = shortcutScope(a), second = shortcutScope(b);
  return first == 'app' || second == 'app' || first == second;
}

/// Null triggers makes Flutter recheck the current binding after a live edit.
class ConfiguredActivator extends ShortcutActivator {
  const ConfiguredActivator(this.id);
  final String id;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => null;

  @override
  String debugDescribeKeys() => shortcutFor(id).command;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      !isRecordingShortcut &&
      (event is KeyDownEvent || event is KeyRepeatEvent) &&
      shortcutFor(id).keybindings.containsKeyEvent(event);
}

bool matchesShortcut(String id, KeyEvent event) =>
    ConfiguredActivator(id).accepts(event, HardwareKeyboard.instance);

class ConfiguredDialogShortcuts extends StatelessWidget {
  const ConfiguredDialogShortcuts({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ShortcutConfiguration(
        child: ListenableBuilder(
          listenable: shortcutChanges,
          builder: (context, _) => Shortcuts(
            shortcuts: {
              const SingleActivator(LogicalKeyboardKey.escape):
                  const DoNothingAndStopPropagationIntent(),
              for (final binding in shortcutFor('dialog.close').keybindings)
                SingleActivator(
                  LogicalKeyboardKey(binding.keyCode),
                  control: binding.isControlPressed,
                  meta: binding.isMetaPressed,
                  alt: binding.isAltPressed,
                  shift: binding.isShiftPressed,
                ): const DismissIntent(),
            },
            child: child,
          ),
        ),
      );
}

class ShortcutConfiguration extends InheritedNotifier<ValueNotifier<int>> {
  ShortcutConfiguration({super.key, required super.child})
      : super(notifier: shortcutChanges);
}

String shortcutLabel(BuildContext context, String id) {
  context.dependOnInheritedWidgetOfExactType<ShortcutConfiguration>();
  return shortcutFor(id)
      .command
      .split(',')
      .where((part) => part.isNotEmpty)
      .map(displayShortcut)
      .join(' / ');
}

String displayShortcut(String command) {
  final binding = Keybinding.parse(command);
  final label = const {
        'backslash': r'\',
        'comma': ',',
        'period': '.',
        'equal': '=',
        'minus': '-',
        'arrow up': '↑',
        'arrow down': '↓',
        'arrow left': '←',
        'arrow right': '→',
        'escape': 'Esc',
        'page up': 'Page Up',
        'page down': 'Page Down',
        'numpad enter': 'Num Enter',
        'numpad add': 'Num +',
        'numpad subtract': 'Num −',
        'add': '+',
      }[binding.keyLabel] ??
      binding.keyLabel
          .replaceFirst('digit ', '')
          .replaceFirst('numpad ', 'Num ')
          .replaceFirstMapped(RegExp('^.'), (match) => match[0]!.toUpperCase());
  return [
    if (binding.isControlPressed) 'Ctrl',
    if (binding.isMetaPressed)
      defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd' : 'Win',
    if (binding.isAltPressed) 'Alt',
    if (binding.isShiftPressed) 'Shift',
    label,
  ].join(' + ');
}
