use flowy_derive::ProtoBuf_Enum;
use flowy_notification::NotificationBuilder;

const HANDWRITING_SABER_OBSERVABLE_SOURCE: &str = "HandwritingSaber";

#[derive(ProtoBuf_Enum, Debug, Default)]
pub enum HandwritingSaberNotification {
  #[default]
  Unknown = 0,

  /// 远端（其他设备 / 服务端）的更新已应用到本地 Collab。
  /// 客户端收到后需要重新读取数据，否则画布会停留在旧内容上，
  /// 并在下一次保存时把远端内容整篇覆盖掉。
  DidReceiveUpdate = 1,
}

impl std::convert::From<HandwritingSaberNotification> for i32 {
  fn from(notification: HandwritingSaberNotification) -> Self {
    notification as i32
  }
}

impl std::convert::From<i32> for HandwritingSaberNotification {
  fn from(notification: i32) -> Self {
    match notification {
      1 => HandwritingSaberNotification::DidReceiveUpdate,
      _ => HandwritingSaberNotification::Unknown,
    }
  }
}

#[tracing::instrument(level = "trace")]
pub(crate) fn handwriting_saber_notification_builder(
  id: &str,
  ty: HandwritingSaberNotification,
) -> NotificationBuilder {
  NotificationBuilder::new(id, ty, HANDWRITING_SABER_OBSERVABLE_SOURCE)
}
