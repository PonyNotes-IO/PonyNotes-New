import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/shared/custom_image_cache_manager.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../base/markdown_text_robot.dart';
import 'ai_writer_block_operations.dart';
import 'ai_writer_entities.dart';
import 'ai_writer_node_extension.dart';

/// Enable the debug log for the AiWriterCubit.
///
/// This is useful for debugging the AI writer cubit.
const _aiWriterCubitDebugLog = true;

class AiWriterCubit extends Cubit<AiWriterState> {
  AiWriterCubit({
    required this.documentId,
    required this.editorState,
    this.onCreateNode,
    this.onRemoveNode,
    this.onAppendToDocument,
  })  : _aiService = getIt<AIRepository>(),
        _textRobot = MarkdownTextRobot(editorState: editorState),
        selectedSourcesNotifier = ValueNotifier([documentId]),
        enableDeepThinkingNotifier = ValueNotifier(false),
        enableWebSearchNotifier = ValueNotifier(false),
        super(IdleAiWriterState());

  final String documentId;
  final EditorState editorState;

  /// 单次提问最多附带的图片数：多模态请求体是 base64，过多会显著拖慢甚至超限。
  static const _maxImagesForAsk = 4;
  final AIRepository _aiService;
  final MarkdownTextRobot _textRobot;
  final void Function()? onCreateNode;
  final void Function()? onRemoveNode;
  final void Function()? onAppendToDocument;

  Node? aiWriterNode;

  final List<AiWriterRecord> records = [];
  final ValueNotifier<List<String>> selectedSourcesNotifier;
  final ValueNotifier<bool> enableDeepThinkingNotifier;
  final ValueNotifier<bool> enableWebSearchNotifier;

  @override
  Future<void> close() async {
    selectedSourcesNotifier.dispose();
    enableDeepThinkingNotifier.dispose();
    enableWebSearchNotifier.dispose();
    await super.close();
  }

  Future<void> exit({
    bool withDiscard = true,
    bool withUnformat = true,
  }) async {
    if (aiWriterNode == null) {
      return;
    }
    if (withDiscard) {
      await _textRobot.discard(
        afterSelection: aiWriterNode!.aiWriterSelection,
      );
    }
    _textRobot.clear();
    _textRobot.reset();
    onRemoveNode?.call();
    records.clear();
    selectedSourcesNotifier.value = [documentId];
    emit(IdleAiWriterState());

    if (withUnformat) {
      final selection = aiWriterNode!.aiWriterSelection;
      if (selection == null) {
        return;
      }
      await formatSelection(
        editorState,
        selection,
        ApplySuggestionFormatType.clear,
      );
    }
    if (aiWriterNode != null) {
      await removeAiWriterNode(editorState, aiWriterNode!);
      aiWriterNode = null;
    }
  }

  void register(Node node) async {
    if (node.isAiWriterInitialized) {
      return;
    }
    if (aiWriterNode != null && node.id != aiWriterNode!.id) {
      await removeAiWriterNode(editorState, node);
      return;
    }

    aiWriterNode = node;
    onCreateNode?.call();

    await setAiWriterNodeIsInitialized(editorState, node);

    final command = node.aiWriterCommand;
    final (run, prompt) = await _addSelectionTextToRecords(command);

    _aiWriterCubitLog(
      'command: $command, run: $run, prompt: $prompt',
    );

    if (!run) {
      await exit();
      return;
    }

    runCommand(command, prompt, null, null);
  }

  void runCommand(
    AiWriterCommand command,
    String prompt,
    PredefinedFormat? predefinedFormat,
    String? promptId, {
    /// 输入框（AIPromptInputBloc.consumeMetadata）组装好的元数据，
    /// 其中 `images` 是用户通过附件按钮/粘贴挂上的图片（base64）。
    ///
    /// 此前这里没有这个参数，ai_writer_block_component 的 onSubmitted 直接把
    /// metadata 丢弃（写成 `_`），导致用户在输入框里挂的图片**从未被送出**，
    /// AI 自然回答「看不到图片」。
    Map<String, dynamic>? metadata,
  }) async {
    if (aiWriterNode == null) {
      return;
    }

    await _textRobot.discard();
    _textRobot.clear();

    switch (command) {
      case AiWriterCommand.continueWriting:
        await _startContinueWriting(
          command,
          predefinedFormat,
          promptId,
        );
        break;
      case AiWriterCommand.fixSpellingAndGrammar:
      case AiWriterCommand.improveWriting:
      case AiWriterCommand.makeLonger:
      case AiWriterCommand.makeShorter:
        await _startSuggestingEdits(
          command,
          prompt,
          predefinedFormat,
          promptId,
        );
        break;
      case AiWriterCommand.explain:
        await _startInforming(command, prompt, predefinedFormat, promptId);
        break;
      case AiWriterCommand.userQuestion when prompt.isNotEmpty:
        _startAskingQuestion(
          prompt,
          predefinedFormat,
          promptId,
          metadata: metadata,
        );
        break;
      case AiWriterCommand.userQuestion:
        emit(
          ReadyAiWriterState(AiWriterCommand.userQuestion, isFirstRun: true),
        );
        break;
    }
  }

