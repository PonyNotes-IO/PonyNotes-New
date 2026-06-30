import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';

typedef LogoutRelaunchAction = Future<void> Function();

class LogoutRelauncher {
  LogoutRelauncher({
    required this.signOut,
    required this.relaunch,
  });

  final LogoutRelaunchAction signOut;
  final LogoutRelaunchAction relaunch;

  Future<void>? _inFlight;

  Future<void> logoutAndRelaunch() {
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }

    final request = _logoutAndRelaunch();
    _inFlight = request;
    return request.whenComplete(() {
      if (identical(_inFlight, request)) {
        _inFlight = null;
      }
    });
  }

  Future<void> _logoutAndRelaunch() async {
    await signOut();
    await relaunch();
  }
}

LogoutRelauncher? _appLogoutRelauncher;

LogoutRelauncher appLogoutRelauncher() {
  return _appLogoutRelauncher ??= LogoutRelauncher(
    signOut: () => getIt<AuthService>().signOut(),
    relaunch: runAppFlowy,
  );
}
