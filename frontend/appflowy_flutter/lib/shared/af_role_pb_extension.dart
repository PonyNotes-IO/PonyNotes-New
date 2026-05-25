import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';

extension AFRolePBExtension on AFRolePB {
  bool get isOwner => this == AFRolePB.Owner;

  bool get isMember => this == AFRolePB.Member;

  bool get canInvite => isOwner;

  bool get canDelete => isOwner;

  bool get canUpdate => isOwner;

  bool get canLeave => this != AFRolePB.Owner;

  String get description {
    switch (this) {
      case AFRolePB.Owner:
        return '工作空间所有者';
      case AFRolePB.Member:
        return '成员';
      case AFRolePB.Guest:
        return '受限成员';
    }
    throw UnimplementedError('Unknown role: $this');
  }
}
