import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/ai/service/ai_model_state_notifier.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_entity.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'ai_entities.dart';

part 'ai_prompt_input_bloc.freezed.dart';

class AIPromptInputBloc extends Bloc<AIPromptInputEvent, AIPromptInputState> {
  AIPromptInputBloc({
    required String objectId,
    required PredefinedFormat? predefinedFormat,
  })  : aiModelStateNotifier = AIModelStateNotifier(objectId: objectId),
        super(AIPromptInputState.initial(predefinedFormat)) {
    _dispatch();
    _startListening();
    _init();
  }

  final AIModelStateNotifier aiModelStateNotifier;

  String? promptId;

  @override
  Future<void> close() async {
    await aiModelStateNotifier.dispose();
    return super.close();
  }

  void _dispatch() {
    on<AIPromptInputEvent>(
      (event, emit) {
        event.when(
          updateAIState: (modelState) {
            emit(
              state.copyWith(
                modelState: modelState,
              ),
            );
          },
          toggleShowPredefinedFormat: () {
            final showPredefinedFormats = !state.showPredefinedFormats;
            final predefinedFormat =
                showPredefinedFormats && state.predefinedFormat == null
                    ? PredefinedFormat(
                        imageFormat: ImageFormat.text,
                        textFormat: TextFormat.paragraph,
                      )
                    : null;
            emit(
              state.copyWith(
                showPredefinedFormats: showPredefinedFormats,
                predefinedFormat: predefinedFormat,
              ),
            );
          },
          updatePredefinedFormat: (format) {
            if (!state.showPredefinedFormats) {
              return;
            }
            emit(state.copyWith(predefinedFormat: format));
          },
          attachFile: (filePath, fileName) {
            final newFile = ChatFile.fromFilePath(filePath);
            if (newFile != null) {
              emit(
                state.copyWith(
                  attachedFiles: [...state.attachedFiles, newFile],
                ),
              );
            }
          },
          removeFile: (file) {
            final files = [...state.attachedFiles];
            files.remove(file);
            emit(
              state.copyWith(
                attachedFiles: files,
              ),
            );
          },
          updateMentionedViews: (views) {
            emit(
              state.copyWith(
                mentionedPages: views,
              ),
            );
          },
          updatePromptId: (promptId) {
            this.promptId = promptId;
          },
          clearMetadata: () {
            promptId = null;
            emit(
              state.copyWith(
                attachedFiles: [],
                mentionedPages: [],
              ),
            );
          },
          // PonyNotes: 深度思考开关处理
          toggleDeepThinking: () {
            emit(
              state.copyWith(
                enableDeepThinking: !state.enableDeepThinking,
              ),
            );
          },
          // PonyNotes: 联网搜索开关处理
          toggleWebSearch: () {
            emit(
              state.copyWith(
                enableWebSearch: !state.enableWebSearch,
              ),
            );
          },
        );
      },
    );
  }

  void _startListening() {
    aiModelStateNotifier.addListener(
      onStateChanged: (modelState) {
        add(
          AIPromptInputEvent.updateAIState(modelState),
        );
      },
    );
  }

  void _init() {
    final modelState = aiModelStateNotifier.getState();
    add(
      AIPromptInputEvent.updateAIState(modelState),
    );
  }

  /// 消费metadata，将图片文件转换为base64并添加到images字段
  Future<Map<String, dynamic>> consumeMetadata() async {
    final metadata = <String, dynamic>{};

    // 添加提到的页面
    for (final page in state.mentionedPages) {
      metadata[page.id] = page;
    }

    // 识别并处理图片文件
    final List<String> imageBase64List = [];
    final List<ChatFile> nonImageFiles = [];
    
    for (final file in state.attachedFiles) {
      if (_isImageFile(file.filePath)) {
        try {
          // 读取图片文件并转换为base64
          final fileData = await File(file.filePath).readAsBytes();
          final base64String = base64Encode(fileData);
          imageBase64List.add(base64String);
        } catch (e) {
          // 如果读取失败，仍然作为普通文件处理
          nonImageFiles.add(file);
        }
      } else {
        nonImageFiles.add(file);
      }
    }

    // 如果有图片，添加到metadata的images字段
    if (imageBase64List.isNotEmpty) {
      metadata['images'] = imageBase64List;
      metadata['has_images'] = true;
    }

    // 保留非图片文件
    for (final file in nonImageFiles) {
      metadata[file.filePath] = file;
    }

    if (metadata.isNotEmpty && !isClosed) {
      add(const AIPromptInputEvent.clearMetadata());
    }

    return metadata;
  }

  /// 判断文件是否为图片
  bool _isImageFile(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff'];
    return imageExtensions.contains(extension);
  }
}

@freezed
class AIPromptInputEvent with _$AIPromptInputEvent {
  const factory AIPromptInputEvent.updateAIState(
    AIModelState modelState,
  ) = _UpdateAIState;

  const factory AIPromptInputEvent.toggleShowPredefinedFormat() =
      _ToggleShowPredefinedFormat;
  const factory AIPromptInputEvent.updatePredefinedFormat(
    PredefinedFormat format,
  ) = _UpdatePredefinedFormat;
  const factory AIPromptInputEvent.attachFile(
    String filePath,
    String fileName,
  ) = _AttachFile;
  const factory AIPromptInputEvent.removeFile(ChatFile file) = _RemoveFile;
  const factory AIPromptInputEvent.updateMentionedViews(List<ViewPB> views) =
      _UpdateMentionedViews;
  const factory AIPromptInputEvent.clearMetadata() = _ClearMetadata;
  const factory AIPromptInputEvent.updatePromptId(String promptId) =
      _UpdatePromptId;
  // PonyNotes: 深度思考开关
  const factory AIPromptInputEvent.toggleDeepThinking() = _ToggleDeepThinking;
  // PonyNotes: 联网搜索开关
  const factory AIPromptInputEvent.toggleWebSearch() = _ToggleWebSearch;
}

@freezed
class AIPromptInputState with _$AIPromptInputState {
  const factory AIPromptInputState({
    required AIModelState modelState,
    required bool supportChatWithFile,
    required bool showPredefinedFormats,
    required PredefinedFormat? predefinedFormat,
    required List<ChatFile> attachedFiles,
    required List<ViewPB> mentionedPages,
    // PonyNotes: 深度思考开关
    required bool enableDeepThinking,
    // PonyNotes: 联网搜索开关
    required bool enableWebSearch,
  }) = _AIPromptInputState;

  factory AIPromptInputState.initial(PredefinedFormat? format) =>
      AIPromptInputState(
        modelState: AIModelState(
          type: AiType.cloud,
          isEditable: true,
          hintText: '',
          localAIEnabled: false,
          tooltip: null,
        ),
        supportChatWithFile: false,
        showPredefinedFormats: format != null,
        predefinedFormat: format,
        attachedFiles: [],
        mentionedPages: [],
        // PonyNotes: 默认关闭深度思考和联网搜索
        enableDeepThinking: false,
        enableWebSearch: false,
      );
}
