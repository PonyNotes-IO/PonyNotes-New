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

  /// The user ID (member_user_id) for collaboration API.
  final String? userId;

  /// The phone number of the user.
  final String? phone;

  SharedUser copyWith({
    String? email,
    String? name,
    ShareRole? role,
    ShareAccessLevel? accessLevel,
    String? avatarUrl,
    String? userId,
    String? phone,
  }) {
    return SharedUser(
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      accessLevel: accessLevel ?? this.accessLevel,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      userId: userId ?? this.userId,
      phone: phone ?? this.phone,
    );
  }
}
