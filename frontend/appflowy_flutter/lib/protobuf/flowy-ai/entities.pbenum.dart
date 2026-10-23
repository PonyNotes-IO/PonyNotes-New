//
//  Generated code. Do not modify.
//  source: entities.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class ContextLoaderTypePB extends $pb.ProtobufEnum {
  static const ContextLoaderTypePB UnknownLoaderType = ContextLoaderTypePB._(0, _omitEnumNames ? '' : 'UnknownLoaderType');
  static const ContextLoaderTypePB Txt = ContextLoaderTypePB._(1, _omitEnumNames ? '' : 'Txt');
  static const ContextLoaderTypePB Markdown = ContextLoaderTypePB._(2, _omitEnumNames ? '' : 'Markdown');
  static const ContextLoaderTypePB PDF = ContextLoaderTypePB._(3, _omitEnumNames ? '' : 'PDF');

  static const $core.List<ContextLoaderTypePB> values = <ContextLoaderTypePB> [
    UnknownLoaderType,
    Txt,
    Markdown,
    PDF,
  ];

  static final $core.Map<$core.int, ContextLoaderTypePB> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ContextLoaderTypePB? valueOf($core.int value) => _byValue[value];

  const ContextLoaderTypePB._($core.int v, $core.String n) : super(v, n);
}

class ChatMessageTypePB extends $pb.ProtobufEnum {
  static const ChatMessageTypePB System = ChatMessageTypePB._(0, _omitEnumNames ? '' : 'System');
  static const ChatMessageTypePB User = ChatMessageTypePB._(1, _omitEnumNames ? '' : 'User');

  static const $core.List<ChatMessageTypePB> values = <ChatMessageTypePB> [
    System,
    User,
  ];

  static final $core.Map<$core.int, ChatMessageTypePB> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ChatMessageTypePB? valueOf($core.int value) => _byValue[value];

  const ChatMessageTypePB._($core.int v, $core.String n) : super(v, n);
}

class CompletionTypePB extends $pb.ProtobufEnum {
  static const CompletionTypePB UserQuestion = CompletionTypePB._(0, _omitEnumNames ? '' : 'UserQuestion');
  static const CompletionTypePB ExplainSelected = CompletionTypePB._(1, _omitEnumNames ? '' : 'ExplainSelected');
  static const CompletionTypePB ContinueWriting = CompletionTypePB._(2, _omitEnumNames ? '' : 'ContinueWriting');
  static const CompletionTypePB SpellingAndGrammar = CompletionTypePB._(3, _omitEnumNames ? '' : 'SpellingAndGrammar');
  static const CompletionTypePB ImproveWriting = CompletionTypePB._(4, _omitEnumNames ? '' : 'ImproveWriting');
  static const CompletionTypePB MakeShorter = CompletionTypePB._(5, _omitEnumNames ? '' : 'MakeShorter');
  static const CompletionTypePB MakeLonger = CompletionTypePB._(6, _omitEnumNames ? '' : 'MakeLonger');
  static const CompletionTypePB CustomPrompt = CompletionTypePB._(7, _omitEnumNames ? '' : 'CustomPrompt');

  static const $core.List<CompletionTypePB> values = <CompletionTypePB> [
    UserQuestion,
    ExplainSelected,
    ContinueWriting,
    SpellingAndGrammar,
    ImproveWriting,
    MakeShorter,
    MakeLonger,
    CustomPrompt,
  ];

  static final $core.Map<$core.int, CompletionTypePB> _byValue = $pb.ProtobufEnum.initByValue(values);
  static CompletionTypePB? valueOf($core.int value) => _byValue[value];

  const CompletionTypePB._($core.int v, $core.String n) : super(v, n);
}

class ModelTypePB extends $pb.ProtobufEnum {
  static const ModelTypePB LocalAI = ModelTypePB._(0, _omitEnumNames ? '' : 'LocalAI');
  static const ModelTypePB RemoteAI = ModelTypePB._(1, _omitEnumNames ? '' : 'RemoteAI');

  static const $core.List<ModelTypePB> values = <ModelTypePB> [
    LocalAI,
    RemoteAI,
  ];

  static final $core.Map<$core.int, ModelTypePB> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelTypePB? valueOf($core.int value) => _byValue[value];

  const ModelTypePB._($core.int v, $core.String n) : super(v, n);
}

class PendingResourceTypePB extends $pb.ProtobufEnum {
  static const PendingResourceTypePB LocalAIAppRes = PendingResourceTypePB._(0, _omitEnumNames ? '' : 'LocalAIAppRes');
  static const PendingResourceTypePB ModelRes = PendingResourceTypePB._(1, _omitEnumNames ? '' : 'ModelRes');

