import 'dart:convert';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';

extension UserProfilePBExtension on UserProfilePB {
  String? get authToken {
    // token 已经是 access_token 字符串，直接返回
    return token.isEmpty ? null : token;
  }
}
