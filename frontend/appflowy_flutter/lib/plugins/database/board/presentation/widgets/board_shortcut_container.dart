import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/board/application/board_actions_bloc.dart';
import 'package:appflowy/plugins/database/board/application/board_bloc.dart';
import 'package:appflowy/plugins/shared/callback_shortcuts.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/shortcut_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'board_focus_scope.dart';

class BoardShortcutContainer extends StatelessWidget {
  const BoardShortcutContainer({
    super.key,
    required this.focusScope,
    required this.child,
  });

  final BoardFocusScope focusScope;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AFCallbackShortcuts(
      bindings: _shortcutBindings(context),
      child: FocusScope(
        child: Focus(
          child: Builder(
            builder: (context) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final focusNode = Focus.of(context);
                  focusNode.requestFocus();
                  focusScope.clear();
                },
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, AFBindingCallback> _shortcutBindings(
    BuildContext context,
  ) {
    return {
      const ConfiguredActivator('board.previous'): focusScope.focusPrevious,
      const ConfiguredActivator('board.next'): focusScope.focusNext,
      const ConfiguredActivator('board.selectPrevious'):
          focusScope.adjustRangeUp,
      const ConfiguredActivator('board.selectNext'): focusScope.adjustRangeDown,
      const ConfiguredActivator('board.clear'): focusScope.clear,
      const ConfiguredActivator('board.delete'): () => _removeHandler(context),
      const ConfiguredActivator('board.createBefore'): () =>
          _shiftCmdUpHandler(context),
      const ConfiguredActivator('board.open'): () => _enterHandler(context),
      const ConfiguredActivator('board.createAfter'): () =>
          _shiftEnterHandler(context),
      const ConfiguredActivator('board.previousGroup'): () =>
          _moveGroupToAdjacentGroup(context, true),
      const ConfiguredActivator('board.nextGroup'): () =>
          _moveGroupToAdjacentGroup(context, false),
      const ConfiguredActivator('board.edit'): () => _keyEHandler(context),
      const ConfiguredActivator('board.createBottom'): () =>
          _keyNHandler(context),
    };
  }

  bool _keyEHandler(BuildContext context) {
    if (focusScope.value.length != 1) {
      return false;
    }
    context.read<BoardActionsCubit>().startEditingRow(focusScope.value.first);
    return true;
  }

  bool _keyNHandler(BuildContext context) {
    if (focusScope.value.length != 1) {
      return false;
    }
    context
        .read<BoardActionsCubit>()
        .startCreateBottomRow(focusScope.value.first.groupId);
    focusScope.clear();
    return true;
  }

  bool _enterHandler(BuildContext context) {
    if (focusScope.value.length != 1) {
      return false;
    }
    context
        .read<BoardActionsCubit>()
        .openCardWithRowId(focusScope.value.first.rowId);
    return true;
  }

  bool _shiftEnterHandler(BuildContext context) {
    if (focusScope.value.isEmpty) {
      context
          .read<BoardActionsCubit>()
          .createRow(null, CreateBoardCardRelativePosition.after);
    } else if (focusScope.value.length == 1) {
      context.read<BoardActionsCubit>().createRow(
            focusScope.value.first,
            CreateBoardCardRelativePosition.after,
          );
    } else {
      return false;
    }
    return true;
  }

  bool _shiftCmdUpHandler(BuildContext context) {
    if (focusScope.value.isEmpty) {
      context
          .read<BoardActionsCubit>()
          .createRow(null, CreateBoardCardRelativePosition.before);
    } else if (focusScope.value.length == 1) {
      context.read<BoardActionsCubit>().createRow(
            focusScope.value.first,
            CreateBoardCardRelativePosition.before,
          );
    } else {
      return false;
    }
    return true;
  }

  bool _removeHandler(BuildContext context) {
    if (focusScope.value.length != 1) {
      return false;
    }

    NavigatorOkCancelDialog(
      message: LocaleKeys.grid_row_deleteCardPrompt.tr(),
      onOkPressed: () {
        context.read<BoardBloc>().add(BoardEvent.deleteCards(focusScope.value));
      },
    ).show(context);

    return true;
  }

  bool _moveGroupToAdjacentGroup(BuildContext context, bool toPrevious) {
    if (focusScope.value.length != 1) {
      return false;
    }
    context.read<BoardBloc>().add(
          BoardEvent.moveGroupToAdjacentGroup(
            focusScope.value.first,
            toPrevious,
          ),
        );
    focusScope.clear();
    return true;
  }
}