  static const $core.List<PendingResourceTypePB> values = <PendingResourceTypePB> [
    LocalAIAppRes,
    ModelRes,
  ];

  static final $core.Map<$core.int, PendingResourceTypePB> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PendingResourceTypePB? valueOf($core.int value) => _byValue[value];

  const PendingResourceTypePB._($core.int v, $core.String n) : super(v, n);
}

class RunningStatePB extends $pb.ProtobufEnum {
  static const RunningStatePB ReadyToRun = RunningStatePB._(0, _omitEnumNames ? '' : 'ReadyToRun');
  static const RunningStatePB Connecting = RunningStatePB._(1, _omitEnumNames ? '' : 'Connecting');
  static const RunningStatePB Connected = RunningStatePB._(2, _omitEnumNames ? '' : 'Connected');
  static const RunningStatePB Running = RunningStatePB._(3, _omitEnumNames ? '' : 'Running');
  static const RunningStatePB Stopped = RunningStatePB._(4, _omitEnumNames ? '' : 'Stopped');

  static const $core.List<RunningStatePB> values = <RunningStatePB> [
    ReadyToRun,
    Connecting,
    Connected,
    Running,
    Stopped,
  ];

  static final $core.Map<$core.int, RunningStatePB> _byValue = $pb.ProtobufEnum.initByValue(values);
  static RunningStatePB? valueOf($core.int value) => _byValue[value];

  const RunningStatePB._($core.int v, $core.String n) : super(v, n);
}

class ResponseImageFormatPB extends $pb.ProtobufEnum {
  static const ResponseImageFormatPB TextOnly = ResponseImageFormatPB._(0, _omitEnumNames ? '' : 'TextOnly');
  static const ResponseImageFormatPB ImageOnly = ResponseImageFormatPB._(1, _omitEnumNames ? '' : 'ImageOnly');
  static const ResponseImageFormatPB TextAndImage = ResponseImageFormatPB._(2, _omitEnumNames ? '' : 'TextAndImage');

  static const $core.List<ResponseImageFormatPB> values = <ResponseImageFormatPB> [
    TextOnly,
    ImageOnly,
    TextAndImage,
  ];

  static final $core.Map<$core.int, ResponseImageFormatPB> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ResponseImageFormatPB? valueOf($core.int value) => _byValue[value];

  const ResponseImageFormatPB._($core.int v, $core.String n) : super(v, n);
}

class ResponseTextFormatPB extends $pb.ProtobufEnum {
  static const ResponseTextFormatPB Paragraph = ResponseTextFormatPB._(0, _omitEnumNames ? '' : 'Paragraph');
  static const ResponseTextFormatPB BulletedList = ResponseTextFormatPB._(1, _omitEnumNames ? '' : 'BulletedList');
  static const ResponseTextFormatPB NumberedList = ResponseTextFormatPB._(2, _omitEnumNames ? '' : 'NumberedList');
  static const ResponseTextFormatPB Table = ResponseTextFormatPB._(3, _omitEnumNames ? '' : 'Table');

  static const $core.List<ResponseTextFormatPB> values = <ResponseTextFormatPB> [
    Paragraph,
    BulletedList,
    NumberedList,
    Table,
  ];

  static final $core.Map<$core.int, ResponseTextFormatPB> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ResponseTextFormatPB? valueOf($core.int value) => _byValue[value];

  const ResponseTextFormatPB._($core.int v, $core.String n) : super(v, n);
}

class LackOfAIResourceTypePB extends $pb.ProtobufEnum {
  static const LackOfAIResourceTypePB PluginExecutableNotReady = LackOfAIResourceTypePB._(0, _omitEnumNames ? '' : 'PluginExecutableNotReady');
  static const LackOfAIResourceTypePB OllamaServerNotReady = LackOfAIResourceTypePB._(1, _omitEnumNames ? '' : 'OllamaServerNotReady');
  static const LackOfAIResourceTypePB MissingModel = LackOfAIResourceTypePB._(2, _omitEnumNames ? '' : 'MissingModel');

  static const $core.List<LackOfAIResourceTypePB> values = <LackOfAIResourceTypePB> [
    PluginExecutableNotReady,
    OllamaServerNotReady,
    MissingModel,
  ];

  static final $core.Map<$core.int, LackOfAIResourceTypePB> _byValue = $pb.ProtobufEnum.initByValue(values);
  static LackOfAIResourceTypePB? valueOf($core.int value) => _byValue[value];

  const LackOfAIResourceTypePB._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