  void _retry({
    required PredefinedFormat? predefinedFormat,
  }) async {
    final lastQuestion =
        records.lastWhereOrNull((record) => record.role == AiRole.user);

    if (lastQuestion != null && state is RegisteredAiWriter) {
      runCommand(
        (state as RegisteredAiWriter).command,
        lastQuestion.content,
        lastQuestion.format,
        null,
      );
    }
  }

  Future<void> stopStream() async {
    if (aiWriterNode == null) {
      return;
    }

    if (state is GeneratingAiWriterState) {
      final generatingState = state as GeneratingAiWriterState;

      await _textRobot.stop(
        attributes: ApplySuggestionFormatType.replace.attributes,
      );

      if (_textRobot.hasAnyResult) {
        records.add(AiWriterRecord.ai(content: _textRobot.markdownText));
      }

      await AIEventStopCompleteText(
        CompleteTextTaskPB(
          taskId: generatingState.taskId,
        ),
      ).send();

      emit(
        ReadyAiWriterState(
          generatingState.command,
          isFirstRun: false,
          markdownText: generatingState.markdownText,
        ),
      );
    }
  }

  void runResponseAction(
    SuggestionAction action, [
    PredefinedFormat? predefinedFormat,
  ]) async {
    if (aiWriterNode == null) {
      return;
    }

    if (action case SuggestionAction.rewrite || SuggestionAction.tryAgain) {
      _retry(predefinedFormat: predefinedFormat);
      return;
    }
    if (action case SuggestionAction.discard || SuggestionAction.close) {
      await exit();
      return;
    }

    final selection = aiWriterNode?.aiWriterSelection;
    if (selection == null) {
      return;
    }

    // Accept
    //
    // If the user clicks accept, we need to replace the selection with the AI's response
    if (action case SuggestionAction.accept) {
      // trim the markdown text to avoid extra new lines
      final trimmedMarkdownText = _textRobot.markdownText.trim();

      _aiWriterCubitLog(
        'trigger accept action, markdown text: $trimmedMarkdownText',
      );

      await formatSelection(
        editorState,
        selection,
        ApplySuggestionFormatType.clear,
      );

      await _textRobot.deleteAINodes();

      await _textRobot.replace(
        selection: selection,
        markdownText: trimmedMarkdownText,
      );

      await exit(withDiscard: false, withUnformat: false);

      return;
    }

    if (action case SuggestionAction.keep) {
      await _textRobot.persist();
      await exit(withDiscard: false);
      return;
    }

    if (action case SuggestionAction.insertBelow) {
      if (state is! ReadyAiWriterState) {
        return;
      }
      final command = (state as ReadyAiWriterState).command;
      final markdownText = (state as ReadyAiWriterState).markdownText;
      if (command == AiWriterCommand.explain && markdownText.isNotEmpty) {
        final position = await ensurePreviousNodeIsEmptyParagraph(
          editorState,
          aiWriterNode!,
        );
        _textRobot.start(position: position);
        await _textRobot.persist(markdownText: markdownText);
      } else if (_textRobot.hasAnyResult) {
        await _textRobot.persist();
      }

      await formatSelection(
        editorState,
        selection,
        ApplySuggestionFormatType.clear,
      );
      await exit(withDiscard: false);
    }
  }

  bool hasUnusedResponse() {
    return switch (state) {
      ReadyAiWriterState(
        isFirstRun: final isInitial,
        markdownText: final markdownText,
      ) =>
        !isInitial && (markdownText.isNotEmpty || _textRobot.hasAnyResult),
      GeneratingAiWriterState() => true,
      _ => false,
    };
  }

