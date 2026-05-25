use lib_dispatch::prelude::*;
use std::sync::Weak;
use strum_macros::Display;
use flowy_derive::{Flowy_Event, ProtoBuf_Enum};

use crate::event_handler::*;
use crate::manager::WhiteboardManager;

pub fn init(whiteboard_manager: Weak<WhiteboardManager>) -> AFPlugin {
  AFPlugin::new()
    .name(env!("CARGO_PKG_NAME"))
    .state(whiteboard_manager)
    .event(WhiteboardEvent::CreateWhiteboard, create_whiteboard_handler)
    .event(WhiteboardEvent::OpenWhiteboard, open_whiteboard_handler)
    .event(WhiteboardEvent::UpdateWhiteboard, update_whiteboard_handler)
    .event(WhiteboardEvent::GetWhiteboardData, get_whiteboard_data_handler)
    .event(WhiteboardEvent::CloseWhiteboard, close_whiteboard_handler)
    .event(WhiteboardEvent::DeleteWhiteboard, delete_whiteboard_handler)
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Display, ProtoBuf_Enum, Flowy_Event)]
#[event_err = "FlowyError"]
pub enum WhiteboardEvent {
  #[event(input = "CreateWhiteboardPayloadPB")]
  CreateWhiteboard = 0,
  
  #[event(input = "ViewIdPB")]
  OpenWhiteboard = 1,
  
  #[event(input = "UpdateWhiteboardPayloadPB")]
  UpdateWhiteboard = 2,
  
  #[event(input = "ViewIdPB", output = "WhiteboardDataPB")]
  GetWhiteboardData = 3,
  
  #[event(input = "ViewIdPB")]
  CloseWhiteboard = 4,
  
  #[event(input = "ViewIdPB")]
  DeleteWhiteboard = 5,
}
