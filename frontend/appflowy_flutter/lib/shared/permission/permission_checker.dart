// Check if the user has the required permission to access the device's
//  - camera
//  - storage
//  - ...
import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/widgets/show_flowy_mobile_confirm_dialog.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_platform/universal_platform.dart';

class PermissionChecker {
  static Future<bool> checkPhotoPermission(BuildContext context) async {
    // check the permission first
    final status = await Permission.photos.status;
    // if the permission is permanently denied, we should open the app settings
    if (status.isPermanentlyDenied && context.mounted) {
      unawaited(
        showFlowyMobileConfirmDialog(
          context,
          title: FlowyText.semibold(
            LocaleKeys.pageStyle_photoPermissionTitle.tr(),
            maxLines: 3,
            textAlign: TextAlign.center,
          ),
          content: FlowyText(
            LocaleKeys.pageStyle_photoPermissionDescription.tr(),
            maxLines: 5,
            textAlign: TextAlign.center,
            fontSize: 12.0,
          ),
          actionAlignment: ConfirmDialogActionAlignment.vertical,
          actionButtonTitle: LocaleKeys.pageStyle_openSettings.tr(),
          actionButtonColor: Colors.blue,
          cancelButtonTitle: LocaleKeys.pageStyle_doNotAllow.tr(),
          cancelButtonColor: Colors.blue,
          onActionButtonPressed: () {
            openAppSettings();
          },
        ),
      );

      return false;
    } else if (status.isDenied) {
      // https://github.com/Baseflow/flutter-permission-handler/issues/1262#issuecomment-2006340937
      Permission permission = Permission.photos;
      if (UniversalPlatform.isAndroid &&
          ApplicationInfo.androidSDKVersion <= 32) {
        permission = Permission.storage;
      }
      // if the permission is denied, we should request the permission
      final newStatus = await permission.request();
      if (newStatus.isDenied) {
        return false;
      }
    }

    return true;
  }

  static Future<bool> checkCameraPermission(BuildContext context) async {
    // check the permission first
    final status = await Permission.camera.status;
    // if the permission is permanently denied, we should open the app settings
    if (status.isPermanentlyDenied && context.mounted) {
      unawaited(
        showFlowyMobileConfirmDialog(
          context,
          title: FlowyText.semibold(
            LocaleKeys.pageStyle_cameraPermissionTitle.tr(),
            maxLines: 3,
            textAlign: TextAlign.center,
          ),
          content: FlowyText(
            LocaleKeys.pageStyle_cameraPermissionDescription.tr(),
            maxLines: 5,
            textAlign: TextAlign.center,
            fontSize: 12.0,
          ),
          actionAlignment: ConfirmDialogActionAlignment.vertical,
          actionButtonTitle: LocaleKeys.pageStyle_openSettings.tr(),
          actionButtonColor: Colors.blue,
          cancelButtonTitle: LocaleKeys.pageStyle_doNotAllow.tr(),
          cancelButtonColor: Colors.blue,
          onActionButtonPressed: openAppSettings,
        ),
      );

      return false;
    } else if (status.isDenied) {
      final newStatus = await Permission.camera.request();
      if (newStatus.isDenied) {
        return false;
      }
    }

    return true;
  }

  static Future<bool> checkCalendarPermission(BuildContext context) async {
    try {
      // 检查是否在支持的平台上
      if (!UniversalPlatform.isAndroid && !UniversalPlatform.isIOS) {
        print('日历权限检查仅在Android和iOS平台上支持');
        return false;
      }

      // check the permission first
      final status = await Permission.calendar.status;
      // if the permission is permanently denied, we should open the app settings
      if (status.isPermanentlyDenied && context.mounted) {
        unawaited(
          showFlowyMobileConfirmDialog(
            context,
            title: FlowyText.semibold(
              '日历权限',
              maxLines: 3,
              textAlign: TextAlign.center,
            ),
            content: FlowyText(
              '需要访问系统日历权限来同步您的日程安排。请在设置中允许访问日历。',
              maxLines: 5,
              textAlign: TextAlign.center,
              fontSize: 12.0,
            ),
            actionAlignment: ConfirmDialogActionAlignment.vertical,
            actionButtonTitle: '打开设置',
            actionButtonColor: Colors.blue,
            cancelButtonTitle: '不允许',
            cancelButtonColor: Colors.blue,
            onActionButtonPressed: openAppSettings,
          ),
        );

        return false;
      } else if (status.isDenied) {
        final newStatus = await Permission.calendar.request();
        if (newStatus.isDenied) {
          return false;
        }
      }

      return true;
    } catch (e) {
      print('检查日历权限时出错: $e');
      // 如果是插件缺失错误，返回false
      if (e.toString().contains('MissingPluginException')) {
        return false;
      }
      // 其他错误也返回false
      return false;
    }
  }
}