  Future<(bool, String)> _addSelectionTextToRecords(
    AiWriterCommand command,
  ) async {
    final node = aiWriterNode;

    // check the node is registered
    if (node == null) {
      Log.warn('[AI writer] Node is null');
      return (false, '');
    }

    // check the selection is valid
    final selection = node.aiWriterSelection?.normalized;
    if (selection == null) {
      Log.warn('[AI writer]Selection is null');
      return (false, '');
    }

    // if the command is continue writing, we don't need to get the selection text
    if (command == AiWriterCommand.continueWriting) {
      return (true, '');
    }

    // if the selection is collapsed, we don't need to get the selection text
    if (selection.isCollapsed) {
      return (true, '');
    }

    final selectionText = await editorState.getMarkdownInSelection(selection);

    if (command == AiWriterCommand.userQuestion) {
      records.add(
        AiWriterRecord.user(content: selectionText, format: null),
      );

      return (true, '');
    } else {
      return (true, selectionText);
    }
  }

  Future<String> _getDocumentContentFromTopToPosition(Position position) async {
    final beginningToCursorSelection = Selection(
      start: Position(path: [0]),
      end: position,
    ).normalized;

    final documentText =
        (await editorState.getMarkdownInSelection(beginningToCursorSelection))
            .trim();

    final view = await ViewBackendService.getView(documentId).toNullable();
    final viewName = view?.name ?? '';

    return "$viewName\n$documentText".trim();
  }

