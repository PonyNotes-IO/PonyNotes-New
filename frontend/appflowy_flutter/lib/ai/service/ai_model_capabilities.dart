import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';

/// AI 模型能力判断辅助函数
///
/// 由于 protobuf 的 AIModelPB 没有 supports_images 字段，
/// 我们基于模型名称（id/name）来识别多模态模型。
/// 这与 `AIModel.fromJson` 中 isKnownMultimodal 的判断保持一致。
class AIModelCapabilities {
  /// 判断模型是否支持图片/多模态输入
  ///
  /// 由于 protobuf 的 AIModelPB 没有 supports_images 字段，
  /// 我们基于模型名称（name）来识别多模态模型。
  /// 只有明确在映射表中的模型才被识别为多模态。
  static bool supportsImages(String? modelName) {
    if (modelName == null || modelName.isEmpty) return false;
    return _chineseNameToMultimodal[modelName] ?? false;
  }

  /// 模型显示名 → 是否支持图片的映射表
  /// 仅精确匹配，非模糊匹配（避免 'seek' 匹配 'vl' 等误判）
  static const Map<String, bool> _chineseNameToMultimodal = {
    '通义千问': true,
    '豆包': true,
    'DeepSeek': false,
  };

  /// 判断 AIModelPB 是否支持图片
  static bool supportsAIModelPB(AIModelPB? model) {
    if (model == null) return false;
    return supportsImages(model.name);
  }
}
