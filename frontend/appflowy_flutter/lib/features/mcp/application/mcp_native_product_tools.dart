part of 'mcp_tools.dart';

extension _McpNativeProductTools on McpTools {
  List<McpToolSpec> get _nativeProductSpecs => [
        _nativeTool('local_ai_control', '查询本地AI运行状态/配置并启停、重启或修改配置。', {
          'status': _NativeAction<UserWorkspaceIdPB>(
            UserWorkspaceIdPB.create,
            (p) async => AIEventGetLocalAIState().send().getOrThrow(),
            readOnly: true,
          ),
          'settings': _NativeAction<UserWorkspaceIdPB>(
            UserWorkspaceIdPB.create,
            (p) async => AIEventGetLocalAISetting().send().getOrThrow(),
            readOnly: true,
          ),
          'toggle': _NativeAction<UserWorkspaceIdPB>(
            UserWorkspaceIdPB.create,
            (p) async => AIEventToggleLocalAI().send().getOrThrow(),
            confirm: true,
          ),
          'restart': _NativeAction<UserWorkspaceIdPB>(
            UserWorkspaceIdPB.create,
            (p) async => AIEventRestartLocalAI().send().getOrThrow(),
            confirm: true,
          ),
          'configure': _NativeAction<LocalAISettingPB>(
            LocalAISettingPB.create,
            (p) async => AIEventUpdateLocalAISetting(p).send().getOrThrow(),
            confirm: true,
          ),
        }),
        _withActions(
          _nativeTool('ai_chat_action', '读取聊天历史、生成回答、停止生成、读取相关问题或修改聊天设置。', {
            'previous_messages': _NativeAction<LoadPrevChatMessagePB>(
              LoadPrevChatMessagePB.create,
              (p) async => AIEventLoadPrevMessage(p).send().getOrThrow(),
              readOnly: true,
            ),
            'next_messages': _NativeAction<LoadNextChatMessagePB>(
              LoadNextChatMessagePB.create,
              (p) async => AIEventLoadNextMessage(p).send().getOrThrow(),
              readOnly: true,
            ),
            'stop': _NativeAction<StopStreamPB>(
              StopStreamPB.create,
              _stopChatAction,
            ),
            'related_questions': _NativeAction<ChatMessageIdPB>(
              ChatMessageIdPB.create,
              (p) async => AIEventGetRelatedQuestion(p).send().getOrThrow(),
              readOnly: true,
            ),
            'get_settings': _NativeAction<ChatId>(
              ChatId.create,
              (p) async => AIEventGetChatSettings(p).send().getOrThrow(),
              readOnly: true,
            ),
            'update_settings': _NativeAction<UpdateChatSettingsPB>(
              UpdateChatSettingsPB.create,
              (p) async => AIEventUpdateChatSettings(p).send().getOrThrow(),
            ),
          }),
          {
            'chat_id': const JsonString(),
            'text': const JsonString(),
            'answer_message_id': const JsonString(),
            'task_id': const JsonString(),
          },
          ['send', 'regenerate', 'read_stream'],
          _safeChatAction,
        ),
        _withActions(
          _nativeTool('page_sharing', '读取、修改页面成员与权限、管理分享链接及访问申请。', {
            'get_page_access': _NativeAction<GetSharedUsersPayloadPB>(
              GetSharedUsersPayloadPB.create,
              (p) async => FolderEventGetSharedUsers(p).send().getOrThrow(),
              readOnly: true,
            ),
            'invite_page_member': _NativeAction<SharePageWithUserPayloadPB>(
              SharePageWithUserPayloadPB.create,
              (p) async => FolderEventSharePageWithUser(p).send().getOrThrow(),
              owner: true,
              confirm: true,
            ),
            'revoke_page_access':
                _NativeAction<RemoveUserFromSharedPagePayloadPB>(
              RemoveUserFromSharedPagePayloadPB.create,
              (p) async =>
                  FolderEventRemoveUserFromSharedPage(p).send().getOrThrow(),
              owner: true,
              confirm: true,
            ),
          }),
          {
            'page_id': const JsonString(),
            'user_id': const JsonString(),
            'access_level': const JsonInteger(minimum: 1, maximum: 4),
            'operation': const JsonString(),
            'request_id': const JsonString(),
            'decision': const JsonBoolean(),
          },
          [
            'update_page_member',
            'create_page_share_link',
            'request_resource_access',
            'manage_access_requests',
          ],
          _sharingCloud,
        ),
        _withActions(
          _nativeTool('site_publishing', '发布、取消发布、读取发布信息、设置公开路径和站点主页。', {
            'publish_page': _NativeAction<PublishViewParamsPB>(
              PublishViewParamsPB.create,
              (p) async => FolderEventPublishView(p).send().getOrThrow(),
              owner: true,
              confirm: true,
            ),
            'unpublish_pages': _NativeAction<UnpublishViewsPayloadPB>(
              UnpublishViewsPayloadPB.create,
              (p) async => FolderEventUnpublishViews(p).send().getOrThrow(),
              owner: true,
              confirm: true,
            ),
            'list_published_pages': _NativeAction<UserWorkspaceIdPB>(
              UserWorkspaceIdPB.create,
              (p) async => FolderEventListPublishedViews().send().getOrThrow(),
              readOnly: true,
            ),
            'get_publish_info': _NativeAction<ViewIdPB>(
              ViewIdPB.create,
              (p) async => FolderEventGetPublishInfo(p).send().getOrThrow(),
              readOnly: true,
            ),
            'update_publish_settings': _NativeAction<SetPublishNamePB>(
              SetPublishNamePB.create,
              (p) async => FolderEventSetPublishName(p).send().getOrThrow(),
              owner: true,
              confirm: true,
            ),
            'update_site_settings.namespace':
                _NativeAction<SetPublishNamespacePayloadPB>(
              SetPublishNamespacePayloadPB.create,
              (p) async =>
                  FolderEventSetPublishNamespace(p).send().getOrThrow(),
              owner: true,
              confirm: true,
            ),
            'update_site_settings.homepage': _NativeAction<ViewIdPB>(
              ViewIdPB.create,
              (p) async =>
                  FolderEventSetDefaultPublishView(p).send().getOrThrow(),
              owner: true,
              confirm: true,
            ),
          }),
          {
            'publish_id': const JsonString(),
            'page_id': const JsonString(),
            'operation': const JsonString(),
            'comment_id': const JsonString(),
            'text': const JsonString(),
            'reaction': const JsonString(),
            'reply_comment_id': const JsonString(),
            'parent_id': const JsonString(),
            'publish_namespace': const JsonString(),
            'publish_name': const JsonString(),
          },
          [
            'published_page_interaction',
            'import_published_page',
            'manage_site_domain',
          ],
          _publishingCloud,
        ),
      ];
}
