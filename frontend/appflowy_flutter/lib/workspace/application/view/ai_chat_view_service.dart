import 'dart:convert';
import 'dart:io';
import 'package:appflowy/plugins/standalone_ai_chat/models/chat_image.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path_provider/path_provider.dart';

/// AI聊天视图创建服务
class AIChatViewService {
  /// 创建新的AI Chat视图并打开
  /// 
  /// [parentViewId] 父视图ID（通常是workspace ID）
  /// [initialMessage] 初始消息（可选）
  /// [selectedModelId] 选定的模型ID（可选）
  /// [enableDeepThinking] 是否启用深度思考（可选）
  /// [enableWebSearch] 是否启用全网搜索（可选）
  /// [initialImages] 初始图片列表（可选）
  static Future<ViewPB?> createAndOpenAIChat({
    required String parentViewId,
    String? initialMessage,
    String? selectedModelId,
    bool enableDeepThinking = false,
    bool enableWebSearch = false,
    List<ChatImage>? initialImages,
  }) async {
    try {
      // 1. 生成Chat名称
      final chatName = _generateChatName(initialMessage);
      
      Log.info('🔄 开始创建AI Chat视图...');
      Log.info('   - 父视图ID: $parentViewId');
      Log.info('   - 名称: $chatName');
      Log.info('   - 模型: $selectedModelId');
      Log.info('   - 初始消息: ${initialMessage?.substring(0, initialMessage.length > 50 ? 50 : initialMessage.length)}...');
      Log.info('   - 图片数量: ${initialImages?.length ?? 0}');

      // 2. 处理图片数据
      List<String>? imagePaths;
      if (initialImages != null && initialImages.isNotEmpty) {
        imagePaths = await _prepareImagePaths(initialImages);
        Log.info('✅ 准备了 ${imagePaths.length} 张图片路径');
      }

      // 3. 构建额外参数（存储为JSON）
      final extraData = <String, dynamic>{};
      if (selectedModelId != null && selectedModelId.isNotEmpty) {
        extraData['preferred_model'] = selectedModelId;
      }
      if (initialMessage != null && initialMessage.isNotEmpty) {
        extraData['initial_message'] = initialMessage;
      }
      if (enableDeepThinking) {
        extraData['enable_deep_thinking'] = 'true';
      }
      if (enableWebSearch) {
        extraData['enable_web_search'] = 'true';
      }
      if (imagePaths != null && imagePaths.isNotEmpty) {
        extraData['initial_images'] = imagePaths;
        Log.info('✅ 将 ${imagePaths.length} 张图片路径添加到extra');
      }

      // 将额外数据转换为JSON字符串
      String? extraJson;
      if (extraData.isNotEmpty) {
        extraJson = json.encode(extraData);
        Log.info('📦 额外参数JSON: $extraJson');
      }

      // 4. 创建Chat类型的View
      // 注意：AppFlowy的createView的ext参数可能不支持直接存储到extra字段
      // 我们可能需要在创建后再更新extra字段
      // AI会话是用户的个人隐私数据，应该创建在私有空间
      final result = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Chat,
        parentViewId: parentViewId,
        name: chatName,
        openAfterCreate: true,
        section: ViewSectionPB.Private,  // 指定为私有空间
      );

      return result.fold(
        (view) async {
          Log.info('✅ 成功创建AI Chat视图');
          Log.info('   - 视图ID: ${view.id}');
          Log.info('   - 视图名称: ${view.name}');
          
          // 5. 如果有额外数据，更新view的extra字段
          if (extraJson != null) {
            Log.info('🔄 更新视图的extra字段...');
            await ViewBackendService.updateView(
              viewId: view.id,
              extra: extraJson,
            );
            Log.info('✅ extra字段更新成功');
          }
          
          // 6. 创建AIChatPagePlugin并打开
          try {
            final plugin = view.plugin();
            Log.info('✅ 创建插件成功，正在打开标签页...');
            
            getIt<TabsBloc>().add(
              TabsEvent.openPlugin(
                plugin: plugin,
                view: view,
              ),
            );
            
            Log.info('✅ AI Chat标签页已打开');
          } catch (pluginError) {
            Log.error('❌ 创建或打开插件失败: $pluginError');
          }
          
          return view;
        },
        (error) {
          Log.error('❌ 创建AI Chat视图失败: ${error.msg}');
          Log.error('   - 错误代码: ${error.code}');
          return null;
        },
      );
    } catch (e, stackTrace) {
      Log.error('❌ 创建AI Chat视图异常: $e', e, stackTrace);
      return null;
    }
  }

  /// 获取当前workspace ID
  static Future<String?> getCurrentWorkspaceId() async {
    try {
      Log.info('🔍 正在获取当前workspace ID...');
      
      final result = await FolderEventReadCurrentWorkspace().send();
      return result.fold(
        (workspace) {
          Log.info('✅ 获取workspace ID成功: ${workspace.id}');
          return workspace.id;
        },
        (error) {
          Log.error('❌ 获取workspace ID失败: ${error.msg}');
          return null;
        },
      );
    } catch (e) {
      Log.error('❌ 获取workspace ID异常: $e');
      return null;
    }
  }

  /// 生成Chat名称
  static String _generateChatName(String? initialMessage) {
    if (initialMessage == null || initialMessage.isEmpty) {
      return 'AI 对话';
    }
    
    // 移除多余的空白字符
    final cleanMessage = initialMessage.trim().replaceAll(RegExp(r'\s+'), ' ');
    
    // 如果消息太长，截断并添加省略号
    if (cleanMessage.length > 30) {
      return '${cleanMessage.substring(0, 30)}...';
    }
    
    return cleanMessage;
  }

  /// 准备图片路径列表
  /// 将ChatImage转换为可存储的文件路径
  static Future<List<String>> _prepareImagePaths(List<ChatImage> images) async {
    final paths = <String>[];
    
    for (final image in images) {
      if (image.filePath != null) {
        // 已经有文件路径，直接使用
        paths.add(image.filePath!);
      } else if (image.bytes != null) {
        // bytes数据，保存为临时文件
        try {
          final tempDir = await getTemporaryDirectory();
          final fileName = image.name ?? 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final tempFile = File('${tempDir.path}/ai_chat_images/$fileName');
          
          // 确保目录存在
          await tempFile.parent.create(recursive: true);
          
          // 写入文件
          await tempFile.writeAsBytes(image.bytes!);
          paths.add(tempFile.path);
          Log.info('✅ 图片bytes保存为临时文件: ${tempFile.path}');
        } catch (e) {
          Log.error('❌ 保存图片临时文件失败: $e');
        }
      } else if (image.url != null) {
        // URL图片，暂时跳过（可以考虑下载后保存）
        Log.warn('⚠️  URL图片暂不支持: ${image.url}');
      }
    }
    
    return paths;
  }
}

