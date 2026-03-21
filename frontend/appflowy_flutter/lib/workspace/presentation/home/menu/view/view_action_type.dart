import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum ViewMoreActionType {
  delete,
  favorite,
  unFavorite,
  duplicate,
  duplicateToMySpace, // 复制到我的空间
  copyLink, // not supported yet.
  rename,
  moveTo,
  openInNewTab,
  changeIcon,
  divider,
  lastModified,
  created,
  lockPage,
  leaveSharedPage,
  leaveWorkspace, // 离开工作区
  manageSpace, // 管理空间
  export; // 导出

  static const disableInLockedView = [
    delete,
    rename,
    moveTo,
    changeIcon,
  ];
}

extension ViewMoreActionTypeExtension on ViewMoreActionType {
  String get name {
    switch (this) {
      case ViewMoreActionType.delete:
        return LocaleKeys.disclosureAction_delete.tr();
      case ViewMoreActionType.favorite:
        return LocaleKeys.disclosureAction_favorite.tr();
      case ViewMoreActionType.unFavorite:
        return LocaleKeys.disclosureAction_unfavorite.tr();
      case ViewMoreActionType.duplicate:
        return LocaleKeys.disclosureAction_duplicate.tr();
      case ViewMoreActionType.duplicateToMySpace:
        return '复制到我的空间';
      case ViewMoreActionType.copyLink:
        return LocaleKeys.disclosureAction_copyLink.tr();
      case ViewMoreActionType.rename:
        return LocaleKeys.disclosureAction_rename.tr();
      case ViewMoreActionType.moveTo:
        return LocaleKeys.disclosureAction_moveTo.tr();
      case ViewMoreActionType.openInNewTab:
        return LocaleKeys.disclosureAction_openNewTab.tr();
      case ViewMoreActionType.changeIcon:
        return LocaleKeys.disclosureAction_changeIcon.tr();
      case ViewMoreActionType.lockPage:
        return LocaleKeys.disclosureAction_lockPage.tr();
      case ViewMoreActionType.leaveSharedPage:
        return 'Leave';
      case ViewMoreActionType.leaveWorkspace:
        return LocaleKeys.workspace_leaveCurrentWorkspace.tr();
      case ViewMoreActionType.manageSpace:
        return LocaleKeys.space_manage.tr();
      case ViewMoreActionType.export:
        return '导出';
      case ViewMoreActionType.divider:
      case ViewMoreActionType.lastModified:
      case ViewMoreActionType.created:
        return '';
    }
  }

  FlowySvgData get leftIconSvg {
    switch (this) {
      case ViewMoreActionType.delete:
        return FlowySvgs.trash_s;
      case ViewMoreActionType.favorite:
        return FlowySvgs.favorite_s;
      case ViewMoreActionType.unFavorite:
        return FlowySvgs.unfavorite_s;
      case ViewMoreActionType.duplicate:
        return FlowySvgs.duplicate_s;
      case ViewMoreActionType.duplicateToMySpace:
        return FlowySvgs.duplicate_s;
      case ViewMoreActionType.rename:
        return FlowySvgs.view_item_rename_s;
      case ViewMoreActionType.moveTo:
        return FlowySvgs.move_to_s;
      case ViewMoreActionType.openInNewTab:
        return FlowySvgs.view_item_open_in_new_tab_s;
      case ViewMoreActionType.changeIcon:
        return FlowySvgs.change_icon_s;
      case ViewMoreActionType.lockPage:
        return FlowySvgs.lock_page_s;
      case ViewMoreActionType.leaveSharedPage:
        return FlowySvgs.leave_workspace_s;
      case ViewMoreActionType.leaveWorkspace:
        return FlowySvgs.leave_workspace_s;
      case ViewMoreActionType.manageSpace:
        return FlowySvgs.settings_s; // 使用设置图标，或者可以添加专门的图标
      case ViewMoreActionType.export:
        return FlowySvgs.download_s; // 使用下载图标作为导出图标
      case ViewMoreActionType.divider:
      case ViewMoreActionType.lastModified:
      case ViewMoreActionType.copyLink:
      case ViewMoreActionType.created:
        throw UnsupportedError('No left icon for $this');
    }
  }

  Widget get rightIcon {
    switch (this) {
      case ViewMoreActionType.changeIcon:
      case ViewMoreActionType.moveTo:
      case ViewMoreActionType.favorite:
      case ViewMoreActionType.unFavorite:
      case ViewMoreActionType.duplicate:
      case ViewMoreActionType.duplicateToMySpace:
      case ViewMoreActionType.copyLink:
      case ViewMoreActionType.rename:
      case ViewMoreActionType.openInNewTab:
      case ViewMoreActionType.divider:
      case ViewMoreActionType.delete:
      case ViewMoreActionType.lastModified:
      case ViewMoreActionType.created:
      case ViewMoreActionType.lockPage:
      case ViewMoreActionType.leaveSharedPage:
      case ViewMoreActionType.leaveWorkspace:
      case ViewMoreActionType.manageSpace:
      case ViewMoreActionType.export:
        return const SizedBox.shrink();
    }
  }
}
