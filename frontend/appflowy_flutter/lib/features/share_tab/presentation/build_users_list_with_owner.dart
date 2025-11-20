import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:collection/collection.dart';

import '../data/models/share_access_level.dart';

/// 构建包含拥有者的完整用户列表，拥有者始终在最前面
List<SharedUser> buildUsersListWithOwner({
  required SharedUsers users,
  required UserProfilePB? currentUser,
}) {
  if (currentUser == null) {
    return users;
  }

  // 查找是否已有拥有者
  final owner = users.firstWhereOrNull(
    (user) => user.role == ShareRole.owner,
  );

  // 如果已有拥有者，将其放在最前面，其他用户放在后面
  if (owner != null) {
    final otherUsers =
        users.where((user) => user.role != ShareRole.owner).toList();
    return [owner, ...otherUsers];
  }

  // 如果没有拥有者，创建拥有者对象（使用当前用户信息）
  final ownerUser = SharedUser(
    email: currentUser.email,
    name: currentUser.name.isNotEmpty ? currentUser.name : currentUser.email,
    role: ShareRole.owner,
    accessLevel: ShareAccessLevel.fullAccess,
    avatarUrl: currentUser.iconUrl.isNotEmpty ? currentUser.iconUrl : null,
  );

  // 检查当前用户是否已在列表中
  final currentUserInList = users.firstWhereOrNull(
    (user) => user.email == currentUser.email,
  );

  if (currentUserInList != null) {
    // 如果当前用户已在列表中，将其替换为拥有者，并放在最前面
    final otherUsers =
        users.where((user) => user.email != currentUser.email).toList();
    return [ownerUser, ...otherUsers];
  } else {
    // 如果当前用户不在列表中，将拥有者放在最前面
    return [ownerUser, ...users];
  }
}


