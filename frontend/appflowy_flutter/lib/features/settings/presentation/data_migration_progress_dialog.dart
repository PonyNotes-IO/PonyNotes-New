import 'dart:async';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:flutter/material.dart';

Future<void> migrateDataAndRestart(BuildContext context) async {
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  '正在迁移本地数据，请勿关闭软件…',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // Allow the progress UI to paint before shutting down the Rust backend.
  await WidgetsBinding.instance.endOfFrame;
  await runAppFlowy();

  final migrationError = ApplicationDataStorage.lastMigrationError;
  if (migrationError == null) {
    return;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final newContext = AppGlobals.rootNavKey.currentContext;
    if (newContext == null) {
      return;
    }
    showDialog<void>(
      context: newContext,
      builder: (context) => AlertDialog(
        title: const Text('存储路径迁移失败'),
        content: Text(
          '数据仍保留在原目录，软件已继续使用原路径。\n\n$migrationError',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  });
}
