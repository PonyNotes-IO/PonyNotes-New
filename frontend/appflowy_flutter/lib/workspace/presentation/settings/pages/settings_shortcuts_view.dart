import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/align_toolbar_item/custom_text_align_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/string_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_copy_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_cut_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_paste_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/math_equation/math_equation_shortcut.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/toggle/toggle_block_shortcuts.dart';
import 'package:appflowy/shared/error_page/error_page.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/settings_shortcuts_cubit.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/settings_shortcuts_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/emoji_picker/emoji_shortcut_event.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

import 'package:appflowy/workspace/application/settings/shortcuts/shortcut_registry.dart';

class SettingsShortcutsView extends StatefulWidget {
  const SettingsShortcutsView({super.key, this.service});
  final SettingsShortcutService? service;
  @override
  State<SettingsShortcutsView> createState() => _SettingsShortcutsViewState();
}

class _SettingsShortcutsViewState extends State<SettingsShortcutsView> {
  String _query = '';
  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) =>
            ShortcutsCubit(widget.service ?? SettingsShortcutService())
              ..fetchShortcuts(),
        child: Builder(
          builder: (context) => SettingsBody(
            title: LocaleKeys.settings_shortcutsPage_title.tr(),
            autoSeparate: false,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 300,
                    child: AFTextField(
                      onChanged: (value) => setState(
                        () => _query = value.toLowerCase(),
                      ),
                      hintText: '搜索功能或组合键',
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('一键恢复默认'),
                    onPressed: () => showConfirmDialog(
                      context: context,
                      title: LocaleKeys.settings_shortcutsPage_resetDialog_title
                          .tr(),
                      description: '将应用、编辑器和组件的全部快捷键恢复为默认组合键。',
                      confirmLabel: LocaleKeys
                          .settings_shortcutsPage_resetDialog_buttonLabel
                          .tr(),
                      onConfirm: (_) {
                        context.read<ShortcutsCubit>().resetToDefault();
                        Navigator.of(context).pop();
                      },
                      style: ConfirmPopupStyle.cancelAndOk,
                    ),
                  ),
                ],
              ),
              const VSpace(12),
              const Text('点击右侧编辑按钮，直接按下组合键后保存。修改立即生效，并在下次启动时保留。'),
              const VSpace(24),
              BlocBuilder<ShortcutsCubit, ShortcutsState>(
                builder: (context, state) {
                  if (state.status.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state.status.isFailure) {
                    return FlowyErrorPage.message(
                      state.error,
                      howToFix: '请重试，或恢复默认快捷键。',
                    );
                  }
                  final filtered = state.commandShortcutEvents
                      .where(
                        (event) =>
                            event.afLabel.toLowerCase().contains(_query) ||
                            event.command.toLowerCase().contains(_query),
                      )
                      .toList();
                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('没有匹配的快捷键'),
                    );
                  }
                  final groups = <String, List<CommandShortcutEvent>>{};
                  for (final event in filtered) {
                    groups
                        .putIfAbsent(shortcutScope(event), () => [])
                        .add(event);
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final scope in [
                        'app',
                        'editor',
                        'table',
                        'code',
                        'board',
                        'cell',
                        'checklist',
                        'row',
                        'dropdown',
                        'dialog',
                      ])
                        if (groups.containsKey(scope)) ...[
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 16,
                              bottom: 12,
                            ),
                            child: Text(
                              const {
                                'app': '应用',
                                'editor': '文档编辑',
                                'table': '表格单元格',
                                'code': '代码块',
                                'board': '看板',
                                'cell': '数据库单元格',
                                'checklist': '清单',
                                'row': '行标题',
                                'dropdown': '下拉菜单',
                                'dialog': '弹窗',
                              }[scope]!,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          for (final event in groups[scope]!)
                            ShortcutSettingTile(command: event),
                        ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
}

class ShortcutSettingTile extends StatelessWidget {
  const ShortcutSettingTile({super.key, required this.command});
  final CommandShortcutEvent command;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                command.afLabel.split(' · ').last,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const HSpace(12),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (command.command.isEmpty) const Text('未设置'),
                  for (final binding
                      in command.command.split(',').where((s) => s.isNotEmpty))
                    KeyBadge(keyLabel: displayShortcut(binding)),
                ],
              ),
            ),
            IconButton(
              tooltip: LocaleKeys.settings_shortcutsPage_editTooltip.tr(),
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () async {
                isRecordingShortcut = true;
                try {
                  await showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => ShortcutRecorderDialog(
                      command: command,
                      cubit: context.read<ShortcutsCubit>(),
                    ),
                  );
                } finally {
                  isRecordingShortcut = false;
                }
              },
            ),
          ],
        ),
      );
}

class ShortcutRecorderDialog extends StatefulWidget {
  const ShortcutRecorderDialog({
    super.key,
    required this.command,
    required this.cubit,
  });
  final CommandShortcutEvent command;
  final ShortcutsCubit cubit;
  @override
  State<ShortcutRecorderDialog> createState() => _ShortcutRecorderDialogState();
}

