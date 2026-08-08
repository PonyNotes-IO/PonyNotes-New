import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// Notifier for global space changes (e.g. create / delete / update).
///
/// `MobileSpaceManagementPage` (and any other component that mutates spaces
/// via a private `SpaceBloc` instance) should call
/// [MobileSpaceChangeNotifier.notifySpacesChanged] after the mutation is
/// persisted to the backend, so the home screen's `SpaceBloc` (which is a
/// different instance) can re-dispatch `SpaceEvent.initial` to refresh its
/// `spaces` list.
///
/// Listeners are responsible for any UX workarounds (e.g. backend
/// `getPublicViews` cache lag that briefly omits the just-created space);
/// the notifier itself is intentionally a thin pub-sub.
class MobileSpaceChangeNotifier extends ChangeNotifier {
  MobileSpaceChangeNotifier._();
  static final MobileSpaceChangeNotifier instance =
      MobileSpaceChangeNotifier._();

  /// Bumps a counter and notifies listeners. Listeners should trigger a
  /// refresh on their `SpaceBloc` (e.g. re-add `SpaceEvent.initial`).
  void notifySpacesChanged() {
    Log.info('[SpaceCreate] MobileSpaceChangeNotifier.notifySpacesChanged()');
    notifyListeners();
  }
}
