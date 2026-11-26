use flowy_derive::ProtoBuf;

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct RegisterStreamPB {
  #[pb(index = 1)]
  pub port: i64,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct QueryFilePB {
  #[pb(index = 1)]
  pub url: String,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct FileStatePB {
  #[pb(index = 1)]
  pub file_id: String,

  #[pb(index = 2)]
  pub is_finish: bool,

  #[pb(index = 3)]
  pub error_code: i32,

  #[pb(index = 4)]
  pub error_message: String,
}
