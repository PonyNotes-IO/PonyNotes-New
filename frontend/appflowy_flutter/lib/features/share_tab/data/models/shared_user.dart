import 'package:appflowy/features/share_tab/data/models/share_access_level.dart';
import 'package:appflowy/features/share_tab/data/models/share_role.dart';

typedef SharedUsers = List<SharedUser>;

/// Represents a user with a role on a shared page.
class SharedUser {
  SharedUser({
    required this.email,
    required this.name,
    required this.role,
    required this.accessLevel,
    this.avatarUrl,
    this.userId,
    this.uid,
    this.phone,
  });

  final String email;

  /// The name of the user.
  final String name;

  /// The role of the user.
  final ShareRole role;

  /// The access level of the user.
  final ShareAccessLevel accessLevel;

  /// The avatar URL of the user.
  ///
  /// if the avatar is not set, it will be the first letter of the name.
  final String? avatarUrl;

  /// The user ID (member_user_id / uuid) for collaboration API.
  final String? userId;

  /// The numeric user ID from the API (uid field).
  final String? uid;

  /// The phone number of the user.
  final String? phone;

  SharedUser copyWith({
    String? email,
    String? name,
    ShareRole? role,
    ShareAccessLevel? accessLevel,
    String? avatarUrl,
    String? userId,
    String? uid,
    String? phone,
  }) {
    return SharedUser(
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      accessLevel: accessLevel ?? this.accessLevel,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      userId: userId ?? this.userId,
      uid: uid ?? this.uid,
      phone: phone ?? this.phone,
    );
  }
}
