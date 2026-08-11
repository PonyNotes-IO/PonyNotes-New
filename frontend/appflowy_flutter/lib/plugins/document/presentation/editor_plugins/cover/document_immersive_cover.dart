import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/base/mobile_view_page_bloc.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/cover/document_immersive_cover_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_style/_page_style_cover_image.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/util/string_extension.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/ignore_parent_gesture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';

double kDocumentCoverHeight = 98.0;
double kDocumentTitlePadding = 20.0;

class DocumentImmersiveCover extends StatefulWidget {
  const DocumentImmersiveCover({
    super.key,
    required this.view,
    required this.userProfilePB,
    required this.tabs,
    this.fixedTitle,
  });

  final ViewPB view;
  final UserProfilePB userProfilePB;
  final String? fixedTitle;
  final List<PickerTabType> tabs;

  @override
  State<DocumentImmersiveCover> createState() => _DocumentImmersiveCoverState();
}

class _DocumentImmersiveCoverState extends State<DocumentImmersiveCover> {
  final textEditingController = TextEditingController();
  final scrollController = ScrollController();
  final focusNode = FocusNode();

  late PropertyValueNotifier<Selection?>? selectionNotifier =
      context.read<DocumentBloc>().state.editorState?.selectionNotifier;

  @override
  void initState() {
    super.initState();
    selectionNotifier?.addListener(_unfocus);
    if (widget.view.name.isEmpty) {
      focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    textEditingController.dispose();
    scrollController.dispose();
    selectionNotifier?.removeListener(_unfocus);
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnoreParentGestureWidget(
      child: BlocProvider(
        create: (context) => DocumentImmersiveCoverBloc(view: widget.view)
          ..add(const DocumentImmersiveCoverEvent.initial()),
        child: BlocConsumer<DocumentImmersiveCoverBloc,
            DocumentImmersiveCoverState>(
          listener: (context, state) {
            if (textEditingController.text != state.name) {
              textEditingController.text = state.name;
            }
          },
          builder: (context, state) {
            final icon =
                context.watch<ViewBloc>().state.view.icon.toEmojiIconData();
            final iconAndTitle = _buildIconAndTitle(context, icon);
            return Padding(
              padding: EdgeInsets.only(
                top: state.cover.isNone ? kDocumentTitlePadding : 0,
                bottom: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!state.cover.isNone) _buildCover(context, state),
                  _buildHeaderActions(context, state, icon),
                  iconAndTitle,
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderActions(
    BuildContext context,
    DocumentImmersiveCoverState state,
    EmojiIconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Wrap(
        spacing: 4,
        children: [
          FlowyButton(
            useIntrinsicWidth: true,
            leftIcon: const FlowySvg(FlowySvgs.add_cover_s),
            leftIconSize: const Size.square(18),
            text: FlowyText.small(
              (state.cover.isNone
                      ? LocaleKeys.document_plugins_cover_addCover
                      : LocaleKeys.document_plugins_cover_changeCover)
                  .tr(),
              color: Theme.of(context).hintColor,
            ),
            onTap: () => _showCoverSelector(context),
          ),
          FlowyButton(
            useIntrinsicWidth: true,
            leftIcon: const FlowySvg(FlowySvgs.add_icon_s),
            leftIconSize: const Size.square(18),
            text: FlowyText.small(
              (icon.isNotEmpty
                      ? LocaleKeys.document_plugins_cover_changeIcon
                      : LocaleKeys.document_plugins_cover_addIcon)
                  .tr(),
              color: Theme.of(context).hintColor,
            ),
            onTap: () => _showIconSelector(
              context,
              icon,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconAndTitle(
    BuildContext context,
    EmojiIconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          if (icon.isNotEmpty) ...[
            _buildIcon(context, icon),
            const HSpace(8.0),
          ],
          Expanded(child: _buildTitle(context)),
        ],
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    String? fontFamily = defaultFontFamily;
    final documentFontFamily =
        context.read<DocumentPageStyleBloc>().state.fontFamily;
    if (documentFontFamily != null && fontFamily != documentFontFamily) {
      fontFamily = getGoogleFontSafely(documentFontFamily).fontFamily;
    }

    if (widget.fixedTitle != null) {
      return FlowyText(
        widget.fixedTitle!,
        fontSize: 28.0,
        fontWeight: FontWeight.w700,
        fontFamily: fontFamily,
        overflow: TextOverflow.ellipsis,
      );
    }

    return AutoSizeTextField(
      controller: textEditingController,
      focusNode: focusNode,
      minFontSize: 18.0,
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: LocaleKeys.menuAppHeader_defaultNewPageName.tr(),
        contentPadding: EdgeInsets.zero,
      ),
      scrollController: scrollController,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.next,
      style: TextStyle(
        fontSize: 28.0,
        fontWeight: FontWeight.w700,
        fontFamily: fontFamily,
        overflow: TextOverflow.ellipsis,
      ),
      onChanged: (name) => Debounce.debounce(
        'rename',
        const Duration(milliseconds: 300),
        () => _rename(name),
      ),
      onSubmitted: (name) {
        // focus on the document
        _createNewLine();
        Debounce.debounce(
          'rename',
          const Duration(milliseconds: 300),
          () => _rename(name),
        );
      },
    );
  }

  Widget _buildIcon(BuildContext context, EmojiIconData icon) {
    return GestureDetector(
      child: ConstrainedBox(
        constraints: const BoxConstraints.tightFor(width: 34.0),
        child: EmojiIconWidget(
          emoji: icon,
          emojiSize: 26,
        ),
      ),
      onTap: () => _showIconSelector(context, icon),
    );
  }

  Future<void> _showIconSelector(
    BuildContext context,
    EmojiIconData icon,
  ) async {
    final viewBloc = context.read<ViewBloc>();
    await showMobileBottomSheet(
      context,
      showDragHandle: true,
      showDivider: false,
      showHeader: true,
      title: LocaleKeys.titleBar_pageIcon.tr(),
      backgroundColor: AFThemeExtension.of(context).background,
      enableDraggableScrollable: true,
      minChildSize: 0.6,
      initialChildSize: 0.61,
      scrollableWidgetBuilder: (bottomSheetContext, controller) {
        return Expanded(
          child: FlowyIconEmojiPicker(
            initialType: icon.type.toPickerTabType(),
            tabs: widget.tabs,
            documentId: widget.view.id,
            onSelectedEmoji: (r) {
              viewBloc.add(ViewEvent.updateIcon(r.data));
              if (!r.keepOpen) Navigator.pop(bottomSheetContext);
            },
          ),
        );
      },
      builder: (_) => const SizedBox.shrink(),
    );
  }

  Future<void> _showCoverSelector(BuildContext context) {
    return showMobileBottomSheet(
      context,
      showDragHandle: true,
      showDivider: false,
      showDoneButton: true,
      showHeader: true,
      title: LocaleKeys.pageStyle_coverImage.tr(),
      backgroundColor: AFThemeExtension.of(context).background,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<DocumentPageStyleBloc>()),
          BlocProvider.value(value: context.read<MobileViewPageBloc>()),
        ],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PageStyleCoverImage(documentId: widget.view.id),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, DocumentImmersiveCoverState state) {
    final cover = state.cover;
    final type = cover.type;
    final height = kDocumentCoverHeight;

    if (type == PageStyleCoverImageType.customImage ||
        type == PageStyleCoverImageType.unsplashImage) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: FlowyNetworkImage(
          url: cover.value,
          userProfilePB: widget.userProfilePB,
        ),
      );
    }

    if (type == PageStyleCoverImageType.builtInImage) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Image.asset(
          PageStyleCoverImageType.builtInImagePath(cover.value),
          fit: BoxFit.cover,
        ),
      );
    }

    if (type == PageStyleCoverImageType.pureColor) {
      return Container(
        height: height,
        width: double.infinity,
        color: cover.value.coverColor(context),
      );
    }

    if (type == PageStyleCoverImageType.gradientColor) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: FlowyGradientColor.fromId(cover.value).linear,
        ),
      );
    }

    if (type == PageStyleCoverImageType.localImage) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Image.file(
          File(cover.value),
          fit: BoxFit.cover,
        ),
      );
    }

    return SizedBox(
      height: 0,
      width: double.infinity,
    );
  }

  void _unfocus() {
    final selection = selectionNotifier?.value;
    if (selection != null) {
      focusNode.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    }
  }

  void _rename(String name) {
    scrollController.position.jumpTo(0);
    context.read<ViewBloc>().add(ViewEvent.rename(name));
  }

  Future<void> _createNewLine() async {
    focusNode.unfocus();

    final selection = textEditingController.selection;
    final text = textEditingController.text;
    // split the text into two lines based on the cursor position
    final parts = [
      text.substring(0, selection.baseOffset),
      text.substring(selection.baseOffset),
    ];
    textEditingController.text = parts[0];

    final editorState = context.read<DocumentBloc>().state.editorState;
    if (editorState == null) {
      Log.info('editorState is null when creating new line');
      return;
    }

    final transaction = editorState.transaction;
    transaction.insertNode([0], paragraphNode(text: parts[1]));
    await editorState.apply(transaction);

    // update selection instead of using afterSelection in transaction,
    //  because it will cause the cursor to jump
    await editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0])),
      // trigger the keyboard service.
      reason: SelectionUpdateReason.uiEvent,
    );
  }
}