  /// 从输入框元数据里取出用户挂的图片（base64）。
  ///
  /// 键名与 AIPromptInputBloc.consumeMetadata 保持一致（images / has_images），
  /// 后者会把附件中扩展名为 jpg/jpeg/png 的项读成 base64 放进来。
  List<String> _extractImagesFromMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null) return const [];
    final raw = metadata['images'];
    if (raw is! List) return const [];
    return raw.whereType<String>().where((e) => e.isNotEmpty).toList();
  }

  /// 收集文档中可用于图片分析的图片，返回 base64 列表。
  ///
  /// 文档内 AI 与「问 AI」最终落到同一个 /api/ai/chat/session 接口，服务端早已
  /// 支持多模态（qwen3-vl-plus）；此前不支持图片分析，是因为文档侧从未把图片
  /// 传下去。
  ///
  /// **取字节的关键**：文档图片块里存的是**云端 URL**（saveImageToCloudStorage
  /// 返回的就是它），不是本地路径。字节则以该 URL 为键缓存在
  /// CustomImageCacheManager 里。上一版按「本地路径」读盘、遇到 http 一律跳过，
  /// 结果收集数恒为 0 —— AI 自然回答「没有收到任何图片文件」。
  /// 这里改为：本地路径直接读盘；云端 URL 先查缓存（命中即零网络），
  /// 未命中才按需下载，且有超时上限，不会把提问拖住。
  ///
  /// 遍历必须**递归**：图片可能嵌在其它块内，只看顶层子节点会漏。
  Future<List<String>> _collectDocumentImagesAsBase64() async {
    final urls = <String>[];

    void collect(Node node) {
      if (urls.length >= _maxImagesForAsk) return;
      if (node.type == CustomImageBlockKeys.type) {
        final url = node.attributes[CustomImageBlockKeys.url] as String?;
        if (url != null && url.isNotEmpty && !urls.contains(url)) {
          urls.add(url);
        }
      }
      for (final child in node.children) {
        collect(child);
      }
    }

    try {
      collect(editorState.document.root);
    } catch (e) {
      Log.warn('[AIWriter] 遍历文档节点异常，按无图片处理: $e');
      return const [];
    }

    if (urls.isEmpty) {
      Log.info('[AIWriter] 文档内未找到图片块');
      return const [];
    }

    final result = <String>[];
    for (final url in urls) {
      try {
        final bytes = await _readImageBytes(url);
        if (bytes == null || bytes.isEmpty) {
          Log.warn('[AIWriter] 图片取字节为空，已跳过: $url');
          continue;
        }
        result.add(base64Encode(bytes));
      } catch (e) {
        Log.warn('[AIWriter] 读取图片失败，已跳过: $url, $e');
      }
    }

    Log.info(
      '[AIWriter] 文档图片块 ${urls.length} 个，成功取到 ${result.length} 张随提问上送',
    );
    return result;
  }

  /// 取单张图片的字节。本地路径直接读盘；云端 URL 优先走缓存，未命中再下载。
  Future<Uint8List?> _readImageBytes(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final file = File(url);
      if (!file.existsSync()) return null;
      return file.readAsBytes();
    }

    // 缓存命中：零网络开销，这是绝大多数情况（图片是在本机插入的）。
    final cached = await CustomImageCacheManager().getFileFromCache(url);
    if (cached != null && await cached.file.exists()) {
      return cached.file.readAsBytes();
    }

    // 未命中（如在别的设备插入的图片）：按需下载，但设超时，
    // 绝不让取图把提问卡住 —— 拿不到就少传这一张。
    final file = await CustomImageCacheManager()
        .getSingleFile(url)
        .timeout(const Duration(seconds: 8));
    return file.readAsBytes();
  }

  void _startAskingQuestion(
    String prompt,
    PredefinedFormat? format,
    String? promptId, {
    Map<String, dynamic>? metadata,
  }) async {
    if (aiWriterNode == null) {
      return;
    }
    final command = AiWriterCommand.userQuestion;

    // 图片来源有两处，优先级：**输入框挂的附件 > 文档里的图片块**。
    //
    // 用户在输入框里明确挂了图片，意图就是让 AI 看这几张；此时不应再把文档里
    // 无关的图片混进去。只有用户没挂附件时，才退而把文档中的图片带上，
    // 用于「分析这篇文档里的图」这类提问。
    final attached = _extractImagesFromMetadata(metadata);
    final images =
        attached.isNotEmpty ? attached : await _collectDocumentImagesAsBase64();
    Log.info(
      '[AIWriter] 提问附带图片：附件 ${attached.length} 张，'
      '最终上送 ${images.length} 张',
    );

    // 【修复】文档内向AI提问时，不传objectId，避免后端查找view失败的问题
    // 提问和回答会直接插入到当前文档中，而不是创建新的AI会话视图
    final stream = await _aiService.streamCompletion(
      objectId: null,  // 不传objectId，避免后端查找view失败
      text: prompt,
      format: format,
      promptId: promptId,
      history: records,
      sourceIds: [],  // 不传sourceIds，避免RAG检索
      completionType: command.toCompletionType(),
      enableDeepThinking: enableDeepThinkingNotifier.value,
      enableWebSearch: enableWebSearchNotifier.value,
      images: images,
      onStart: () async {
        final position = await ensurePreviousNodeIsEmptyParagraph(
          editorState,
          aiWriterNode!,
        );
        _textRobot.start(position: position);
        records.add(
          AiWriterRecord.user(
            content: prompt,
            format: format,
          ),
        );
      },
      processMessage: (text) async {
        await _textRobot.appendMarkdownText(
          text,
          updateSelection: false,
          attributes: ApplySuggestionFormatType.replace.attributes,
        );
        onAppendToDocument?.call();
      },
      processAssistMessage: (text) async {
        if (state case final GeneratingAiWriterState generatingState) {
          emit(
            GeneratingAiWriterState(
              command,
              taskId: generatingState.taskId,
              markdownText: generatingState.markdownText + text,
            ),
          );
        }
      },
      onEnd: () async {
        if (state case final GeneratingAiWriterState generatingState) {
          await _textRobot.stop(
            attributes: ApplySuggestionFormatType.replace.attributes,
          );
          emit(
            ReadyAiWriterState(
              command,
              isFirstRun: false,
              markdownText: generatingState.markdownText,
            ),
          );
          records.add(
            AiWriterRecord.ai(content: _textRobot.markdownText),
          );
        }
      },
      onError: (error) async {
        emit(ErrorAiWriterState(command, error: error));
        records.add(
          AiWriterRecord.ai(content: _textRobot.markdownText),
        );
      },
      onLocalAIStreamingStateChange: (state) {
        emit(LocalAIStreamingAiWriterState(command, state: state));
      },
    );

    if (stream != null) {
      emit(
        GeneratingAiWriterState(
          command,
          taskId: stream.$1,
        ),
      );
    }

  }

  Future<void> _startContinueWriting(
    AiWriterCommand command,
    PredefinedFormat? predefinedFormat,
    String? promptId,
  ) async {
    final position = aiWriterNode?.aiWriterSelection?.start;
    if (position == null) {
      return;
    }
    final text = await _getDocumentContentFromTopToPosition(position);

    if (text.isEmpty) {
      final stateCopy = state;
      emit(DocumentContentEmptyAiWriterState(command, onConfirm: exit));
      emit(stateCopy);
      return;
    }

    final stream = await _aiService.streamCompletion(
      objectId: documentId,
      text: text,
      completionType: command.toCompletionType(),
      history: records,
      sourceIds: selectedSourcesNotifier.value,
      format: predefinedFormat,
      promptId: promptId,
      enableDeepThinking: enableDeepThinkingNotifier.value,
      enableWebSearch: enableWebSearchNotifier.value,
      onStart: () async {
        final position = await ensurePreviousNodeIsEmptyParagraph(
          editorState,
          aiWriterNode!,
        );
        _textRobot.start(position: position);
        records.add(
          AiWriterRecord.user(
            content: text,
            format: predefinedFormat,
          ),
        );
      },
      processMessage: (text) async {
        await _textRobot.appendMarkdownText(
          text,
          updateSelection: false,
          attributes: ApplySuggestionFormatType.replace.attributes,
        );
        onAppendToDocument?.call();
      },
      processAssistMessage: (text) async {
        if (state case final GeneratingAiWriterState generatingState) {
          emit(
            GeneratingAiWriterState(
              command,
              taskId: generatingState.taskId,
              markdownText: generatingState.markdownText + text,
            ),
          );
        }
      },
      onEnd: () async {
        if (state case final GeneratingAiWriterState generatingState) {
          await _textRobot.stop(
            attributes: ApplySuggestionFormatType.replace.attributes,
          );
          emit(
            ReadyAiWriterState(
              command,
              isFirstRun: false,
              markdownText: generatingState.markdownText,
            ),
          );
        }
        records.add(
          AiWriterRecord.ai(content: _textRobot.markdownText),
        );
      },
      onError: (error) async {
        emit(ErrorAiWriterState(command, error: error));
        records.add(
          AiWriterRecord.ai(content: _textRobot.markdownText),
        );
      },
      onLocalAIStreamingStateChange: (state) {
        emit(LocalAIStreamingAiWriterState(command, state: state));
      },
    );
    if (stream != null) {
      emit(
        GeneratingAiWriterState(command, taskId: stream.$1),
      );
    }
  }

  Future<void> _startSuggestingEdits(
    AiWriterCommand command,
    String prompt,
    PredefinedFormat? predefinedFormat,
    String? promptId,
  ) async {
    final selection = aiWriterNode?.aiWriterSelection;
    if (selection == null) {
      return;
    }
    if (prompt.isEmpty) {
      prompt = records.removeAt(0).content;
    }

    final stream = await _aiService.streamCompletion(
      objectId: documentId,
      text: prompt,
      format: predefinedFormat,
      promptId: promptId,
      completionType: command.toCompletionType(),
      history: records,
      sourceIds: selectedSourcesNotifier.value,
      enableDeepThinking: enableDeepThinkingNotifier.value,
      enableWebSearch: enableWebSearchNotifier.value,
      onStart: () async {
        await formatSelection(
          editorState,
          selection,
          ApplySuggestionFormatType.original,
        );
        final position = await ensurePreviousNodeIsEmptyParagraph(
          editorState,
          aiWriterNode!,
        );
        _textRobot.start(position: position, previousSelection: selection);
        records.add(
          AiWriterRecord.user(
            content: prompt,
            format: predefinedFormat,
          ),
        );
      },
      processMessage: (text) async {
        await _textRobot.appendMarkdownText(
          text,
          updateSelection: false,
          attributes: ApplySuggestionFormatType.replace.attributes,
        );
        onAppendToDocument?.call();

        _aiWriterCubitLog(
          'received message: $text',
        );
      },
      processAssistMessage: (text) async {
        if (state case final GeneratingAiWriterState generatingState) {
          emit(
            GeneratingAiWriterState(
              command,
              taskId: generatingState.taskId,
              markdownText: generatingState.markdownText + text,
            ),
          );
        }

        _aiWriterCubitLog(
          'received assist message: $text',
        );
      },
      onEnd: () async {
        if (state case final GeneratingAiWriterState generatingState) {
          await _textRobot.stop(
            attributes: ApplySuggestionFormatType.replace.attributes,
          );
          emit(
            ReadyAiWriterState(
              command,
              isFirstRun: false,
              markdownText: generatingState.markdownText,
            ),
          );
          records.add(
            AiWriterRecord.ai(content: _textRobot.markdownText),
          );

          _aiWriterCubitLog(
            'returned response: ${_textRobot.markdownText}',
          );
        }
      },
      onError: (error) async {
        emit(ErrorAiWriterState(command, error: error));
        records.add(
          AiWriterRecord.ai(content: _textRobot.markdownText),
        );
      },
      onLocalAIStreamingStateChange: (state) {
        emit(LocalAIStreamingAiWriterState(command, state: state));
      },
    );
    if (stream != null) {
      emit(
        GeneratingAiWriterState(command, taskId: stream.$1),
      );
    }
  }

  Future<void> _startInforming(
    AiWriterCommand command,
    String prompt,
    PredefinedFormat? predefinedFormat,
    String? promptId,
  ) async {
    final selection = aiWriterNode?.aiWriterSelection;
    if (selection == null) {
      return;
    }
    if (prompt.isEmpty) {
      prompt = records.removeAt(0).content;
    }

    final stream = await _aiService.streamCompletion(
      objectId: documentId,
      text: prompt,
      completionType: command.toCompletionType(),
      history: records,
      sourceIds: selectedSourcesNotifier.value,
      format: predefinedFormat,
      promptId: promptId,
      enableDeepThinking: enableDeepThinkingNotifier.value,
      enableWebSearch: enableWebSearchNotifier.value,
      onStart: () async {
        records.add(
          AiWriterRecord.user(
            content: prompt,
            format: predefinedFormat,
          ),
        );
      },
      processMessage: (text) async {
        if (state case final GeneratingAiWriterState generatingState) {
          emit(
            GeneratingAiWriterState(
              command,
              taskId: generatingState.taskId,
              markdownText: generatingState.markdownText + text,
            ),
          );
        }
      },
      processAssistMessage: (_) async {},
      onEnd: () async {
        if (state case final GeneratingAiWriterState generatingState) {
          emit(
            ReadyAiWriterState(
              command,
              isFirstRun: false,
              markdownText: generatingState.markdownText,
            ),
          );
          records.add(
            AiWriterRecord.ai(content: generatingState.markdownText),
          );
        }
      },
      onError: (error) async {
        if (state case final GeneratingAiWriterState generatingState) {
          records.add(
            AiWriterRecord.ai(content: generatingState.markdownText),
          );
        }
        emit(ErrorAiWriterState(command, error: error));
      },
      onLocalAIStreamingStateChange: (state) {
        emit(LocalAIStreamingAiWriterState(command, state: state));
      },
    );
    if (stream != null) {
      emit(
        GeneratingAiWriterState(command, taskId: stream.$1),
      );
    }
  }

  void _aiWriterCubitLog(String message) {
    if (_aiWriterCubitDebugLog) {
      Log.debug('[AiWriterCubit] $message');
    }
  }
}

