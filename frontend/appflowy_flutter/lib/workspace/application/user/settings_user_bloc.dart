import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_user_bloc.freezed.dart';

class SettingsUserViewBloc extends Bloc<SettingsUserEvent, SettingsUserState> {
  SettingsUserViewBloc(this.userProfile)
      : _userListener = UserListener(userProfile: userProfile),
        _userService = UserBackendService(userId: userProfile.id),
        super(SettingsUserState.initial(userProfile)) {
    _dispatch();
  }

  final UserBackendService _userService;
  final UserListener _userListener;
  final UserProfilePB userProfile;

  @override
  Future<void> close() async {
    await _userListener.stop();
    return super.close();
  }

  void _dispatch() {
    on<SettingsUserEvent>(
      (event, emit) async {
        await event.when(
          initial: () async {
            await _reloadUserProfile();
            _userListener.start(onProfileUpdated: _profileUpdated);
          },
          didReceiveUserProfile: (UserProfilePB newUserProfile) {
            emit(state.copyWith(userProfile: newUserProfile));
          },
          updateUserName: (String name) async {
            final result = await _userService.updateUserProfile(name: name);
            if (result.isSuccess) {
              await _reloadUserProfile();
            } else {
              result.fold((_) {}, Log.error);
            }
          },
          updateUserIcon: (String iconUrl) async {
            final result =
                await _userService.updateUserProfile(iconUrl: iconUrl);
            if (result.isSuccess) {
              await _reloadUserProfile();
            } else {
              result.fold((_) {}, Log.error);
            }
          },
          updateUserEmail: (String email) async {
            final result = await _userService.updateUserProfile(email: email);
            if (result.isSuccess) {
              await _reloadUserProfile();
            } else {
              result.fold((_) {}, Log.error);
            }
          },
          updateUserPassword: (String oldPassword, String newPassword) {
            _userService
                .updateUserProfile(password: newPassword)
                .then((result) {
              result.fold(
                (l) => null,
                (err) => Log.error(err),
              );
            });
          },
          removeUserIcon: () async {
            // Empty Icon URL = No icon
            final result = await _userService.updateUserProfile(iconUrl: "");
            if (result.isSuccess) {
              await _reloadUserProfile();
            } else {
              result.fold((_) {}, Log.error);
            }
          },
        );
      },
    );
  }

  Future<void> _reloadUserProfile() async {
    // The profile service caches reads briefly. Invalidate it after a successful
    // write so the state cannot be rebuilt with the previous avatar URL.
    UserBackendService.clearCurrentUserProfileCache();
    final result = await UserBackendService.getCurrentUserProfile();
    if (isClosed) {
      return;
    }

    result.fold(
      (userProfile) => add(
        SettingsUserEvent.didReceiveUserProfile(userProfile),
      ),
      (err) => Log.error(err),
    );
  }

  void _profileUpdated(
    FlowyResult<UserProfilePB, FlowyError> userProfileOrFailed,
  ) =>
      userProfileOrFailed.fold(
        (newUserProfile) =>
            add(SettingsUserEvent.didReceiveUserProfile(newUserProfile)),
        (err) => Log.error(err),
      );
}

@freezed
class SettingsUserEvent with _$SettingsUserEvent {
  const factory SettingsUserEvent.initial() = _Initial;
  const factory SettingsUserEvent.updateUserName({
    required String name,
  }) = _UpdateUserName;
  const factory SettingsUserEvent.updateUserEmail({
    required String email,
  }) = _UpdateEmail;
  const factory SettingsUserEvent.updateUserIcon({
    required String iconUrl,
  }) = _UpdateUserIcon;
  const factory SettingsUserEvent.updateUserPassword({
    required String oldPassword,
    required String newPassword,
  }) = _UpdateUserPassword;
  const factory SettingsUserEvent.removeUserIcon() = _RemoveUserIcon;
  const factory SettingsUserEvent.didReceiveUserProfile(
    UserProfilePB newUserProfile,
  ) = _DidReceiveUserProfile;
}

@freezed
class SettingsUserState with _$SettingsUserState {
  const factory SettingsUserState({
    required UserProfilePB userProfile,
    required FlowyResult<void, String> successOrFailure,
  }) = _SettingsUserState;

  factory SettingsUserState.initial(UserProfilePB userProfile) =>
      SettingsUserState(
        userProfile: userProfile,
        successOrFailure: FlowyResult.success(null),
      );
}
