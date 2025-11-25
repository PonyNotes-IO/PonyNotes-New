import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/shared/share/constants.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class SettingsPageSitesConstants {
  static const threeDotsButtonWidth = 26.0;
  static const alignPadding = 6.0;

  static final dateFormat = DateFormat('MMM d, yyyy');

  static final publishedViewHeaderTitles = [
    LocaleKeys.settings_sites_publishedPage_page.tr(),
    LocaleKeys.settings_sites_publishedPage_pathName.tr(),
    LocaleKeys.settings_sites_publishedPage_date.tr(),
  ];

  static final namespaceHeaderTitles = [
    LocaleKeys.settings_sites_namespaceHeader.tr(),
    LocaleKeys.settings_sites_homepageHeader.tr(),
  ];

  // the published view name is longer than the other two, so we give it more flex
  static final publishedViewItemFlexes = [1, 1, 1];
}

class SettingsPageSitesEvent {
  static Future<void> visitSite(
    BuildContext context,
    PublishInfoViewPB publishInfoView,
  ) async {
    // 获取当前工作区ID
    final workspaceId = await _getCurrentWorkspaceId(context);
    // visit the site
    final url = ShareConstants.buildPublishUrl(
      workspaceId: workspaceId,
      viewId: publishInfoView.info.viewId,
    );
    afLaunchUrlString(url);
  }

  static Future<void> copySiteLink(
    BuildContext context,
    PublishInfoViewPB publishInfoView,
  ) async {
    // 获取当前工作区ID
    final workspaceId = await _getCurrentWorkspaceId(context);
    final url = ShareConstants.buildPublishUrl(
      workspaceId: workspaceId,
      viewId: publishInfoView.info.viewId,
    );
    getIt<ClipboardService>().setData(ClipboardServiceData(plainText: url));
    showToastNotification(
      message: LocaleKeys.message_copy_success.tr(),
    );
  }

  static Future<String> _getCurrentWorkspaceId(BuildContext context) async {
    // 从服务获取当前工作区ID
    final result = await UserBackendService.getCurrentWorkspace();
    return result.fold(
      (workspace) => workspace.id,
      (_) => '',
    );
  }
}
