use std::sync::Weak;

use strum_macros::Display;

use flowy_derive::{Flowy_Event, ProtoBuf_Enum};
use lib_dispatch::prelude::*;

use crate::event_handler::*;
use crate::manager::StorageManager;

pub fn init(storage_manager: Weak<StorageManager>) -> AFPlugin {
  AFPlugin::new()
    .name("Flowy-Storage")
    .state(storage_manager)
    .event(FileStorageEvent::RegisterStream, register_stream_handler)
    .event(FileStorageEvent::QueryFile, query_file_handler)
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Display, Hash, ProtoBuf_Enum, Flowy_Event)]
#[event_err = "FlowyError"]
pub enum FileStorageEvent {
  #[event(input = "RegisterStreamPB")]
  RegisterStream = 0,

  #[event(input = "QueryFilePB", output = "FileStatePB")]
  QueryFile = 1,
}

