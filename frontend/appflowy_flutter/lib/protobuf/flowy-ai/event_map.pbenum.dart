//
//  Generated code. Do not modify.
//  source: event_map.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class AIEvent extends $pb.ProtobufEnum {
  static const AIEvent LoadPrevMessage = AIEvent._(0, _omitEnumNames ? '' : 'LoadPrevMessage');
  static const AIEvent LoadNextMessage = AIEvent._(1, _omitEnumNames ? '' : 'LoadNextMessage');
  static const AIEvent StreamMessage = AIEvent._(2, _omitEnumNames ? '' : 'StreamMessage');
  static const AIEvent StopStream = AIEvent._(3, _omitEnumNames ? '' : 'StopStream');
  static const AIEvent GetRelatedQuestion = AIEvent._(4, _omitEnumNames ? '' : 'GetRelatedQuestion');
  static const AIEvent GetAnswerForQuestion = AIEvent._(5, _omitEnumNames ? '' : 'GetAnswerForQuestion');
  static const AIEvent CompleteText = AIEvent._(9, _omitEnumNames ? '' : 'CompleteText');
  static const AIEvent StopCompleteText = AIEvent._(10, _omitEnumNames ? '' : 'StopCompleteText');
  static const AIEvent ChatWithFile = AIEvent._(11, _omitEnumNames ? '' : 'ChatWithFile');
  static const AIEvent RestartLocalAI = AIEvent._(17, _omitEnumNames ? '' : 'RestartLocalAI');
  static const AIEvent ToggleLocalAI = AIEvent._(18, _omitEnumNames ? '' : 'ToggleLocalAI');
  static const AIEvent GetLocalAIState = AIEvent._(19, _omitEnumNames ? '' : 'GetLocalAIState');
  static const AIEvent CreateChatContext = AIEvent._(23, _omitEnumNames ? '' : 'CreateChatContext');
  static const AIEvent GetChatInfo = AIEvent._(24, _omitEnumNames ? '' : 'GetChatInfo');
  static const AIEvent GetChatSettings = AIEvent._(25, _omitEnumNames ? '' : 'GetChatSettings');
  static const AIEvent UpdateChatSettings = AIEvent._(26, _omitEnumNames ? '' : 'UpdateChatSettings');
  static const AIEvent RegenerateResponse = AIEvent._(27, _omitEnumNames ? '' : 'RegenerateResponse');
  static const AIEvent GetLocalAISetting = AIEvent._(29, _omitEnumNames ? '' : 'GetLocalAISetting');
  static const AIEvent UpdateLocalAISetting = AIEvent._(30, _omitEnumNames ? '' : 'UpdateLocalAISetting');
  static const AIEvent GetSettingModelSelection = AIEvent._(31, _omitEnumNames ? '' : 'GetSettingModelSelection');
  static const AIEvent UpdateSelectedModel = AIEvent._(32, _omitEnumNames ? '' : 'UpdateSelectedModel');
  static const AIEvent GetLocalModelSelection = AIEvent._(33, _omitEnumNames ? '' : 'GetLocalModelSelection');
  static const AIEvent GetSourceModelSelection = AIEvent._(34, _omitEnumNames ? '' : 'GetSourceModelSelection');
  static const AIEvent GetCustomPromptDatabaseConfiguration = AIEvent._(35, _omitEnumNames ? '' : 'GetCustomPromptDatabaseConfiguration');
  static const AIEvent SetCustomPromptDatabaseConfiguration = AIEvent._(36, _omitEnumNames ? '' : 'SetCustomPromptDatabaseConfiguration');

  static const $core.List<AIEvent> values = <AIEvent> [
    LoadPrevMessage,
    LoadNextMessage,
    StreamMessage,
    StopStream,
    GetRelatedQuestion,
    GetAnswerForQuestion,
    CompleteText,
    StopCompleteText,
    ChatWithFile,
    RestartLocalAI,
    ToggleLocalAI,
    GetLocalAIState,
    CreateChatContext,
    GetChatInfo,
    GetChatSettings,
    UpdateChatSettings,
    RegenerateResponse,
    GetLocalAISetting,
    UpdateLocalAISetting,
    GetSettingModelSelection,
    UpdateSelectedModel,
    GetLocalModelSelection,
    GetSourceModelSelection,
    GetCustomPromptDatabaseConfiguration,
    SetCustomPromptDatabaseConfiguration,
  ];

  static final $core.Map<$core.int, AIEvent> _byValue = $pb.ProtobufEnum.initByValue(values);
  static AIEvent? valueOf($core.int value) => _byValue[value];

  const AIEvent._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
