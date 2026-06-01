import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bottom_sheet/bottom_sheet.dart';
import '../bottom_sheet/bottom_sheet_view_item.dart';
import '../bottom_sheet/bottom_sheet_view_item_body.dart';
import 'mobile_view_item_add_button.dart';

class MobileViewItemMoreSheet extends StatelessWidget {
  const MobileViewItemMoreSheet({
    super.key,
    required this.view,
    required this.spaceType,
    required this.favoriteBloc,
  });

  final ViewPB view;
  final FolderSpaceType spaceType;
  final FavoriteBloc favoriteBloc;

  @override
  Widget build(BuildContext context) {
    return MobileViewItemBottomSheet(
      view: view,
      actions: _buildActions(view),
      favoriteBloc: favoriteBloc,
    );
  }

  List<MobileViewItemBottomSheetBodyAction> _buildActions(ViewPB view) {
    final isFavorite = view.isFavorite;
    return [
      isFavorite
          ? MobileViewItemBottomSheetBodyAction.removeFromFavorites
          : MobileViewItemBottomSheetBodyAction.addToFavorites,
      MobileViewItemBottomSheetBodyAction.divider,
      MobileViewItemBottomSheetBodyAction.rename,
      if (view.layout != ViewLayoutPB.Chat)
        MobileViewItemBottomSheetBodyAction.duplicate,
      MobileViewItemBottomSheetBodyAction.divider,
      MobileViewItemBottomSheetBodyAction.delete,
    ];
  }
}

