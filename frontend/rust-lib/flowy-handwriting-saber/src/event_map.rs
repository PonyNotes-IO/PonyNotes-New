use lib_dispatch::prelude::*;
use std::sync::Weak;
use strum_macros::Display;

use crate::event_handler::*;
use crate::manager::HandwritingSaberManager;

pub fn init(handwriting_saber_manager: Weak<HandwritingSaberManager>) -> AFPlugin {
  AFPlugin::new()
    .name(env!("CARGO_PKG_NAME"))
    .state(handwriting_saber_manager)
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Display)]
pub enum HandwritingSaberEvent {
  CreateHandwritingSaber = 0,
  OpenHandwritingSaber = 1,
  SaveHandwritingSaber = 2,
  GetHandwritingSaberData = 3,
  CloseHandwritingSaber = 4,
  DeleteHandwritingSaber = 5,
}

