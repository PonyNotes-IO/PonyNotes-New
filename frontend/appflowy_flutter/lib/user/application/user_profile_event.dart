import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:event_bus/event_bus.dart';

/// 全局用户配置事件总线
/// 用于在用户配置更新时通知所有需要更新的组件
EventBus userProfileEventBus = EventBus();

/// 用户配置更新事件
class UserProfileUpdatedEvent {
  UserProfileUpdatedEvent(this.userProfile);

  final UserProfilePB userProfile;
}
