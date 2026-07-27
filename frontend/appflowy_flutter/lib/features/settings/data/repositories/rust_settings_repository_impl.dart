import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/rust_sdk.dart';
import 'package:appflowy/user/application/user_settings_service.dart';
import 'package:appflowy/workspace/application/settings/prelude.dart';
import 'package:appflowy_backend/protobuf/flowy-error/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:path/path.dart' as p;

import '../models/user_data_location.dart';
import 'settings_repository.dart';

class RustSettingsRepositoryImpl implements SettingsRepository {
  const RustSettingsRepositoryImpl();

  final _userBackendService = const UserSettingsBackendService();

  @override
  Future<FlowyResult<UserDataLocation, FlowyError>>
      getUserDataLocation() async {
    final defaultDirectory = (await appFlowyApplicationDataDirectory()).path;
    final storage = getIt<ApplicationDataStorage>();
    final settings = await _userBackendService.getUserSetting().toNullable();
    final configuredDirectory = settings == null
        ? await storage.getPath()
        : await storage.resolveActiveRoot(p.dirname(settings.userFolder));

    return FlowyResult.success(
      UserDataLocation(
        path: configuredDirectory,
        isCustom: !p.equals(configuredDirectory, defaultDirectory),
      ),
    );
  }

  @override
  Future<FlowyResult<UserDataLocation, FlowyError>>
      resetUserDataLocation() async {
    final directory = await appFlowyApplicationDataDirectory();
    final storage = getIt<ApplicationDataStorage>();
    final settings = await _userBackendService.getUserSetting().toNullable();
    if (settings == null) {
      return FlowyResult.failure(
        FlowyError(msg: 'Unable to read the current data directory'),
      );
    }

    try {
      final configuredDirectory = await storage.schedulePathMigration(
        destinationRoot: directory.path,
        activeDataPath: p.dirname(settings.userFolder),
      );
      return FlowyResult.success(
        UserDataLocation(
          path: configuredDirectory,
          isCustom: false,
        ),
      );
    } catch (error) {
      return FlowyResult.failure(
        FlowyError(msg: 'Unable to migrate the data directory: $error'),
      );
    }
  }

  @override
  Future<FlowyResult<UserDataLocation, FlowyError>> setCustomLocation(
    String path,
  ) async {
    final defaultDirectory = (await appFlowyApplicationDataDirectory()).path;
    final storage = getIt<ApplicationDataStorage>();
    final settings = await _userBackendService.getUserSetting().toNullable();
    if (settings == null) {
      return FlowyResult.failure(
        FlowyError(msg: 'Unable to read the current data directory'),
      );
    }
    try {
      final configuredDirectory = await storage.scheduleCustomPathMigration(
        path: path,
        // userFolder points to <storage root>/<user id>. Migrate the storage
        // root so account metadata and every local user are carried over too.
        activeDataPath: p.dirname(settings.userFolder),
      );

      return FlowyResult.success(
        UserDataLocation(
          path: configuredDirectory,
          isCustom: !p.equals(configuredDirectory, defaultDirectory),
        ),
      );
    } catch (error) {
      return FlowyResult.failure(
        FlowyError(msg: 'Unable to migrate the data directory: $error'),
      );
    }
  }
}
