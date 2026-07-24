import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/rust_sdk.dart';
import 'package:appflowy/workspace/application/settings/prelude.dart';
import 'package:appflowy_backend/protobuf/flowy-error/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';

import '../models/user_data_location.dart';
import 'settings_repository.dart';

class RustSettingsRepositoryImpl implements SettingsRepository {
  const RustSettingsRepositoryImpl();

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
    await storage.setCustomPath(path);
    final configuredDirectory = await storage.getPath();

    return FlowyResult.success(
      UserDataLocation(
        path: configuredDirectory,
        isCustom: !configuredDirectory.contains(defaultDirectory),
      ),
    );
  }
}
