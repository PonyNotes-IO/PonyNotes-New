use flowy_notification::NotificationBuilder;

const WHITEBOARD_OBSERVABLE_SOURCE: &str = "Whiteboard";

#[derive(Debug, Default, Clone)]
pub enum WhiteboardNotification {
  #[default]
  Unknown = 0,

  /// 当白板数据（Map）发生变更时发送
  /// Payload: WhiteboardDataPB
  DidReceiveUpdate = 1,
}

impl std::convert::From<WhiteboardNotification> for i32 {
  fn from(notification: WhiteboardNotification) -> Self {
    notification as i32
  }
}

impl std::convert::From<i32> for WhiteboardNotification {
  fn from(notification: i32) -> Self {
    match notification {
      1 => WhiteboardNotification::DidReceiveUpdate,
      _ => WhiteboardNotification::Unknown,
    }
  }
}

#[tracing::instrument(level = "trace")]
pub(crate) fn whiteboard_notification_builder(
  view_id: String,
  ty: WhiteboardNotification,
) -> NotificationBuilder {
  NotificationBuilder::new(&view_id, ty, WHITEBOARD_OBSERVABLE_SOURCE)
}
