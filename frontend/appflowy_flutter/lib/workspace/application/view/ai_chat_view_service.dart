import 'dart:convert';
import 'dart:io';
import 'package:appflowy/plugins/standalone_ai_chat/models/chat_image.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon_popup.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart';

/// AI会话子空间名称
const String kAIChatSpaceName = '我的AI会话';

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
      Log.info('   - 工作空间ID: $parentViewId');
      Log.info('   - 名称: $chatName');
      Log.info('   - 模型: $selectedModelId');
      Log.info('   - 初始消息: ${initialMessage?.substring(0, initialMessage.length > 50 ? 50 : initialMessage.length)}...');
      Log.info('   - 图片数量: ${initialImages?.length ?? 0}');

      // 2. 获取或创建"我的AI会话"子空间（Space类型）
      final aiChatSpaceId = await _getOrCreateAIChatSpace(parentViewId);
      if (aiChatSpaceId == null) {
        Log.error('❌ 无法获取或创建"我的AI会话"子空间');
        return null;
      }
      Log.info('✅ AI会话子空间ID: $aiChatSpaceId');

      // 3. 处理图片数据
      List<String>? imagePaths;
      if (initialImages != null && initialImages.isNotEmpty) {
        imagePaths = await _prepareImagePaths(initialImages);
        Log.info('✅ 准备了 ${imagePaths.length} 张图片路径');
      }

      // 4. 构建额外参数（存储为JSON）
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

      // 5. 在"我的AI会话"子空间下创建Chat类型的View
      // 注意：设置 openAfterCreate: false，因为我们需要先更新extra字段再打开
      final result = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Chat,
        parentViewId: aiChatSpaceId,  // 使用AI会话子空间作为父视图
        name: chatName,
        openAfterCreate: false,  // 先不打开，等更新extra后再打开
        section: ViewSectionPB.Private,  // 指定为私有空间
      );

      // 【修复】使用 isSuccess/isFailure 替代 fold，避免 async 回调不等待的问题
      if (result.isFailure) {
        final error = result.getFailure();
        Log.error('❌ 创建AI Chat视图失败: ${error.msg}');
        Log.error('   - 错误代码: ${error.code}');
        return null;
      }
      
      final view = result.toNullable()!;
      Log.info('✅ 成功创建AI Chat视图');
      Log.info('   - 视图ID: ${view.id}');
      Log.info('   - 视图名称: ${view.name}');
      Log.info('   - 父视图ID: $aiChatSpaceId');
      
      // 6. 如果有额外数据，更新view的extra字段
      if (extraJson != null) {
        Log.info('🔄 更新视图的extra字段...');
        final updateResult = await ViewBackendService.updateView(
          viewId: view.id,
          extra: extraJson,
        );
        if (updateResult.isSuccess) {
          Log.info('✅ extra字段更新成功');
        } else {
          Log.error('❌ extra字段更新失败: ${updateResult.getFailure().msg}');
        }
      }
      
      // 7. 重新获取视图数据（包含更新后的extra字段）
      ViewPB updatedView = view;
      if (extraJson != null) {
        Log.info('🔄 重新获取视图数据以包含更新后的extra...');
        final getViewResult = await ViewBackendService.getView(view.id);
        if (getViewResult.isSuccess) {
          updatedView = getViewResult.toNullable()!;
          Log.info('✅ 重新获取视图成功，extra: ${updatedView.extra}');
        } else {
          Log.warn('⚠️  重新获取视图失败，使用原视图: ${getViewResult.getFailure().msg}');
        }
      }
      
      // 8. 创建AIChatPagePlugin并打开（使用更新后的视图）
      try {
        final plugin = updatedView.plugin();
        Log.info('✅ 创建插件成功，正在打开标签页...');
        
        getIt<TabsBloc>().add(
          TabsEvent.openPlugin(
            plugin: plugin,
            view: updatedView,  // 使用更新后的视图
          ),
        );
        
        Log.info('✅ AI Chat标签页已打开');
      } catch (pluginError) {
        Log.error('❌ 创建或打开插件失败: $pluginError');
      }
      
      return updatedView;
    } catch (e, stackTrace) {
      Log.error('❌ 创建AI Chat视图异常: $e', e, stackTrace);
      return null;
    }
  }

  /// 获取或创建"我的AI会话"子空间（Space类型）
  /// 返回子空间的viewId
  static Future<String?> _getOrCreateAIChatSpace(String workspaceId) async {
    try {
      Log.info('🔍 查找"$kAIChatSpaceName"子空间...');
      
      // 1. 获取用户信息
      final userResult = await UserEventGetUserProfile().send();
      final userProfile = userResult.fold((user) => user, (e) => null);
      if (userProfile == null) {
        Log.error('❌ 无法获取用户信息');
        return null;
      }

      // 2. 创建工作空间服务
      final workspaceService = WorkspaceService(
        workspaceId: workspaceId,
        userId: userProfile.id,
      );

      // 3. 获取私有空间和公共空间视图列表
      final privateViewsResult = await workspaceService.getPrivateViews();
      final publicViewsResult = await workspaceService.getPublicViews();
      
      final privateViews = privateViewsResult.fold(
        (views) => views,
        (error) {
          Log.error('❌ 获取私有视图列表失败: ${error.msg}');
          return <ViewPB>[];
        },
      );
      
      final publicViews = publicViewsResult.fold(
        (views) => views,
        (error) {
          Log.error('❌ 获取公共视图列表失败: ${error.msg}');
          return <ViewPB>[];
        },
      );

      // 4. 合并私有空间和公共空间
      final allViews = [...privateViews, ...publicViews];
      final allSpaces = allViews.where((view) => view.isSpace).toList();

      Log.info('📋 所有空间视图数量: ${allSpaces.length}');
      for (final view in allSpaces) {
        Log.info('   - ${view.name} (id: ${view.id}, isSpace: ${view.isSpace}, permission: ${view.spacePermission})');
      }

      // 5. 查找"我的AI会话"子空间（isSpace=true 且名称匹配）
      final existingSpace = allSpaces.firstWhereOrNull(
        (view) => view.isSpace && view.name == kAIChatSpaceName,
      );

      if (existingSpace != null) {
        Log.info('✅ 找到已存在的"$kAIChatSpaceName"子空间: ${existingSpace.id}，类型: ${existingSpace.spacePermission}');
        return existingSpace.id;
      }

      // 6. 不存在则在私有空间中创建"我的AI会话"子空间（Space类型）
      Log.info('🔄 创建"$kAIChatSpaceName"子空间...');
      
      // 构建Space的extra属性
      final spaceExtra = {
        ViewExtKeys.isSpaceKey: true,  // 关键：标记为Space
        ViewExtKeys.spaceIconKey: builtInSpaceIcons.first,  // 使用默认图标
        ViewExtKeys.spaceIconColorKey: builtInSpaceColors[2],  // 使用蓝色（0x00C8FF）
        ViewExtKeys.spacePermissionKey: SpacePermission.private.index,  // 私有空间
        ViewExtKeys.spaceCreatedAtKey: DateTime.now().millisecondsSinceEpoch,
      };
      
      final createResult = await workspaceService.createView(
        name: kAIChatSpaceName,
        viewSection: ViewSectionPB.Private,  // 放在私有空间区域
        setAsCurrent: false,  // 不要设置为当前空间
        extra: jsonEncode(spaceExtra),  // 包含Space属性
      );

      return createResult.fold(
        (space) {
          Log.info('✅ 成功创建"$kAIChatSpaceName"子空间: ${space.id}');
          return space.id;
        },
        (error) {
          Log.error('❌ 创建"$kAIChatSpaceName"子空间失败: ${error.msg}');
          return null;
        },
      );
    } catch (e, stackTrace) {
      Log.error('❌ 获取或创建AI会话子空间异常: $e', e, stackTrace);
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
  /// 使用永久存储目录（getApplicationDocumentsDirectory）而非临时目录，
  /// 确保图片在应用重启后仍然存在
  static Future<List<String>> _prepareImagePaths(List<ChatImage> images) async {
    final paths = <String>[];
    final appDir = await getApplicationDocumentsDirectory();
    final storageDir = Directory('${appDir.path}/ai_chat_images');

    // 确保目录存在
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }

    for (final image in images) {
      try {
        String? finalPath;

        // 优先从 bytes 创建（最可靠的方式）
        if (image.bytes != null) {
          final fileName = image.name ?? 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final imageFile = File('${storageDir.path}/$fileName');
          await imageFile.writeAsBytes(image.bytes!);
          finalPath = imageFile.path;
          Log.info('✅ 图片从bytes保存到永久目录: ${imageFile.path}');
        }
        // 如果没有bytes，尝试从filePath读取并复制
        else if (image.filePath != null) {
          final sourceFile = File(image.filePath!);
          if (await sourceFile.exists()) {
            final fileName = image.name ?? '${DateTime.now().millisecondsSinceEpoch}_${image.filePath!.split('/').last}';
            final imageFile = File('${storageDir.path}/$fileName');
            // 复制文件到永久目录
            await sourceFile.copy(imageFile.path);
            finalPath = imageFile.path;
            Log.info('✅ 图片从filePath复制到永久目录: ${imageFile.path}');
          } else {
            Log.warn('⚠️  源图片文件不存在: ${image.filePath}');
          }
        }
        // URL图片，暂时跳过
        else if (image.url != null) {
          Log.warn('⚠️  URL图片暂不支持: ${image.url}');
        }

        if (finalPath != null) {
          paths.add(finalPath);
        }
      } catch (e) {
        Log.error('❌ 处理图片失败: $e');
      }
    }

    return paths;
  }
}
