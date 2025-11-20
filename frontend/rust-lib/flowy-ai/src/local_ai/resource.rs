/// Represents resources that are pending or missing for local AI
#[derive(Debug, Clone)]
pub enum PendingResource {
  PluginExecutableNotReady,
  OllamaServerNotReady,
  MissingModel(String),
}