class _ShortcutRecorderDialogState extends State<ShortcutRecorderDialog> {
  late String _command = widget.command.command;
  String? _error;
  bool _saving = false;
  late final FocusNode _focusNode = FocusNode(
    onKeyEvent: (_, event) {
      if (_saving || event is! KeyDownEvent) return KeyEventResult.handled;
      final command = event.toCommand;
      if (command.isNotEmpty && isValidShortcutCommand(command)) {
        if (!isSupportedShortcutCommand(widget.command, command)) {
          setState(() => _error = '当前平台不支持这个组合键，请换一个键。');
          return KeyEventResult.handled;
        }
        setState(() {
          _command = command;
          _error = null;
        });
        _focusNode.nextFocus();
      }
      return KeyEventResult.handled;
    },
  );
  @override
  void initState() {
    super.initState();
    isRecordingShortcut = true;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    isRecordingShortcut = false;
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final success = await widget.cubit.rebind(widget.command, _command);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = '保存失败，请重试。原有快捷键未更改。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = widget.cubit.conflictsFor(widget.command, _command);
    return AlertDialog(
      title: Text(widget.command.afLabel),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('点击录制区后按下组合键。Enter、Esc 和 Tab 也可设为快捷键；使用下方按钮保存或取消。'),
            const VSpace(16),
            Focus(
              focusNode: _focusNode,
              autofocus: true,
              child: GestureDetector(
                onTap: _focusNode.requestFocus,
                child: Semantics(
                  label: '快捷键录制区',
                  button: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _command.isEmpty
                          ? '未设置'
                          : _command
                              .split(',')
                              .map(displayShortcut)
                              .join(' / '),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            if (conflicts.isNotEmpty) ...[
              const VSpace(16),
              Text(
                '该组合键已用于：${conflicts.map((e) => e.afLabel).join('、')}。保存将解除这些功能的相同组合键，保留其其他组合键。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (_error != null) ...[
              const VSpace(12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => setState(() => _command = ''),
          child: const Text('清除绑定'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? '保存中…'
                : conflicts.isEmpty
                    ? '保存'
                    : '替换并保存',
          ),
        ),
      ],
    );
  }
}

@visibleForTesting
class KeyBadge extends StatelessWidget {
  const KeyBadge({super.key, required this.keyLabel});
  final String keyLabel;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(keyLabel, style: Theme.of(context).textTheme.bodySmall),
      );
}

extension ToCommand on KeyEvent {
  String get toCommand {
    final key = keyToCodeMapping.keys
        .where((name) => keyToCodeMapping[name] == logicalKey.keyId)
        .firstOrNull;
    if (key == null) return '';
    final command = [
      if (HardwareKeyboard.instance.isControlPressed) 'ctrl',
      if (HardwareKeyboard.instance.isMetaPressed) 'meta',
      if (HardwareKeyboard.instance.isShiftPressed) 'shift',
      if (HardwareKeyboard.instance.isAltPressed) 'alt',
      key.toLowerCase(),
    ].join('+');
    return isValidShortcutCommand(command) ? command : '';
  }
}

extension CommandLabel on CommandShortcutEvent {
  String get afLabel {
    if (componentShortcutDefaults.containsKey(key)) {
      return componentShortcutDefaults[key]!.$1;
    }
    String? label;

    if (key == toggleToggleListCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_toggleToDoList.tr();
    } else if (key == insertNewParagraphNextToCodeBlockCommand('').key) {
      label = LocaleKeys
          .settings_shortcutsPage_keybindings_insertNewParagraphInCodeblock
          .tr();
    } else if (key == pasteInCodeblock('').key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_pasteInCodeblock.tr();
    } else if (key == selectAllInCodeBlockCommand('').key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_selectAllCodeblock.tr();
    } else if (key == tabToInsertSpacesInCodeBlockCommand('').key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_indentLineCodeblock
          .tr();
    } else if (key == tabToDeleteSpacesInCodeBlockCommand('').key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_outdentLineCodeblock
          .tr();
    } else if (key == tabSpacesAtCurosrInCodeBlockCommand('').key) {
      label = LocaleKeys
          .settings_shortcutsPage_keybindings_twoSpacesCursorCodeblock
          .tr();
    } else if (key == customCopyCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_copy.tr();
    } else if (key == customPasteCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_paste.tr();
    } else if (key == customCutCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_cut.tr();
    } else if (key == customTextLeftAlignCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_alignLeft.tr();
    } else if (key == customTextCenterAlignCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_alignCenter.tr();
    } else if (key == customTextRightAlignCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_alignRight.tr();
    } else if (key == insertInlineMathEquationCommand.key) {
      label = LocaleKeys
          .settings_shortcutsPage_keybindings_insertInlineMathEquation
          .tr();
    } else if (key == undoCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_undo.tr();
    } else if (key == redoCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_redo.tr();
    } else if (key == convertToParagraphCommand.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_convertToParagraph.tr();
    } else if (key == backspaceCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_backspace.tr();
    } else if (key == deleteLeftWordCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_deleteLeftWord.tr();
    } else if (key == deleteLeftSentenceCommand.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_deleteLeftSentence.tr();
    } else if (key == deleteCommand.key) {
      label = UniversalPlatform.isMacOS
          ? LocaleKeys.settings_shortcutsPage_keybindings_deleteMacOS.tr()
          : LocaleKeys.settings_shortcutsPage_keybindings_delete.tr();
    } else if (key == deleteRightWordCommand.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_deleteRightWord.tr();
    } else if (key == moveCursorLeftCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorLeft.tr();
    } else if (key == moveCursorToBeginCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorBeginning
          .tr();
    } else if (key == moveCursorToLeftWordCommand.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_moveCursorLeftWord.tr();
    } else if (key == moveCursorLeftSelectCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorLeftSelect
          .tr();
    } else if (key == moveCursorBeginSelectCommand.key) {
      label = LocaleKeys
          .settings_shortcutsPage_keybindings_moveCursorBeginSelect
          .tr();
    } else if (key == moveCursorLeftWordSelectCommand.key) {
      label = LocaleKeys
          .settings_shortcutsPage_keybindings_moveCursorLeftWordSelect
          .tr();
    } else if (key == moveCursorRightCommand.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_moveCursorRight.tr();
    } else if (key == moveCursorToEndCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorEnd.tr();
    } else if (key == moveCursorToRightWordCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorRightWord
          .tr();
    } else if (key == moveCursorRightSelectCommand.key) {
      label = LocaleKeys
          .settings_shortcutsPage_keybindings_moveCursorRightSelect
          .tr();
    } else if (key == moveCursorEndSelectCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorEndSelect
          .tr();
    } else if (key == moveCursorRightWordSelectCommand.key) {
      label = LocaleKeys
          .settings_shortcutsPage_keybindings_moveCursorRightWordSelect
          .tr();
    } else if (key == moveCursorUpCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorUp.tr();
    } else if (key == moveCursorTopSelectCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorTopSelect
          .tr();
    } else if (key == moveCursorTopCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorTop.tr();
    } else if (key == moveCursorUpSelectCommand.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_moveCursorUpSelect.tr();
    } else if (key == moveCursorDownCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorDown.tr();
    } else if (key == moveCursorBottomSelectCommand.key) {
      label = LocaleKeys
          .settings_shortcutsPage_keybindings_moveCursorBottomSelect
          .tr();
    } else if (key == moveCursorBottomCommand.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_moveCursorBottom.tr();
    } else if (key == moveCursorDownSelectCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_moveCursorDownSelect
          .tr();
    } else if (key == homeCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_home.tr();
    } else if (key == endCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_end.tr();
    } else if (key == toggleBoldCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_toggleBold.tr();
    } else if (key == toggleItalicCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_toggleItalic.tr();
    } else if (key == toggleUnderlineCommand.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_toggleUnderline.tr();
    } else if (key == toggleStrikethroughCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_toggleStrikethrough
          .tr();
    } else if (key == toggleCodeCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_toggleCode.tr();
    } else if (key == toggleHighlightCommand.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_toggleHighlight.tr();
    } else if (key == showLinkMenuCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_showLinkMenu.tr();
    } else if (key == openInlineLinkCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_openInlineLink.tr();
    } else if (key == openLinksCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_openLinks.tr();
    } else if (key == indentCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_indent.tr();
    } else if (key == outdentCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_outdent.tr();
    } else if (key == exitEditingCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_exit.tr();
    } else if (key == pageUpCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_pageUp.tr();
    } else if (key == pageDownCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_pageDown.tr();
    } else if (key == selectAllCommand.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_selectAll.tr();
    } else if (key == pasteTextWithoutFormattingCommand.key) {
      label = LocaleKeys
          .settings_shortcutsPage_keybindings_pasteWithoutFormatting
          .tr();
    } else if (key == emojiShortcutEvent.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_showEmojiPicker.tr();
    } else if (key == enterInTableCell.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_enterInTableCell.tr();
    } else if (key == leftInTableCell.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_leftInTableCell.tr();
    } else if (key == rightInTableCell.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_rightInTableCell.tr();
    } else if (key == upInTableCell.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_upInTableCell.tr();
    } else if (key == downInTableCell.key) {
      label =
          LocaleKeys.settings_shortcutsPage_keybindings_downInTableCell.tr();
    } else if (key == tabInTableCell.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_tabInTableCell.tr();
    } else if (key == shiftTabInTableCell.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_shiftTabInTableCell
          .tr();
    } else if (key == backSpaceInTableCell.key) {
      label = LocaleKeys.settings_shortcutsPage_keybindings_backSpaceInTableCell
          .tr();
    }

    return label ?? description?.capitalize() ?? '';
  }
}
