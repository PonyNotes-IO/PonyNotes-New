use lib_dispatch::prelude::*;
use std::sync::Weak;
use strum_macros::Display;
use flowy_derive::{Flowy_Event, ProtoBuf_Enum};

use crate::event_handler::*;
use crate::manager::HandwritingSaberManager;

pub fn init(handwriting_saber_manager: Weak<HandwritingSaberManager>) -> AFPlugin {
  AFPlugin::new()
    .name(env!("CARGO_PKG_NAME"))
    .state(handwriting_saber_manager)
    .event(HandwritingSaberEvent::CreateHandwritingSaber, create_handwriting_saber_handler)
    .event(HandwritingSaberEvent::OpenHandwritingSaber, open_handwriting_saber_handler)
    .event(HandwritingSaberEvent::SaveHandwritingSaber, save_handwriting_saber_handler)
    .event(HandwritingSaberEvent::GetHandwritingSaberData, get_handwriting_saber_data_handler)
    .event(HandwritingSaberEvent::CloseHandwritingSaber, close_handwriting_saber_handler)
    .event(HandwritingSaberEvent::DeleteHandwritingSaber, delete_handwriting_saber_handler)
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Display, ProtoBuf_Enum, Flowy_Event)]
#[event_err = "FlowyError"]
pub enum HandwritingSaberEvent {
  #[event(input = "CreateHandwritingSaberPayloadPB")]
  CreateHandwritingSaber = 0,

  #[event(input = "ViewIdPB")]
  OpenHandwritingSaber = 1,

  #[event(input = "SaveHandwritingSaberPayloadPB", output = "SaveHandwritingSaberResponsePB")]
  SaveHandwritingSaber = 2,

  #[event(input = "ViewIdPB", output = "HandwritingSaberDataPB")]
  GetHandwritingSaberData = 3,

  #[event(input = "ViewIdPB")]
  CloseHandwritingSaber = 4,

  #[event(input = "ViewIdPB")]
  DeleteHandwritingSaber = 5,
}