mixin RegisteredAiWriter {
  AiWriterCommand get command;
}

sealed class AiWriterState {
  const AiWriterState();
}

class IdleAiWriterState extends AiWriterState {
  const IdleAiWriterState();
}

class ReadyAiWriterState extends AiWriterState with RegisteredAiWriter {
  const ReadyAiWriterState(
    this.command, {
    required this.isFirstRun,
    this.markdownText = '',
  });

  @override
  final AiWriterCommand command;

  final bool isFirstRun;
  final String markdownText;
}

class GeneratingAiWriterState extends AiWriterState with RegisteredAiWriter {
  const GeneratingAiWriterState(
    this.command, {
    required this.taskId,
    this.progress = '',
    this.markdownText = '',
  });

  @override
  final AiWriterCommand command;

  final String taskId;
  final String progress;
  final String markdownText;
}

class ErrorAiWriterState extends AiWriterState with RegisteredAiWriter {
  const ErrorAiWriterState(
    this.command, {
    required this.error,
  });

  @override
  final AiWriterCommand command;

  final AIError error;
}

class DocumentContentEmptyAiWriterState extends AiWriterState
    with RegisteredAiWriter {
  const DocumentContentEmptyAiWriterState(
    this.command, {
    required this.onConfirm,
  });

  @override
  final AiWriterCommand command;

  final void Function() onConfirm;
}

class LocalAIStreamingAiWriterState extends AiWriterState
    with RegisteredAiWriter {
  const LocalAIStreamingAiWriterState(
    this.command, {
    required this.state,
  });

  @override
  final AiWriterCommand command;

  final LocalAIStreamingState state;
}
