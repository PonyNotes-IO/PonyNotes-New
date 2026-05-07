import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/widgets/widgets.dart';
import 'package:appflowy/plugins/trash/application/prelude.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/trash.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

class MobileHomeTrashPage extends StatefulWidget {
  const MobileHomeTrashPage({super.key});

  static const routeName = '/trash';

  @override
  State<MobileHomeTrashPage> createState() => _MobileHomeTrashPageState();
}

class _MobileHomeTrashPageState extends State<MobileHomeTrashPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<TrashBloc>()..add(const TrashEvent.initial()),
      child: BlocBuilder<TrashBloc, TrashState>(
        builder: (context, state) {
          final filteredObjects = state.objects.where((obj) {
            if (_searchQuery.isEmpty) return true;
            return obj.name.toLowerCase().contains(_searchQuery.toLowerCase());
          }).toList();

          return Scaffold(
            appBar: AppBar(
              leading: const AppBarBackButton(),
              title: Text(LocaleKeys.trash_text.tr()),
              centerTitle: true,
              actions: [
                state.objects.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        splashRadius: 20,
                        icon: const Icon(Icons.more_horiz),
                        onPressed: () {
                          final trashBloc = context.read<TrashBloc>();
                          showMobileBottomSheet(
                            context,
                            showHeader: true,
                            showCloseButton: true,
                            showDragHandle: true,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                            title: LocaleKeys.trash_mobile_actions.tr(),
                            builder: (_) => Row(
                              children: [
                                Expanded(
                                  child: _TrashActionAllButton(
                                    trashBloc: trashBloc,
                                  ),
                                ),
                                const SizedBox(
                                  width: 16,
                                ),
                                Expanded(
                                  child: _TrashActionAllButton(
                                    trashBloc: trashBloc,
                                    type: _TrashActionType.restoreAll,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ],
            ),
            body: Column(
              children: [
                _TrashSearchBar(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                Expanded(
                  child: filteredObjects.isEmpty
                      ? state.objects.isEmpty
                          ? const _EmptyTrashBin()
                          : const _NoSearchResult()
                      : _DeletedFilesListView(objects: filteredObjects),
                ),
                if (filteredObjects.isNotEmpty) _TrashAutoDeleteHint(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrashSearchBar extends StatelessWidget {
  const _TrashSearchBar({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, child) {
          return TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: '搜索被移入垃圾箱的页面',
              isDense: true,
              prefixIconConstraints: BoxConstraints.loose(const Size(38, 40)),
              prefixIcon: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: FlowySvg(
                  FlowySvgs.m_home_search_icon_m,
                  color: AppFlowyTheme.of(context).iconColorScheme.secondary,
                  size: const Size.square(20),
                ),
              ),
              suffixIcon: value.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        controller.clear();
                        onChanged('');
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
                        child: FlowySvg(
                          FlowySvgs.search_clear_m,
                          color: AppFlowyTheme.of(context).iconColorScheme.tertiary,
                          size: const Size.square(20),
                        ),
                      ),
                    )
                  : null,
              contentPadding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              filled: true,
              fillColor: const Color(0xFFF9F9F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NoSearchResult extends StatelessWidget {
  const _NoSearchResult();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FlowySvg(
            FlowySvgs.m_home_search_icon_m,
            size: Size.square(46),
          ),
          const VSpace(16.0),
          FlowyText.medium(
            '未找到匹配的笔记',
            fontSize: 18.0,
            textAlign: TextAlign.center,
          ),
          const VSpace(8.0),
          FlowyText.regular(
            '尝试其他关键词搜索',
            fontSize: 17.0,
            textAlign: TextAlign.center,
            color: Theme.of(context).hintColor,
          ),
        ],
      ),
    );
  }
}

enum _TrashActionType {
  restoreAll,
  deleteAll,
}

class _EmptyTrashBin extends StatelessWidget {
  const _EmptyTrashBin();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FlowySvg(
            FlowySvgs.m_empty_trash_xl,
            size: Size.square(46),
          ),
          const VSpace(16.0),
          FlowyText.medium(
            LocaleKeys.trash_mobile_empty.tr(),
            fontSize: 18.0,
            textAlign: TextAlign.center,
          ),
          const VSpace(8.0),
          FlowyText.regular(
            LocaleKeys.trash_mobile_emptyDescription.tr(),
            fontSize: 17.0,
            maxLines: 10,
            textAlign: TextAlign.center,
            lineHeight: 1.3,
            color: Theme.of(context).hintColor,
          ),
          const VSpace(kBottomNavigationBarHeight + 36.0),
        ],
      ),
    );
  }
}

class _TrashActionAllButton extends StatelessWidget {
  /// Switch between 'delete all' and 'restore all' feature
  const _TrashActionAllButton({
    this.type = _TrashActionType.deleteAll,
    required this.trashBloc,
  });
  final _TrashActionType type;
  final TrashBloc trashBloc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDeleteAll = type == _TrashActionType.deleteAll;
    return BlocProvider.value(
      value: trashBloc,
      child: BottomSheetActionWidget(
        svg: isDeleteAll ? FlowySvgs.m_trash_delete_m : FlowySvgs.m_trash_restore_m,
        text: isDeleteAll
            ? LocaleKeys.trash_deleteAll.tr()
            : LocaleKeys.trash_restoreAll.tr(),
        onTap: () {
          final trashList = trashBloc.state.objects;
          if (trashList.isNotEmpty) {
            context.pop();
            showFlowyMobileConfirmDialog(
              context,
              title: FlowyText(
                isDeleteAll
                    ? LocaleKeys.trash_confirmDeleteAll_title.tr()
                    : LocaleKeys.trash_restoreAll.tr(),
              ),
              content: FlowyText(
                isDeleteAll
                    ? LocaleKeys.trash_confirmDeleteAll_caption.tr()
                    : LocaleKeys.trash_confirmRestoreAll_caption.tr(),
              ),
              actionButtonTitle: isDeleteAll
                  ? LocaleKeys.trash_deleteAll.tr()
                  : LocaleKeys.trash_restoreAll.tr(),
              actionButtonColor: isDeleteAll
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              onActionButtonPressed: () {
                if (isDeleteAll) {
                  trashBloc.add(
                    const TrashEvent.deleteAll(),
                  );
                } else {
                  trashBloc.add(
                    const TrashEvent.restoreAll(),
                  );
                }
              },
              cancelButtonTitle: LocaleKeys.button_cancel.tr(),
            );
          } else {
            // when there is no deleted files
            // show toast
            Fluttertoast.showToast(
              msg: LocaleKeys.trash_mobile_empty.tr(),
              gravity: ToastGravity.CENTER,
            );
          }
        },
      ),
    );
  }
}

class _DeletedFilesListView extends StatelessWidget {
  const _DeletedFilesListView({required this.objects});

  final List<TrashPB> objects;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        itemBuilder: (context, index) {
          final deletedFile = objects[index];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              // TODO: show different file type icon, implement this feature after TrashPB has file type field
              leading: FlowySvg(
                FlowySvgs.document_s,
                size: const Size.square(24),
                color: theme.colorScheme.onSurface,
              ),
              title: Text(
                deletedFile.name.isEmpty ? '无标题笔记' : deletedFile.name,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurface),
              ),
              horizontalTitleGap: 0,
              tileColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    splashRadius: 20,
                    icon: FlowySvg(
                      FlowySvgs.m_trash_restore_m,
                      size: const Size.square(24),
                      color: theme.colorScheme.onSurface,
                    ),
                    onPressed: () {
                      context
                          .read<TrashBloc>()
                          .add(TrashEvent.putback(deletedFile.id));
                      Fluttertoast.showToast(
                        msg:
                            '${deletedFile.name} ${LocaleKeys.trash_mobile_isRestored.tr()}',
                        gravity: ToastGravity.BOTTOM,
                      );
                    },
                  ),
                  IconButton(
                    splashRadius: 20,
                    icon: FlowySvg(
                      FlowySvgs.m_trash_delete_m,
                      size: const Size.square(24),
                      color: theme.colorScheme.onSurface,
                    ),
                    onPressed: () {
                      context
                          .read<TrashBloc>()
                          .add(TrashEvent.delete(deletedFile));
                      Fluttertoast.showToast(
                        msg:
                            '${deletedFile.name} ${LocaleKeys.trash_mobile_isDeleted.tr()}',
                        gravity: ToastGravity.BOTTOM,
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
        itemCount: objects.length,
      ),
    );
  }
}

class _TrashAutoDeleteHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 36,
        top: 12,
        left: 16,
        right: 16,
      ),
      child: Text(
        '回收站中的笔记将在7天后永久删除',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).hintColor,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
