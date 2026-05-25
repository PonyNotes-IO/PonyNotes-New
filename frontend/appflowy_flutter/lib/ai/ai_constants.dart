/// 全局 AI 模型源 key，与 Rust 端的 `GLOBAL_ACTIVE_MODEL_KEY` 对应。
/// 该值用于访问「工作区级」模型配置，当具体会话还没有独立配置时，
/// 可以通过该 key 获取默认的模型列表及选中状态。
const String kGlobalAIModelSource = 'global_active_model';


