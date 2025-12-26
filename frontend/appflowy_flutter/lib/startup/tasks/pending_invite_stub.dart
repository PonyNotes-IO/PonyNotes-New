import 'package:appflowy_backend/log.dart';

/// Stub implementation for non-web platforms.
Future<void> processPendingInvite() async {
  Log.info('🔵 [PendingInvite] Non-web platform: skipping pending invite processing');
  return;
}


