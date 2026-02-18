import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';

class ShareTabState {
  factory ShareTabState.initial() => const ShareTabState();

  const ShareTabState({
    this.currentUser,
    this.users = const [],
    this.availableUsers = const [],
    this.isLoading = false,
    this.errorMessage = '',
    this.shareLink = '',
    this.generalAccessRole,
    this.linkCopied = false,
    this.sectionType = SharedSectionType.private,
    this.initialResult,
    this.shareResult,
    this.removeResult,
    this.updateAccessLevelResult,
    this.turnIntoMemberResult,
    this.addCollaboratorResult,
    this.hasClickedUpgradeToPro = false,
    this.selectedPermissionId = 1, // 默认只读权限
  });

  final UserProfilePB? currentUser;
  final SharedUsers users;
  final SharedUsers availableUsers;
  final bool isLoading;
  final String errorMessage;
  final String shareLink;
  final ShareAccessLevel? generalAccessRole;
  final bool linkCopied;
  final SharedSectionType sectionType;
  final FlowyResult<void, FlowyError>? initialResult;
  final FlowyResult<void, FlowyError>? shareResult;
  final FlowyResult<void, FlowyError>? removeResult;
  final FlowyResult<void, FlowyError>? updateAccessLevelResult;
  final FlowyResult<void, FlowyError>? turnIntoMemberResult;
  final FlowyResult<void, FlowyError>? addCollaboratorResult;
  final bool hasClickedUpgradeToPro;
  final int selectedPermissionId; // 分享链接的权限：1=查看，2=评论，3=编辑，4=全部权限

  ShareTabState copyWith({
    UserProfilePB? currentUser,
    SharedUsers? users,
    SharedUsers? availableUsers,
    bool? isLoading,
    String? errorMessage,
    String? shareLink,
    ShareAccessLevel? generalAccessRole,
    bool? linkCopied,
    SharedSectionType? sectionType,
    FlowyResult<void, FlowyError>? initialResult,
    FlowyResult<void, FlowyError>? shareResult,
    FlowyResult<void, FlowyError>? removeResult,
    FlowyResult<void, FlowyError>? updateAccessLevelResult,
    FlowyResult<void, FlowyError>? turnIntoMemberResult,
    FlowyResult<void, FlowyError>? addCollaboratorResult,
    bool? hasClickedUpgradeToPro,
  }) {
    return ShareTabState(
      currentUser: currentUser ?? this.currentUser,
      users: users ?? this.users,
      availableUsers: availableUsers ?? this.availableUsers,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      shareLink: shareLink ?? this.shareLink,
      generalAccessRole: generalAccessRole ?? this.generalAccessRole,
      linkCopied: linkCopied ?? this.linkCopied,
      sectionType: sectionType ?? this.sectionType,
      initialResult: initialResult,
      shareResult: shareResult,
      removeResult: removeResult,
      updateAccessLevelResult: updateAccessLevelResult,
      turnIntoMemberResult: turnIntoMemberResult,
      addCollaboratorResult: addCollaboratorResult,
      hasClickedUpgradeToPro:
          hasClickedUpgradeToPro ?? this.hasClickedUpgradeToPro,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShareTabState &&
        other.currentUser == currentUser &&
        other.users == users &&
        other.availableUsers == availableUsers &&
        other.isLoading == isLoading &&
        other.errorMessage == errorMessage &&
        other.shareLink == shareLink &&
        other.generalAccessRole == generalAccessRole &&
        other.linkCopied == linkCopied &&
        other.sectionType == sectionType &&
        other.initialResult == initialResult &&
        other.shareResult == shareResult &&
        other.removeResult == removeResult &&
        other.updateAccessLevelResult == updateAccessLevelResult &&
        other.turnIntoMemberResult == turnIntoMemberResult &&
        other.addCollaboratorResult == addCollaboratorResult &&
        other.hasClickedUpgradeToPro == hasClickedUpgradeToPro;
  }

  @override
  int get hashCode {
    return Object.hash(
      currentUser,
      users,
      availableUsers,
      isLoading,
      errorMessage,
      shareLink,
      generalAccessRole,
      linkCopied,
      sectionType,
      initialResult,
      shareResult,
      removeResult,
      updateAccessLevelResult,
      turnIntoMemberResult,
      addCollaboratorResult,
      hasClickedUpgradeToPro,
    );
  }

  @override
  String toString() {
    return 'ShareTabState(currentUser: $currentUser, users: $users, availableUsers: $availableUsers, isLoading: $isLoading, errorMessage: $errorMessage, shareLink: $shareLink, generalAccessRole: $generalAccessRole, shareSectionType: $SharedSectionType, linkCopied: $linkCopied, initialResult: $initialResult, shareResult: $shareResult, removeResult: $removeResult, updateAccessLevelResult: $updateAccessLevelResult, turnIntoMemberResult: $turnIntoMemberResult, addCollaboratorResult: $addCollaboratorResult, hasClickedUpgradeToPro: $hasClickedUpgradeToPro)';
  }
}
