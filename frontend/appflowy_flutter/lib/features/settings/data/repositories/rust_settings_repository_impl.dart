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
    final configuredDirectory = await getIt<ApplicationDataStorage>().getPath();

    return FlowyResult.success(
      UserDataLocation(
        path: configuredDirectory,
        isCustom: !configuredDirectory.contains(defaultDirectory),
      ),
    );
  }

  @override
  Future<FlowyResult<UserDataLocation, FlowyError>>
      resetUserDataLocation() async {
    final directory = await appFlowyApplicationDataDirectory();
    await getIt<ApplicationDataStorage>().setPath(directory.path);

    return FlowyResult.success(
      UserDataLocation(
        path: directory.path,
        isCustom: false,
      ),
    );
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
          isCustom: !configuredDirectory.contains(defaultDirectory),
        ),
      );
    } catch (error) {
      return FlowyResult.failure(
        FlowyError(msg: 'Unable to migrate the data directory: $error'),
      );
    }
  }
}
