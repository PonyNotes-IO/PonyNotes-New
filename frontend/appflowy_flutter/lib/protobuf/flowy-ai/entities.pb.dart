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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'entities.pbenum.dart';

export 'entities.pbenum.dart';

class ChatId extends $pb.GeneratedMessage {
  factory ChatId({
    $core.String? value,
  }) {
    final $result = create();
    if (value != null) {
      $result.value = value;
    }
    return $result;
  }
  ChatId._() : super();
  factory ChatId.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatId.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatId', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatId clone() => ChatId()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatId copyWith(void Function(ChatId) updates) => super.copyWith((message) => updates(message as ChatId)) as ChatId;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatId create() => ChatId._();
  ChatId createEmptyInstance() => create();
  static $pb.PbList<ChatId> createRepeated() => $pb.PbList<ChatId>();
  @$core.pragma('dart2js:noInline')
  static ChatId getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatId>(create);
  static ChatId? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get value => $_getSZ(0);
  @$pb.TagNumber(1)
  set value($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearValue() => clearField(1);
}

class ChatInfoPB extends $pb.GeneratedMessage {
  factory ChatInfoPB({
    $core.String? chatId,
    $core.Iterable<FilePB>? files,
  }) {
    final $result = create();
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (files != null) {
      $result.files.addAll(files);
    }
    return $result;
  }
  ChatInfoPB._() : super();
  factory ChatInfoPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatInfoPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatInfoPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'chatId')
    ..pc<FilePB>(2, _omitFieldNames ? '' : 'files', $pb.PbFieldType.PM, subBuilder: FilePB.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatInfoPB clone() => ChatInfoPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatInfoPB copyWith(void Function(ChatInfoPB) updates) => super.copyWith((message) => updates(message as ChatInfoPB)) as ChatInfoPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatInfoPB create() => ChatInfoPB._();
  ChatInfoPB createEmptyInstance() => create();
  static $pb.PbList<ChatInfoPB> createRepeated() => $pb.PbList<ChatInfoPB>();
  @$core.pragma('dart2js:noInline')
  static ChatInfoPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatInfoPB>(create);
  static ChatInfoPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chatId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chatId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChatId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<FilePB> get files => $_getList(1);
}

class FilePB extends $pb.GeneratedMessage {
  factory FilePB({
    $core.String? id,
    $core.String? name,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (name != null) {
      $result.name = name;
    }
    return $result;
  }
  FilePB._() : super();
  factory FilePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FilePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FilePB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FilePB clone() => FilePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FilePB copyWith(void Function(FilePB) updates) => super.copyWith((message) => updates(message as FilePB)) as FilePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FilePB create() => FilePB._();
  FilePB createEmptyInstance() => create();
  static $pb.PbList<FilePB> createRepeated() => $pb.PbList<FilePB>();
  @$core.pragma('dart2js:noInline')
  static FilePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FilePB>(create);
  static FilePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);
}

class SendChatPayloadPB extends $pb.GeneratedMessage {
  factory SendChatPayloadPB({
    $core.String? chatId,
    $core.String? message,
    ChatMessageTypePB? messageType,
  }) {
    final $result = create();
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (message != null) {
      $result.message = message;
    }
    if (messageType != null) {
      $result.messageType = messageType;
    }
    return $result;
  }
  SendChatPayloadPB._() : super();
  factory SendChatPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SendChatPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SendChatPayloadPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'chatId')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..e<ChatMessageTypePB>(3, _omitFieldNames ? '' : 'messageType', $pb.PbFieldType.OE, defaultOrMaker: ChatMessageTypePB.System, valueOf: ChatMessageTypePB.valueOf, enumValues: ChatMessageTypePB.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SendChatPayloadPB clone() => SendChatPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SendChatPayloadPB copyWith(void Function(SendChatPayloadPB) updates) => super.copyWith((message) => updates(message as SendChatPayloadPB)) as SendChatPayloadPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SendChatPayloadPB create() => SendChatPayloadPB._();
  SendChatPayloadPB createEmptyInstance() => create();
  static $pb.PbList<SendChatPayloadPB> createRepeated() => $pb.PbList<SendChatPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static SendChatPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SendChatPayloadPB>(create);
  static SendChatPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chatId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chatId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChatId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => clearField(2);

  @$pb.TagNumber(3)
  ChatMessageTypePB get messageType => $_getN(2);
  @$pb.TagNumber(3)
  set messageType(ChatMessageTypePB v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasMessageType() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessageType() => clearField(3);
}

enum StreamChatPayloadPB_OneOfFormat {
  format, 
  notSet
}

enum StreamChatPayloadPB_OneOfPromptId {
  promptId, 
  notSet
}

enum StreamChatPayloadPB_OneOfModel {
  model, 
  notSet
}

class StreamChatPayloadPB extends $pb.GeneratedMessage {
  factory StreamChatPayloadPB({
    $core.String? chatId,
    $core.String? message,
    ChatMessageTypePB? messageType,
    $fixnum.Int64? answerStreamPort,
    $fixnum.Int64? questionStreamPort,
    PredefinedFormatPB? format,
    $core.String? promptId,
    AIModelPB? model,
    $core.bool? enableThinking,
    $core.bool? enableWebSearch,
    $core.Iterable<$core.String>? images,
    $core.bool? hasImages,
  }) {
    final $result = create();
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (message != null) {
      $result.message = message;
    }
    if (messageType != null) {
      $result.messageType = messageType;
    }
    if (answerStreamPort != null) {
      $result.answerStreamPort = answerStreamPort;
    }
    if (questionStreamPort != null) {
      $result.questionStreamPort = questionStreamPort;
    }
    if (format != null) {
      $result.format = format;
    }
    if (promptId != null) {
      $result.promptId = promptId;
    }
    if (model != null) {
      $result.model = model;
    }
    if (enableThinking != null) {
      $result.enableThinking = enableThinking;
    }
    if (enableWebSearch != null) {
      $result.enableWebSearch = enableWebSearch;
    }
    if (images != null) {
      $result.images.addAll(images);
    }
    if (hasImages != null) {
      $result.hasImages = hasImages;
    }
    return $result;
  }
  StreamChatPayloadPB._() : super();
  factory StreamChatPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StreamChatPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, StreamChatPayloadPB_OneOfFormat> _StreamChatPayloadPB_OneOfFormatByTag = {
    6 : StreamChatPayloadPB_OneOfFormat.format,
    0 : StreamChatPayloadPB_OneOfFormat.notSet
  };
  static const $core.Map<$core.int, StreamChatPayloadPB_OneOfPromptId> _StreamChatPayloadPB_OneOfPromptIdByTag = {
    7 : StreamChatPayloadPB_OneOfPromptId.promptId,
    0 : StreamChatPayloadPB_OneOfPromptId.notSet
  };
  static const $core.Map<$core.int, StreamChatPayloadPB_OneOfModel> _StreamChatPayloadPB_OneOfModelByTag = {
    8 : StreamChatPayloadPB_OneOfModel.model,
    0 : StreamChatPayloadPB_OneOfModel.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StreamChatPayloadPB', createEmptyInstance: create)
    ..oo(0, [6])
    ..oo(1, [7])
    ..oo(2, [8])
    ..aOS(1, _omitFieldNames ? '' : 'chatId')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..e<ChatMessageTypePB>(3, _omitFieldNames ? '' : 'messageType', $pb.PbFieldType.OE, defaultOrMaker: ChatMessageTypePB.System, valueOf: ChatMessageTypePB.valueOf, enumValues: ChatMessageTypePB.values)
    ..aInt64(4, _omitFieldNames ? '' : 'answerStreamPort')
    ..aInt64(5, _omitFieldNames ? '' : 'questionStreamPort')
    ..aOM<PredefinedFormatPB>(6, _omitFieldNames ? '' : 'format', subBuilder: PredefinedFormatPB.create)
    ..aOS(7, _omitFieldNames ? '' : 'promptId')
    ..aOM<AIModelPB>(8, _omitFieldNames ? '' : 'model', subBuilder: AIModelPB.create)
    ..aOB(9, _omitFieldNames ? '' : 'enableThinking')
    ..aOB(10, _omitFieldNames ? '' : 'enableWebSearch')
    ..pPS(11, _omitFieldNames ? '' : 'images')
    ..aOB(12, _omitFieldNames ? '' : 'hasImages')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StreamChatPayloadPB clone() => StreamChatPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StreamChatPayloadPB copyWith(void Function(StreamChatPayloadPB) updates) => super.copyWith((message) => updates(message as StreamChatPayloadPB)) as StreamChatPayloadPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StreamChatPayloadPB create() => StreamChatPayloadPB._();
  StreamChatPayloadPB createEmptyInstance() => create();
  static $pb.PbList<StreamChatPayloadPB> createRepeated() => $pb.PbList<StreamChatPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static StreamChatPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StreamChatPayloadPB>(create);
  static StreamChatPayloadPB? _defaultInstance;

  StreamChatPayloadPB_OneOfFormat whichOneOfFormat() => _StreamChatPayloadPB_OneOfFormatByTag[$_whichOneof(0)]!;
  void clearOneOfFormat() => clearField($_whichOneof(0));

  StreamChatPayloadPB_OneOfPromptId whichOneOfPromptId() => _StreamChatPayloadPB_OneOfPromptIdByTag[$_whichOneof(1)]!;
  void clearOneOfPromptId() => clearField($_whichOneof(1));

  StreamChatPayloadPB_OneOfModel whichOneOfModel() => _StreamChatPayloadPB_OneOfModelByTag[$_whichOneof(2)]!;
  void clearOneOfModel() => clearField($_whichOneof(2));

  @$pb.TagNumber(1)
  $core.String get chatId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chatId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChatId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => clearField(2);

  @$pb.TagNumber(3)
  ChatMessageTypePB get messageType => $_getN(2);
  @$pb.TagNumber(3)
  set messageType(ChatMessageTypePB v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasMessageType() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessageType() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get answerStreamPort => $_getI64(3);
  @$pb.TagNumber(4)
  set answerStreamPort($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAnswerStreamPort() => $_has(3);
  @$pb.TagNumber(4)
  void clearAnswerStreamPort() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get questionStreamPort => $_getI64(4);
  @$pb.TagNumber(5)
  set questionStreamPort($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasQuestionStreamPort() => $_has(4);
  @$pb.TagNumber(5)
  void clearQuestionStreamPort() => clearField(5);

  @$pb.TagNumber(6)
  PredefinedFormatPB get format => $_getN(5);
  @$pb.TagNumber(6)
  set format(PredefinedFormatPB v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasFormat() => $_has(5);
  @$pb.TagNumber(6)
  void clearFormat() => clearField(6);
  @$pb.TagNumber(6)
  PredefinedFormatPB ensureFormat() => $_ensure(5);

  @$pb.TagNumber(7)
  $core.String get promptId => $_getSZ(6);
  @$pb.TagNumber(7)
  set promptId($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasPromptId() => $_has(6);
  @$pb.TagNumber(7)
  void clearPromptId() => clearField(7);

  @$pb.TagNumber(8)
  AIModelPB get model => $_getN(7);
  @$pb.TagNumber(8)
  set model(AIModelPB v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasModel() => $_has(7);
  @$pb.TagNumber(8)
  void clearModel() => clearField(8);
  @$pb.TagNumber(8)
  AIModelPB ensureModel() => $_ensure(7);

  @$pb.TagNumber(9)
  $core.bool get enableThinking => $_getBF(8);
  @$pb.TagNumber(9)
  set enableThinking($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasEnableThinking() => $_has(8);
  @$pb.TagNumber(9)
  void clearEnableThinking() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get enableWebSearch => $_getBF(9);
  @$pb.TagNumber(10)
  set enableWebSearch($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasEnableWebSearch() => $_has(9);
  @$pb.TagNumber(10)
  void clearEnableWebSearch() => clearField(10);

  @$pb.TagNumber(11)
  $core.List<$core.String> get images => $_getList(10);

  @$pb.TagNumber(12)
  $core.bool get hasImages => $_getBF(11);
  @$pb.TagNumber(12)
  set hasImages($core.bool v) { $_setBool(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasHasImages() => $_has(11);
  @$pb.TagNumber(12)
  void clearHasImages() => clearField(12);
}

enum RegenerateResponsePB_OneOfFormat {
  format, 
  notSet
}

enum RegenerateResponsePB_OneOfModel {
  model, 
  notSet
}

class RegenerateResponsePB extends $pb.GeneratedMessage {
  factory RegenerateResponsePB({
    $core.String? chatId,
    $fixnum.Int64? answerMessageId,
    $fixnum.Int64? answerStreamPort,
    PredefinedFormatPB? format,
    AIModelPB? model,
  }) {
    final $result = create();
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (answerMessageId != null) {
      $result.answerMessageId = answerMessageId;
    }
    if (answerStreamPort != null) {
      $result.answerStreamPort = answerStreamPort;
    }
    if (format != null) {
      $result.format = format;
    }
    if (model != null) {
      $result.model = model;
    }
    return $result;
  }
  RegenerateResponsePB._() : super();
  factory RegenerateResponsePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RegenerateResponsePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, RegenerateResponsePB_OneOfFormat> _RegenerateResponsePB_OneOfFormatByTag = {
    4 : RegenerateResponsePB_OneOfFormat.format,
    0 : RegenerateResponsePB_OneOfFormat.notSet
  };
  static const $core.Map<$core.int, RegenerateResponsePB_OneOfModel> _RegenerateResponsePB_OneOfModelByTag = {
    5 : RegenerateResponsePB_OneOfModel.model,
    0 : RegenerateResponsePB_OneOfModel.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RegenerateResponsePB', createEmptyInstance: create)
    ..oo(0, [4])
    ..oo(1, [5])
    ..aOS(1, _omitFieldNames ? '' : 'chatId')
    ..aInt64(2, _omitFieldNames ? '' : 'answerMessageId')
    ..aInt64(3, _omitFieldNames ? '' : 'answerStreamPort')
    ..aOM<PredefinedFormatPB>(4, _omitFieldNames ? '' : 'format', subBuilder: PredefinedFormatPB.create)
    ..aOM<AIModelPB>(5, _omitFieldNames ? '' : 'model', subBuilder: AIModelPB.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RegenerateResponsePB clone() => RegenerateResponsePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RegenerateResponsePB copyWith(void Function(RegenerateResponsePB) updates) => super.copyWith((message) => updates(message as RegenerateResponsePB)) as RegenerateResponsePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegenerateResponsePB create() => RegenerateResponsePB._();
  RegenerateResponsePB createEmptyInstance() => create();
  static $pb.PbList<RegenerateResponsePB> createRepeated() => $pb.PbList<RegenerateResponsePB>();
  @$core.pragma('dart2js:noInline')
  static RegenerateResponsePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RegenerateResponsePB>(create);
  static RegenerateResponsePB? _defaultInstance;

  RegenerateResponsePB_OneOfFormat whichOneOfFormat() => _RegenerateResponsePB_OneOfFormatByTag[$_whichOneof(0)]!;
  void clearOneOfFormat() => clearField($_whichOneof(0));

  RegenerateResponsePB_OneOfModel whichOneOfModel() => _RegenerateResponsePB_OneOfModelByTag[$_whichOneof(1)]!;
  void clearOneOfModel() => clearField($_whichOneof(1));

  @$pb.TagNumber(1)
  $core.String get chatId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chatId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChatId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get answerMessageId => $_getI64(1);
  @$pb.TagNumber(2)
  set answerMessageId($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAnswerMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAnswerMessageId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get answerStreamPort => $_getI64(2);
  @$pb.TagNumber(3)
  set answerStreamPort($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAnswerStreamPort() => $_has(2);
  @$pb.TagNumber(3)
  void clearAnswerStreamPort() => clearField(3);

  @$pb.TagNumber(4)
  PredefinedFormatPB get format => $_getN(3);
  @$pb.TagNumber(4)
  set format(PredefinedFormatPB v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasFormat() => $_has(3);
  @$pb.TagNumber(4)
  void clearFormat() => clearField(4);
  @$pb.TagNumber(4)
  PredefinedFormatPB ensureFormat() => $_ensure(3);

  @$pb.TagNumber(5)
  AIModelPB get model => $_getN(4);
  @$pb.TagNumber(5)
  set model(AIModelPB v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasModel() => $_has(4);
  @$pb.TagNumber(5)
  void clearModel() => clearField(5);
  @$pb.TagNumber(5)
  AIModelPB ensureModel() => $_ensure(4);
}

class ChatMessageMetaPB extends $pb.GeneratedMessage {
  factory ChatMessageMetaPB({
    $core.String? id,
    $core.String? name,
    $core.String? data,
    ContextLoaderTypePB? loaderType,
    $core.String? source,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (name != null) {
      $result.name = name;
    }
    if (data != null) {
      $result.data = data;
    }
    if (loaderType != null) {
      $result.loaderType = loaderType;
    }
    if (source != null) {
      $result.source = source;
    }
    return $result;
  }
  ChatMessageMetaPB._() : super();
  factory ChatMessageMetaPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatMessageMetaPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatMessageMetaPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'data')
    ..e<ContextLoaderTypePB>(4, _omitFieldNames ? '' : 'loaderType', $pb.PbFieldType.OE, defaultOrMaker: ContextLoaderTypePB.UnknownLoaderType, valueOf: ContextLoaderTypePB.valueOf, enumValues: ContextLoaderTypePB.values)
    ..aOS(5, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatMessageMetaPB clone() => ChatMessageMetaPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatMessageMetaPB copyWith(void Function(ChatMessageMetaPB) updates) => super.copyWith((message) => updates(message as ChatMessageMetaPB)) as ChatMessageMetaPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatMessageMetaPB create() => ChatMessageMetaPB._();
  ChatMessageMetaPB createEmptyInstance() => create();
  static $pb.PbList<ChatMessageMetaPB> createRepeated() => $pb.PbList<ChatMessageMetaPB>();
  @$core.pragma('dart2js:noInline')
  static ChatMessageMetaPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatMessageMetaPB>(create);
  static ChatMessageMetaPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get data => $_getSZ(2);
  @$pb.TagNumber(3)
  set data($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasData() => $_has(2);
  @$pb.TagNumber(3)
  void clearData() => clearField(3);

  @$pb.TagNumber(4)
  ContextLoaderTypePB get loaderType => $_getN(3);
  @$pb.TagNumber(4)
  set loaderType(ContextLoaderTypePB v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasLoaderType() => $_has(3);
  @$pb.TagNumber(4)
  void clearLoaderType() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get source => $_getSZ(4);
  @$pb.TagNumber(5)
  set source($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSource() => $_has(4);
  @$pb.TagNumber(5)
  void clearSource() => clearField(5);
}

class StopStreamPB extends $pb.GeneratedMessage {
  factory StopStreamPB({
    $core.String? chatId,
  }) {
    final $result = create();
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  StopStreamPB._() : super();
  factory StopStreamPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StopStreamPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StopStreamPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StopStreamPB clone() => StopStreamPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StopStreamPB copyWith(void Function(StopStreamPB) updates) => super.copyWith((message) => updates(message as StopStreamPB)) as StopStreamPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StopStreamPB create() => StopStreamPB._();
  StopStreamPB createEmptyInstance() => create();
  static $pb.PbList<StopStreamPB> createRepeated() => $pb.PbList<StopStreamPB>();
  @$core.pragma('dart2js:noInline')
  static StopStreamPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StopStreamPB>(create);
  static StopStreamPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chatId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chatId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChatId() => clearField(1);
}

enum LoadPrevChatMessagePB_OneOfBeforeMessageId {
  beforeMessageId, 
  notSet
}

class LoadPrevChatMessagePB extends $pb.GeneratedMessage {
  factory LoadPrevChatMessagePB({
    $core.String? chatId,
    $fixnum.Int64? limit,
    $fixnum.Int64? beforeMessageId,
  }) {
    final $result = create();
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (limit != null) {
      $result.limit = limit;
    }
    if (beforeMessageId != null) {
      $result.beforeMessageId = beforeMessageId;
    }
    return $result;
  }
  LoadPrevChatMessagePB._() : super();
  factory LoadPrevChatMessagePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoadPrevChatMessagePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, LoadPrevChatMessagePB_OneOfBeforeMessageId> _LoadPrevChatMessagePB_OneOfBeforeMessageIdByTag = {
    4 : LoadPrevChatMessagePB_OneOfBeforeMessageId.beforeMessageId,
    0 : LoadPrevChatMessagePB_OneOfBeforeMessageId.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoadPrevChatMessagePB', createEmptyInstance: create)
    ..oo(0, [4])
    ..aOS(1, _omitFieldNames ? '' : 'chatId')
    ..aInt64(2, _omitFieldNames ? '' : 'limit')
    ..aInt64(4, _omitFieldNames ? '' : 'beforeMessageId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoadPrevChatMessagePB clone() => LoadPrevChatMessagePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoadPrevChatMessagePB copyWith(void Function(LoadPrevChatMessagePB) updates) => super.copyWith((message) => updates(message as LoadPrevChatMessagePB)) as LoadPrevChatMessagePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoadPrevChatMessagePB create() => LoadPrevChatMessagePB._();
  LoadPrevChatMessagePB createEmptyInstance() => create();
  static $pb.PbList<LoadPrevChatMessagePB> createRepeated() => $pb.PbList<LoadPrevChatMessagePB>();
  @$core.pragma('dart2js:noInline')
  static LoadPrevChatMessagePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoadPrevChatMessagePB>(create);
  static LoadPrevChatMessagePB? _defaultInstance;

  LoadPrevChatMessagePB_OneOfBeforeMessageId whichOneOfBeforeMessageId() => _LoadPrevChatMessagePB_OneOfBeforeMessageIdByTag[$_whichOneof(0)]!;
  void clearOneOfBeforeMessageId() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get chatId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chatId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChatId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get limit => $_getI64(1);
  @$pb.TagNumber(2)
  set limit($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => clearField(2);

  @$pb.TagNumber(4)
  $fixnum.Int64 get beforeMessageId => $_getI64(2);
  @$pb.TagNumber(4)
  set beforeMessageId($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(4)
  $core.bool hasBeforeMessageId() => $_has(2);
  @$pb.TagNumber(4)
  void clearBeforeMessageId() => clearField(4);
}

enum LoadNextChatMessagePB_OneOfAfterMessageId {
  afterMessageId, 
  notSet
}

class LoadNextChatMessagePB extends $pb.GeneratedMessage {
  factory LoadNextChatMessagePB({
    $core.String? chatId,
    $fixnum.Int64? limit,
    $fixnum.Int64? afterMessageId,
  }) {
    final $result = create();
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (limit != null) {
      $result.limit = limit;
    }
    if (afterMessageId != null) {
      $result.afterMessageId = afterMessageId;
    }
    return $result;
  }
  LoadNextChatMessagePB._() : super();
  factory LoadNextChatMessagePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoadNextChatMessagePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, LoadNextChatMessagePB_OneOfAfterMessageId> _LoadNextChatMessagePB_OneOfAfterMessageIdByTag = {
    4 : LoadNextChatMessagePB_OneOfAfterMessageId.afterMessageId,
    0 : LoadNextChatMessagePB_OneOfAfterMessageId.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoadNextChatMessagePB', createEmptyInstance: create)
    ..oo(0, [4])
    ..aOS(1, _omitFieldNames ? '' : 'chatId')
    ..aInt64(2, _omitFieldNames ? '' : 'limit')
    ..aInt64(4, _omitFieldNames ? '' : 'afterMessageId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoadNextChatMessagePB clone() => LoadNextChatMessagePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoadNextChatMessagePB copyWith(void Function(LoadNextChatMessagePB) updates) => super.copyWith((message) => updates(message as LoadNextChatMessagePB)) as LoadNextChatMessagePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoadNextChatMessagePB create() => LoadNextChatMessagePB._();
  LoadNextChatMessagePB createEmptyInstance() => create();
  static $pb.PbList<LoadNextChatMessagePB> createRepeated() => $pb.PbList<LoadNextChatMessagePB>();
  @$core.pragma('dart2js:noInline')
  static LoadNextChatMessagePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoadNextChatMessagePB>(create);
  static LoadNextChatMessagePB? _defaultInstance;

  LoadNextChatMessagePB_OneOfAfterMessageId whichOneOfAfterMessageId() => _LoadNextChatMessagePB_OneOfAfterMessageIdByTag[$_whichOneof(0)]!;
  void clearOneOfAfterMessageId() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get chatId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chatId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChatId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get limit => $_getI64(1);
  @$pb.TagNumber(2)
  set limit($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => clearField(2);

  @$pb.TagNumber(4)
  $fixnum.Int64 get afterMessageId => $_getI64(2);
  @$pb.TagNumber(4)
  set afterMessageId($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(4)
  $core.bool hasAfterMessageId() => $_has(2);
  @$pb.TagNumber(4)
  void clearAfterMessageId() => clearField(4);
}

class ChatMessageListPB extends $pb.GeneratedMessage {
  factory ChatMessageListPB({
    $core.bool? hasMore,
    $core.Iterable<ChatMessagePB>? messages,
    $fixnum.Int64? total,
  }) {
    final $result = create();
    if (hasMore != null) {
      $result.hasMore = hasMore;
    }
    if (messages != null) {
      $result.messages.addAll(messages);
    }
    if (total != null) {
      $result.total = total;
    }
    return $result;
  }
  ChatMessageListPB._() : super();
  factory ChatMessageListPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatMessageListPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatMessageListPB', createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'hasMore')
    ..pc<ChatMessagePB>(2, _omitFieldNames ? '' : 'messages', $pb.PbFieldType.PM, subBuilder: ChatMessagePB.create)
    ..aInt64(3, _omitFieldNames ? '' : 'total')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatMessageListPB clone() => ChatMessageListPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatMessageListPB copyWith(void Function(ChatMessageListPB) updates) => super.copyWith((message) => updates(message as ChatMessageListPB)) as ChatMessageListPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatMessageListPB create() => ChatMessageListPB._();
  ChatMessageListPB createEmptyInstance() => create();
  static $pb.PbList<ChatMessageListPB> createRepeated() => $pb.PbList<ChatMessageListPB>();
  @$core.pragma('dart2js:noInline')
  static ChatMessageListPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatMessageListPB>(create);
  static ChatMessageListPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get hasMore => $_getBF(0);
  @$pb.TagNumber(1)
  set hasMore($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasHasMore() => $_has(0);
  @$pb.TagNumber(1)
  void clearHasMore() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<ChatMessagePB> get messages => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get total => $_getI64(2);
  @$pb.TagNumber(3)
  set total($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTotal() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotal() => clearField(3);
}

class ServerModelSelectionPB extends $pb.GeneratedMessage {
  factory ServerModelSelectionPB({
    $core.Iterable<AvailableModelPB>? models,
  }) {
    final $result = create();
    if (models != null) {
      $result.models.addAll(models);
    }
    return $result;
  }
  ServerModelSelectionPB._() : super();
  factory ServerModelSelectionPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ServerModelSelectionPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ServerModelSelectionPB', createEmptyInstance: create)
    ..pc<AvailableModelPB>(1, _omitFieldNames ? '' : 'models', $pb.PbFieldType.PM, subBuilder: AvailableModelPB.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ServerModelSelectionPB clone() => ServerModelSelectionPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ServerModelSelectionPB copyWith(void Function(ServerModelSelectionPB) updates) => super.copyWith((message) => updates(message as ServerModelSelectionPB)) as ServerModelSelectionPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ServerModelSelectionPB create() => ServerModelSelectionPB._();
  ServerModelSelectionPB createEmptyInstance() => create();
  static $pb.PbList<ServerModelSelectionPB> createRepeated() => $pb.PbList<ServerModelSelectionPB>();
  @$core.pragma('dart2js:noInline')
  static ServerModelSelectionPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ServerModelSelectionPB>(create);
  static ServerModelSelectionPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<AvailableModelPB> get models => $_getList(0);
}

class AvailableModelPB extends $pb.GeneratedMessage {
  factory AvailableModelPB({
    $core.String? name,
    $core.bool? isDefault,
    $core.String? desc,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (isDefault != null) {
      $result.isDefault = isDefault;
    }
    if (desc != null) {
      $result.desc = desc;
    }
    return $result;
  }
  AvailableModelPB._() : super();
  factory AvailableModelPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AvailableModelPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AvailableModelPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOB(2, _omitFieldNames ? '' : 'isDefault')
    ..aOS(3, _omitFieldNames ? '' : 'desc')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AvailableModelPB clone() => AvailableModelPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AvailableModelPB copyWith(void Function(AvailableModelPB) updates) => super.copyWith((message) => updates(message as AvailableModelPB)) as AvailableModelPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AvailableModelPB create() => AvailableModelPB._();
  AvailableModelPB createEmptyInstance() => create();
  static $pb.PbList<AvailableModelPB> createRepeated() => $pb.PbList<AvailableModelPB>();
  @$core.pragma('dart2js:noInline')
  static AvailableModelPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AvailableModelPB>(create);
  static AvailableModelPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isDefault => $_getBF(1);
  @$pb.TagNumber(2)
  set isDefault($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIsDefault() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsDefault() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get desc => $_getSZ(2);
  @$pb.TagNumber(3)
  set desc($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDesc() => $_has(2);
  @$pb.TagNumber(3)
  void clearDesc() => clearField(3);
}

class ModelSourcePB extends $pb.GeneratedMessage {
  factory ModelSourcePB({
    $core.String? source,
  }) {
    final $result = create();
    if (source != null) {
      $result.source = source;
    }
    return $result;
  }
  ModelSourcePB._() : super();
  factory ModelSourcePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelSourcePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelSourcePB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelSourcePB clone() => ModelSourcePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelSourcePB copyWith(void Function(ModelSourcePB) updates) => super.copyWith((message) => updates(message as ModelSourcePB)) as ModelSourcePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelSourcePB create() => ModelSourcePB._();
  ModelSourcePB createEmptyInstance() => create();
  static $pb.PbList<ModelSourcePB> createRepeated() => $pb.PbList<ModelSourcePB>();
  @$core.pragma('dart2js:noInline')
  static ModelSourcePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelSourcePB>(create);
  static ModelSourcePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => clearField(1);
}

class UpdateSelectedModelPB extends $pb.GeneratedMessage {
  factory UpdateSelectedModelPB({
    $core.String? source,
    AIModelPB? selectedModel,
  }) {
    final $result = create();
    if (source != null) {
      $result.source = source;
    }
    if (selectedModel != null) {
      $result.selectedModel = selectedModel;
    }
    return $result;
  }
  UpdateSelectedModelPB._() : super();
  factory UpdateSelectedModelPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UpdateSelectedModelPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UpdateSelectedModelPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..aOM<AIModelPB>(2, _omitFieldNames ? '' : 'selectedModel', subBuilder: AIModelPB.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UpdateSelectedModelPB clone() => UpdateSelectedModelPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UpdateSelectedModelPB copyWith(void Function(UpdateSelectedModelPB) updates) => super.copyWith((message) => updates(message as UpdateSelectedModelPB)) as UpdateSelectedModelPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateSelectedModelPB create() => UpdateSelectedModelPB._();
  UpdateSelectedModelPB createEmptyInstance() => create();
  static $pb.PbList<UpdateSelectedModelPB> createRepeated() => $pb.PbList<UpdateSelectedModelPB>();
  @$core.pragma('dart2js:noInline')
  static UpdateSelectedModelPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UpdateSelectedModelPB>(create);
  static UpdateSelectedModelPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => clearField(1);

  @$pb.TagNumber(2)
  AIModelPB get selectedModel => $_getN(1);
  @$pb.TagNumber(2)
  set selectedModel(AIModelPB v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasSelectedModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearSelectedModel() => clearField(2);
  @$pb.TagNumber(2)
  AIModelPB ensureSelectedModel() => $_ensure(1);
}

class ModelSelectionPB extends $pb.GeneratedMessage {
  factory ModelSelectionPB({
    $core.Iterable<AIModelPB>? models,
    AIModelPB? selectedModel,
  }) {
    final $result = create();
    if (models != null) {
      $result.models.addAll(models);
    }
    if (selectedModel != null) {
      $result.selectedModel = selectedModel;
    }
    return $result;
  }
  ModelSelectionPB._() : super();
  factory ModelSelectionPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelSelectionPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelSelectionPB', createEmptyInstance: create)
    ..pc<AIModelPB>(1, _omitFieldNames ? '' : 'models', $pb.PbFieldType.PM, subBuilder: AIModelPB.create)
    ..aOM<AIModelPB>(2, _omitFieldNames ? '' : 'selectedModel', subBuilder: AIModelPB.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelSelectionPB clone() => ModelSelectionPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelSelectionPB copyWith(void Function(ModelSelectionPB) updates) => super.copyWith((message) => updates(message as ModelSelectionPB)) as ModelSelectionPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelSelectionPB create() => ModelSelectionPB._();
  ModelSelectionPB createEmptyInstance() => create();
  static $pb.PbList<ModelSelectionPB> createRepeated() => $pb.PbList<ModelSelectionPB>();
  @$core.pragma('dart2js:noInline')
  static ModelSelectionPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelSelectionPB>(create);
  static ModelSelectionPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<AIModelPB> get models => $_getList(0);

  @$pb.TagNumber(2)
  AIModelPB get selectedModel => $_getN(1);
  @$pb.TagNumber(2)
  set selectedModel(AIModelPB v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasSelectedModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearSelectedModel() => clearField(2);
  @$pb.TagNumber(2)
  AIModelPB ensureSelectedModel() => $_ensure(1);
}

class RepeatedAIModelPB extends $pb.GeneratedMessage {
  factory RepeatedAIModelPB({
    $core.Iterable<AIModelPB>? items,
  }) {
    final $result = create();
    if (items != null) {
      $result.items.addAll(items);
    }
    return $result;
  }
  RepeatedAIModelPB._() : super();
  factory RepeatedAIModelPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RepeatedAIModelPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RepeatedAIModelPB', createEmptyInstance: create)
    ..pc<AIModelPB>(1, _omitFieldNames ? '' : 'items', $pb.PbFieldType.PM, subBuilder: AIModelPB.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RepeatedAIModelPB clone() => RepeatedAIModelPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RepeatedAIModelPB copyWith(void Function(RepeatedAIModelPB) updates) => super.copyWith((message) => updates(message as RepeatedAIModelPB)) as RepeatedAIModelPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RepeatedAIModelPB create() => RepeatedAIModelPB._();
  RepeatedAIModelPB createEmptyInstance() => create();
  static $pb.PbList<RepeatedAIModelPB> createRepeated() => $pb.PbList<RepeatedAIModelPB>();
  @$core.pragma('dart2js:noInline')
  static RepeatedAIModelPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepeatedAIModelPB>(create);
  static RepeatedAIModelPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<AIModelPB> get items => $_getList(0);
}

class AIModelPB extends $pb.GeneratedMessage {
  factory AIModelPB({
    $core.String? name,
    $core.bool? isLocal,
    $core.String? desc,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (isLocal != null) {
      $result.isLocal = isLocal;
    }
    if (desc != null) {
      $result.desc = desc;
    }
    return $result;
  }
  AIModelPB._() : super();
  factory AIModelPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AIModelPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AIModelPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOB(2, _omitFieldNames ? '' : 'isLocal')
    ..aOS(3, _omitFieldNames ? '' : 'desc')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AIModelPB clone() => AIModelPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AIModelPB copyWith(void Function(AIModelPB) updates) => super.copyWith((message) => updates(message as AIModelPB)) as AIModelPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AIModelPB create() => AIModelPB._();
  AIModelPB createEmptyInstance() => create();
  static $pb.PbList<AIModelPB> createRepeated() => $pb.PbList<AIModelPB>();
  @$core.pragma('dart2js:noInline')
  static AIModelPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AIModelPB>(create);
  static AIModelPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isLocal => $_getBF(1);
  @$pb.TagNumber(2)
  set isLocal($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIsLocal() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsLocal() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get desc => $_getSZ(2);
  @$pb.TagNumber(3)
  set desc($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDesc() => $_has(2);
  @$pb.TagNumber(3)
  void clearDesc() => clearField(3);
}

enum ChatMessagePB_OneOfReplyMessageId {
  replyMessageId, 
  notSet
}

enum ChatMessagePB_OneOfMetadata {
  metadata, 
  notSet
}

class ChatMessagePB extends $pb.GeneratedMessage {
  factory ChatMessagePB({
    $fixnum.Int64? messageId,
    $core.String? content,
    $fixnum.Int64? createdAt,
    $fixnum.Int64? authorType,
    $core.String? authorId,
    $fixnum.Int64? replyMessageId,
    $core.String? metadata,
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (content != null) {
      $result.content = content;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (authorType != null) {
      $result.authorType = authorType;
    }
    if (authorId != null) {
      $result.authorId = authorId;
    }
    if (replyMessageId != null) {
      $result.replyMessageId = replyMessageId;
    }
    if (metadata != null) {
      $result.metadata = metadata;
    }
    return $result;
  }
  ChatMessagePB._() : super();
  factory ChatMessagePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatMessagePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, ChatMessagePB_OneOfReplyMessageId> _ChatMessagePB_OneOfReplyMessageIdByTag = {
    6 : ChatMessagePB_OneOfReplyMessageId.replyMessageId,
    0 : ChatMessagePB_OneOfReplyMessageId.notSet
  };
  static const $core.Map<$core.int, ChatMessagePB_OneOfMetadata> _ChatMessagePB_OneOfMetadataByTag = {
    7 : ChatMessagePB_OneOfMetadata.metadata,
    0 : ChatMessagePB_OneOfMetadata.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatMessagePB', createEmptyInstance: create)
    ..oo(0, [6])
    ..oo(1, [7])
    ..aInt64(1, _omitFieldNames ? '' : 'messageId')
    ..aOS(2, _omitFieldNames ? '' : 'content')
    ..aInt64(3, _omitFieldNames ? '' : 'createdAt')
    ..aInt64(4, _omitFieldNames ? '' : 'authorType')
    ..aOS(5, _omitFieldNames ? '' : 'authorId')
    ..aInt64(6, _omitFieldNames ? '' : 'replyMessageId')
    ..aOS(7, _omitFieldNames ? '' : 'metadata')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatMessagePB clone() => ChatMessagePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatMessagePB copyWith(void Function(ChatMessagePB) updates) => super.copyWith((message) => updates(message as ChatMessagePB)) as ChatMessagePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatMessagePB create() => ChatMessagePB._();
  ChatMessagePB createEmptyInstance() => create();
  static $pb.PbList<ChatMessagePB> createRepeated() => $pb.PbList<ChatMessagePB>();
  @$core.pragma('dart2js:noInline')
  static ChatMessagePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatMessagePB>(create);
  static ChatMessagePB? _defaultInstance;

  ChatMessagePB_OneOfReplyMessageId whichOneOfReplyMessageId() => _ChatMessagePB_OneOfReplyMessageIdByTag[$_whichOneof(0)]!;
  void clearOneOfReplyMessageId() => clearField($_whichOneof(0));

  ChatMessagePB_OneOfMetadata whichOneOfMetadata() => _ChatMessagePB_OneOfMetadataByTag[$_whichOneof(1)]!;
  void clearOneOfMetadata() => clearField($_whichOneof(1));

  @$pb.TagNumber(1)
  $fixnum.Int64 get messageId => $_getI64(0);
  @$pb.TagNumber(1)
  set messageId($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get content => $_getSZ(1);
  @$pb.TagNumber(2)
  set content($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearContent() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get createdAt => $_getI64(2);
  @$pb.TagNumber(3)
  set createdAt($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCreatedAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearCreatedAt() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get authorType => $_getI64(3);
  @$pb.TagNumber(4)
  set authorType($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAuthorType() => $_has(3);
  @$pb.TagNumber(4)
  void clearAuthorType() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get authorId => $_getSZ(4);
  @$pb.TagNumber(5)
  set authorId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAuthorId() => $_has(4);
  @$pb.TagNumber(5)
  void clearAuthorId() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get replyMessageId => $_getI64(5);
  @$pb.TagNumber(6)
  set replyMessageId($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasReplyMessageId() => $_has(5);
  @$pb.TagNumber(6)
  void clearReplyMessageId() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get metadata => $_getSZ(6);
  @$pb.TagNumber(7)
  set metadata($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasMetadata() => $_has(6);
  @$pb.TagNumber(7)
  void clearMetadata() => clearField(7);
}

class ChatMessageErrorPB extends $pb.GeneratedMessage {
  factory ChatMessageErrorPB({
    $core.String? chatId,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  ChatMessageErrorPB._() : super();
  factory ChatMessageErrorPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatMessageErrorPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatMessageErrorPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'chatId')
    ..aOS(2, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatMessageErrorPB clone() => ChatMessageErrorPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatMessageErrorPB copyWith(void Function(ChatMessageErrorPB) updates) => super.copyWith((message) => updates(message as ChatMessageErrorPB)) as ChatMessageErrorPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatMessageErrorPB create() => ChatMessageErrorPB._();
  ChatMessageErrorPB createEmptyInstance() => create();
  static $pb.PbList<ChatMessageErrorPB> createRepeated() => $pb.PbList<ChatMessageErrorPB>();
  @$core.pragma('dart2js:noInline')
  static ChatMessageErrorPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatMessageErrorPB>(create);
  static ChatMessageErrorPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chatId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chatId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChatId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get errorMessage => $_getSZ(1);
  @$pb.TagNumber(2)
  set errorMessage($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasErrorMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearErrorMessage() => clearField(2);
}

class RepeatedChatMessagePB extends $pb.GeneratedMessage {
  factory RepeatedChatMessagePB({
    $core.Iterable<ChatMessagePB>? items,
  }) {
    final $result = create();
    if (items != null) {
      $result.items.addAll(items);
    }
    return $result;
  }
  RepeatedChatMessagePB._() : super();
  factory RepeatedChatMessagePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RepeatedChatMessagePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RepeatedChatMessagePB', createEmptyInstance: create)
    ..pc<ChatMessagePB>(1, _omitFieldNames ? '' : 'items', $pb.PbFieldType.PM, subBuilder: ChatMessagePB.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RepeatedChatMessagePB clone() => RepeatedChatMessagePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RepeatedChatMessagePB copyWith(void Function(RepeatedChatMessagePB) updates) => super.copyWith((message) => updates(message as RepeatedChatMessagePB)) as RepeatedChatMessagePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RepeatedChatMessagePB create() => RepeatedChatMessagePB._();
  RepeatedChatMessagePB createEmptyInstance() => create();
  static $pb.PbList<RepeatedChatMessagePB> createRepeated() => $pb.PbList<RepeatedChatMessagePB>();
  @$core.pragma('dart2js:noInline')
  static RepeatedChatMessagePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepeatedChatMessagePB>(create);
  static RepeatedChatMessagePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ChatMessagePB> get items => $_getList(0);
}

class ChatMessageIdPB extends $pb.GeneratedMessage {
  factory ChatMessageIdPB({
    $core.String? chatId,
    $fixnum.Int64? messageId,
  }) {
    final $result = create();
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (messageId != null) {
      $result.messageId = messageId;
    }
    return $result;
  }
  ChatMessageIdPB._() : super();
  factory ChatMessageIdPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatMessageIdPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatMessageIdPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'chatId')
    ..aInt64(2, _omitFieldNames ? '' : 'messageId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatMessageIdPB clone() => ChatMessageIdPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatMessageIdPB copyWith(void Function(ChatMessageIdPB) updates) => super.copyWith((message) => updates(message as ChatMessageIdPB)) as ChatMessageIdPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatMessageIdPB create() => ChatMessageIdPB._();
  ChatMessageIdPB createEmptyInstance() => create();
  static $pb.PbList<ChatMessageIdPB> createRepeated() => $pb.PbList<ChatMessageIdPB>();
  @$core.pragma('dart2js:noInline')
  static ChatMessageIdPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatMessageIdPB>(create);
  static ChatMessageIdPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chatId => $_getSZ(0);
  @$pb.TagNumber(1)
  set chatId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChatId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get messageId => $_getI64(1);
  @$pb.TagNumber(2)
  set messageId($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessageId() => clearField(2);
}

class RelatedQuestionPB extends $pb.GeneratedMessage {
  factory RelatedQuestionPB({
    $core.String? content,
  }) {
    final $result = create();
    if (content != null) {
      $result.content = content;
    }
    return $result;
  }
  RelatedQuestionPB._() : super();
  factory RelatedQuestionPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RelatedQuestionPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RelatedQuestionPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'content')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RelatedQuestionPB clone() => RelatedQuestionPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RelatedQuestionPB copyWith(void Function(RelatedQuestionPB) updates) => super.copyWith((message) => updates(message as RelatedQuestionPB)) as RelatedQuestionPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RelatedQuestionPB create() => RelatedQuestionPB._();
  RelatedQuestionPB createEmptyInstance() => create();
  static $pb.PbList<RelatedQuestionPB> createRepeated() => $pb.PbList<RelatedQuestionPB>();
  @$core.pragma('dart2js:noInline')
  static RelatedQuestionPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RelatedQuestionPB>(create);
  static RelatedQuestionPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get content => $_getSZ(0);
  @$pb.TagNumber(1)
  set content($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasContent() => $_has(0);
  @$pb.TagNumber(1)
  void clearContent() => clearField(1);
}

class RepeatedRelatedQuestionPB extends $pb.GeneratedMessage {
  factory RepeatedRelatedQuestionPB({
    $fixnum.Int64? messageId,
    $core.Iterable<RelatedQuestionPB>? items,
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (items != null) {
      $result.items.addAll(items);
    }
    return $result;
  }
  RepeatedRelatedQuestionPB._() : super();
  factory RepeatedRelatedQuestionPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RepeatedRelatedQuestionPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RepeatedRelatedQuestionPB', createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'messageId')
    ..pc<RelatedQuestionPB>(2, _omitFieldNames ? '' : 'items', $pb.PbFieldType.PM, subBuilder: RelatedQuestionPB.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RepeatedRelatedQuestionPB clone() => RepeatedRelatedQuestionPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RepeatedRelatedQuestionPB copyWith(void Function(RepeatedRelatedQuestionPB) updates) => super.copyWith((message) => updates(message as RepeatedRelatedQuestionPB)) as RepeatedRelatedQuestionPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RepeatedRelatedQuestionPB create() => RepeatedRelatedQuestionPB._();
  RepeatedRelatedQuestionPB createEmptyInstance() => create();
  static $pb.PbList<RepeatedRelatedQuestionPB> createRepeated() => $pb.PbList<RepeatedRelatedQuestionPB>();
  @$core.pragma('dart2js:noInline')
  static RepeatedRelatedQuestionPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepeatedRelatedQuestionPB>(create);
  static RepeatedRelatedQuestionPB? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get messageId => $_getI64(0);
  @$pb.TagNumber(1)
  set messageId($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<RelatedQuestionPB> get items => $_getList(1);
}

class LLMModelPB extends $pb.GeneratedMessage {
  factory LLMModelPB({
    $fixnum.Int64? llmId,
    $core.String? embeddingModel,
    $core.String? chatModel,
    $core.String? requirement,
    $fixnum.Int64? fileSize,
  }) {
    final $result = create();
    if (llmId != null) {
      $result.llmId = llmId;
    }
    if (embeddingModel != null) {
      $result.embeddingModel = embeddingModel;
    }
    if (chatModel != null) {
      $result.chatModel = chatModel;
    }
    if (requirement != null) {
      $result.requirement = requirement;
    }
    if (fileSize != null) {
      $result.fileSize = fileSize;
    }
    return $result;
  }
  LLMModelPB._() : super();
  factory LLMModelPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMModelPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LLMModelPB', createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'llmId')
    ..aOS(2, _omitFieldNames ? '' : 'embeddingModel')
    ..aOS(3, _omitFieldNames ? '' : 'chatModel')
    ..aOS(4, _omitFieldNames ? '' : 'requirement')
    ..aInt64(5, _omitFieldNames ? '' : 'fileSize')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMModelPB clone() => LLMModelPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMModelPB copyWith(void Function(LLMModelPB) updates) => super.copyWith((message) => updates(message as LLMModelPB)) as LLMModelPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMModelPB create() => LLMModelPB._();
  LLMModelPB createEmptyInstance() => create();
  static $pb.PbList<LLMModelPB> createRepeated() => $pb.PbList<LLMModelPB>();
  @$core.pragma('dart2js:noInline')
  static LLMModelPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMModelPB>(create);
  static LLMModelPB? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get llmId => $_getI64(0);
  @$pb.TagNumber(1)
  set llmId($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLlmId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLlmId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get embeddingModel => $_getSZ(1);
  @$pb.TagNumber(2)
  set embeddingModel($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEmbeddingModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmbeddingModel() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get chatModel => $_getSZ(2);
  @$pb.TagNumber(3)
  set chatModel($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasChatModel() => $_has(2);
  @$pb.TagNumber(3)
  void clearChatModel() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get requirement => $_getSZ(3);
  @$pb.TagNumber(4)
  set requirement($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRequirement() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequirement() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get fileSize => $_getI64(4);
  @$pb.TagNumber(5)
  set fileSize($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasFileSize() => $_has(4);
  @$pb.TagNumber(5)
  void clearFileSize() => clearField(5);
}

enum CompleteTextPB_OneOfFormat {
  format, 
  notSet
}

enum CompleteTextPB_OneOfCustomPrompt {
  customPrompt, 
  notSet
}

enum CompleteTextPB_OneOfPromptId {
  promptId, 
  notSet
}

class CompleteTextPB extends $pb.GeneratedMessage {
  factory CompleteTextPB({
    $core.String? text,
    CompletionTypePB? completionType,
    PredefinedFormatPB? format,
    $fixnum.Int64? streamPort,
    $core.String? objectId,
    $core.Iterable<$core.String>? ragIds,
    $core.Iterable<CompletionRecordPB>? history,
    $core.String? customPrompt,
    $core.String? promptId,
    $core.bool? enableThinking,
    $core.bool? enableWebSearch,
    $core.Iterable<$core.String>? images,
    $core.bool? hasImages,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (completionType != null) {
      $result.completionType = completionType;
    }
    if (format != null) {
      $result.format = format;
    }
    if (streamPort != null) {
      $result.streamPort = streamPort;
    }
    if (objectId != null) {
      $result.objectId = objectId;
    }
    if (ragIds != null) {
      $result.ragIds.addAll(ragIds);
    }
    if (history != null) {
      $result.history.addAll(history);
    }
    if (customPrompt != null) {
      $result.customPrompt = customPrompt;
    }
    if (promptId != null) {
      $result.promptId = promptId;
    }
    if (enableThinking != null) {
      $result.enableThinking = enableThinking;
    }
    if (enableWebSearch != null) {
      $result.enableWebSearch = enableWebSearch;
    }
    if (images != null) {
      $result.images.addAll(images);
    }
    if (hasImages != null) {
      $result.hasImages = hasImages;
    }
    return $result;
  }
  CompleteTextPB._() : super();
  factory CompleteTextPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CompleteTextPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, CompleteTextPB_OneOfFormat> _CompleteTextPB_OneOfFormatByTag = {
    3 : CompleteTextPB_OneOfFormat.format,
    0 : CompleteTextPB_OneOfFormat.notSet
  };
  static const $core.Map<$core.int, CompleteTextPB_OneOfCustomPrompt> _CompleteTextPB_OneOfCustomPromptByTag = {
    8 : CompleteTextPB_OneOfCustomPrompt.customPrompt,
    0 : CompleteTextPB_OneOfCustomPrompt.notSet
  };
  static const $core.Map<$core.int, CompleteTextPB_OneOfPromptId> _CompleteTextPB_OneOfPromptIdByTag = {
    9 : CompleteTextPB_OneOfPromptId.promptId,
    0 : CompleteTextPB_OneOfPromptId.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CompleteTextPB', createEmptyInstance: create)
    ..oo(0, [3])
    ..oo(1, [8])
    ..oo(2, [9])
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..e<CompletionTypePB>(2, _omitFieldNames ? '' : 'completionType', $pb.PbFieldType.OE, defaultOrMaker: CompletionTypePB.UserQuestion, valueOf: CompletionTypePB.valueOf, enumValues: CompletionTypePB.values)
    ..aOM<PredefinedFormatPB>(3, _omitFieldNames ? '' : 'format', subBuilder: PredefinedFormatPB.create)
    ..aInt64(4, _omitFieldNames ? '' : 'streamPort')
    ..aOS(5, _omitFieldNames ? '' : 'objectId')
    ..pPS(6, _omitFieldNames ? '' : 'ragIds')
    ..pc<CompletionRecordPB>(7, _omitFieldNames ? '' : 'history', $pb.PbFieldType.PM, subBuilder: CompletionRecordPB.create)
    ..aOS(8, _omitFieldNames ? '' : 'customPrompt')
    ..aOS(9, _omitFieldNames ? '' : 'promptId')
    ..aOB(10, _omitFieldNames ? '' : 'enableThinking')
    ..aOB(11, _omitFieldNames ? '' : 'enableWebSearch')
    ..pPS(12, _omitFieldNames ? '' : 'images')
    ..aOB(13, _omitFieldNames ? '' : 'hasImages')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CompleteTextPB clone() => CompleteTextPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CompleteTextPB copyWith(void Function(CompleteTextPB) updates) => super.copyWith((message) => updates(message as CompleteTextPB)) as CompleteTextPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CompleteTextPB create() => CompleteTextPB._();
  CompleteTextPB createEmptyInstance() => create();
  static $pb.PbList<CompleteTextPB> createRepeated() => $pb.PbList<CompleteTextPB>();
  @$core.pragma('dart2js:noInline')
  static CompleteTextPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CompleteTextPB>(create);
  static CompleteTextPB? _defaultInstance;

  CompleteTextPB_OneOfFormat whichOneOfFormat() => _CompleteTextPB_OneOfFormatByTag[$_whichOneof(0)]!;
  void clearOneOfFormat() => clearField($_whichOneof(0));

  CompleteTextPB_OneOfCustomPrompt whichOneOfCustomPrompt() => _CompleteTextPB_OneOfCustomPromptByTag[$_whichOneof(1)]!;
  void clearOneOfCustomPrompt() => clearField($_whichOneof(1));

  CompleteTextPB_OneOfPromptId whichOneOfPromptId() => _CompleteTextPB_OneOfPromptIdByTag[$_whichOneof(2)]!;
  void clearOneOfPromptId() => clearField($_whichOneof(2));

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  CompletionTypePB get completionType => $_getN(1);
  @$pb.TagNumber(2)
  set completionType(CompletionTypePB v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasCompletionType() => $_has(1);
  @$pb.TagNumber(2)
  void clearCompletionType() => clearField(2);

  @$pb.TagNumber(3)
  PredefinedFormatPB get format => $_getN(2);
  @$pb.TagNumber(3)
  set format(PredefinedFormatPB v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasFormat() => $_has(2);
  @$pb.TagNumber(3)
  void clearFormat() => clearField(3);
  @$pb.TagNumber(3)
  PredefinedFormatPB ensureFormat() => $_ensure(2);

  @$pb.TagNumber(4)
  $fixnum.Int64 get streamPort => $_getI64(3);
  @$pb.TagNumber(4)
  set streamPort($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasStreamPort() => $_has(3);
  @$pb.TagNumber(4)
  void clearStreamPort() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get objectId => $_getSZ(4);
  @$pb.TagNumber(5)
  set objectId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasObjectId() => $_has(4);
  @$pb.TagNumber(5)
  void clearObjectId() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.String> get ragIds => $_getList(5);

  @$pb.TagNumber(7)
  $core.List<CompletionRecordPB> get history => $_getList(6);

  @$pb.TagNumber(8)
  $core.String get customPrompt => $_getSZ(7);
  @$pb.TagNumber(8)
  set customPrompt($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasCustomPrompt() => $_has(7);
  @$pb.TagNumber(8)
  void clearCustomPrompt() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get promptId => $_getSZ(8);
  @$pb.TagNumber(9)
  set promptId($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasPromptId() => $_has(8);
  @$pb.TagNumber(9)
  void clearPromptId() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get enableThinking => $_getBF(9);
  @$pb.TagNumber(10)
  set enableThinking($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasEnableThinking() => $_has(9);
  @$pb.TagNumber(10)
  void clearEnableThinking() => clearField(10);

  @$pb.TagNumber(11)
  $core.bool get enableWebSearch => $_getBF(10);
  @$pb.TagNumber(11)
  set enableWebSearch($core.bool v) { $_setBool(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasEnableWebSearch() => $_has(10);
  @$pb.TagNumber(11)
  void clearEnableWebSearch() => clearField(11);

  @$pb.TagNumber(12)
  $core.List<$core.String> get images => $_getList(11);

  @$pb.TagNumber(13)
  $core.bool get hasImages => $_getBF(12);
  @$pb.TagNumber(13)
  set hasImages($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasHasImages() => $_has(12);
  @$pb.TagNumber(13)
  void clearHasImages() => clearField(13);
}

class CompleteTextTaskPB extends $pb.GeneratedMessage {
  factory CompleteTextTaskPB({
    $core.String? taskId,
  }) {
    final $result = create();
    if (taskId != null) {
      $result.taskId = taskId;
    }
    return $result;
  }
  CompleteTextTaskPB._() : super();
  factory CompleteTextTaskPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CompleteTextTaskPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CompleteTextTaskPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'taskId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CompleteTextTaskPB clone() => CompleteTextTaskPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CompleteTextTaskPB copyWith(void Function(CompleteTextTaskPB) updates) => super.copyWith((message) => updates(message as CompleteTextTaskPB)) as CompleteTextTaskPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CompleteTextTaskPB create() => CompleteTextTaskPB._();
  CompleteTextTaskPB createEmptyInstance() => create();
  static $pb.PbList<CompleteTextTaskPB> createRepeated() => $pb.PbList<CompleteTextTaskPB>();
  @$core.pragma('dart2js:noInline')
  static CompleteTextTaskPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CompleteTextTaskPB>(create);
  static CompleteTextTaskPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get taskId => $_getSZ(0);
  @$pb.TagNumber(1)
  set taskId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTaskId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTaskId() => clearField(1);
}

class CompletionRecordPB extends $pb.GeneratedMessage {
  factory CompletionRecordPB({
    ChatMessageTypePB? role,
    $core.String? content,
  }) {
    final $result = create();
    if (role != null) {
      $result.role = role;
    }
    if (content != null) {
      $result.content = content;
    }
    return $result;
  }
  CompletionRecordPB._() : super();
  factory CompletionRecordPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CompletionRecordPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CompletionRecordPB', createEmptyInstance: create)
    ..e<ChatMessageTypePB>(1, _omitFieldNames ? '' : 'role', $pb.PbFieldType.OE, defaultOrMaker: ChatMessageTypePB.System, valueOf: ChatMessageTypePB.valueOf, enumValues: ChatMessageTypePB.values)
    ..aOS(2, _omitFieldNames ? '' : 'content')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CompletionRecordPB clone() => CompletionRecordPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CompletionRecordPB copyWith(void Function(CompletionRecordPB) updates) => super.copyWith((message) => updates(message as CompletionRecordPB)) as CompletionRecordPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CompletionRecordPB create() => CompletionRecordPB._();
  CompletionRecordPB createEmptyInstance() => create();
  static $pb.PbList<CompletionRecordPB> createRepeated() => $pb.PbList<CompletionRecordPB>();
  @$core.pragma('dart2js:noInline')
  static CompletionRecordPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CompletionRecordPB>(create);
  static CompletionRecordPB? _defaultInstance;

  @$pb.TagNumber(1)
  ChatMessageTypePB get role => $_getN(0);
  @$pb.TagNumber(1)
  set role(ChatMessageTypePB v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasRole() => $_has(0);
  @$pb.TagNumber(1)
  void clearRole() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get content => $_getSZ(1);
  @$pb.TagNumber(2)
  set content($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearContent() => clearField(2);
}

class ChatStatePB extends $pb.GeneratedMessage {
  factory ChatStatePB({
    ModelTypePB? modelType,
    $core.bool? available,
  }) {
    final $result = create();
    if (modelType != null) {
      $result.modelType = modelType;
    }
    if (available != null) {
      $result.available = available;
    }
    return $result;
  }
  ChatStatePB._() : super();
  factory ChatStatePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatStatePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatStatePB', createEmptyInstance: create)
    ..e<ModelTypePB>(1, _omitFieldNames ? '' : 'modelType', $pb.PbFieldType.OE, defaultOrMaker: ModelTypePB.LocalAI, valueOf: ModelTypePB.valueOf, enumValues: ModelTypePB.values)
    ..aOB(2, _omitFieldNames ? '' : 'available')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatStatePB clone() => ChatStatePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatStatePB copyWith(void Function(ChatStatePB) updates) => super.copyWith((message) => updates(message as ChatStatePB)) as ChatStatePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatStatePB create() => ChatStatePB._();
  ChatStatePB createEmptyInstance() => create();
  static $pb.PbList<ChatStatePB> createRepeated() => $pb.PbList<ChatStatePB>();
  @$core.pragma('dart2js:noInline')
  static ChatStatePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatStatePB>(create);
  static ChatStatePB? _defaultInstance;

  @$pb.TagNumber(1)
  ModelTypePB get modelType => $_getN(0);
  @$pb.TagNumber(1)
  set modelType(ModelTypePB v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelType() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelType() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get available => $_getBF(1);
  @$pb.TagNumber(2)
  set available($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAvailable() => $_has(1);
  @$pb.TagNumber(2)
  void clearAvailable() => clearField(2);
}

class ChatFilePB extends $pb.GeneratedMessage {
  factory ChatFilePB({
    $core.String? filePath,
    $core.String? chatId,
  }) {
    final $result = create();
    if (filePath != null) {
      $result.filePath = filePath;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  ChatFilePB._() : super();
  factory ChatFilePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatFilePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatFilePB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'filePath')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatFilePB clone() => ChatFilePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatFilePB copyWith(void Function(ChatFilePB) updates) => super.copyWith((message) => updates(message as ChatFilePB)) as ChatFilePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatFilePB create() => ChatFilePB._();
  ChatFilePB createEmptyInstance() => create();
  static $pb.PbList<ChatFilePB> createRepeated() => $pb.PbList<ChatFilePB>();
  @$core.pragma('dart2js:noInline')
  static ChatFilePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatFilePB>(create);
  static ChatFilePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get filePath => $_getSZ(0);
  @$pb.TagNumber(1)
  set filePath($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFilePath() => $_has(0);
  @$pb.TagNumber(1)
  void clearFilePath() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);
}

class LocalModelStatePB extends $pb.GeneratedMessage {
  factory LocalModelStatePB({
    $core.String? modelName,
    $core.String? modelSize,
    $core.bool? needDownload,
    $core.String? requirements,
    $core.bool? isDownloading,
  }) {
    final $result = create();
    if (modelName != null) {
      $result.modelName = modelName;
    }
    if (modelSize != null) {
      $result.modelSize = modelSize;
    }
    if (needDownload != null) {
      $result.needDownload = needDownload;
    }
    if (requirements != null) {
      $result.requirements = requirements;
    }
    if (isDownloading != null) {
      $result.isDownloading = isDownloading;
    }
    return $result;
  }
  LocalModelStatePB._() : super();
  factory LocalModelStatePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LocalModelStatePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LocalModelStatePB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelName')
    ..aOS(2, _omitFieldNames ? '' : 'modelSize')
    ..aOB(3, _omitFieldNames ? '' : 'needDownload')
    ..aOS(4, _omitFieldNames ? '' : 'requirements')
    ..aOB(5, _omitFieldNames ? '' : 'isDownloading')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LocalModelStatePB clone() => LocalModelStatePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LocalModelStatePB copyWith(void Function(LocalModelStatePB) updates) => super.copyWith((message) => updates(message as LocalModelStatePB)) as LocalModelStatePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LocalModelStatePB create() => LocalModelStatePB._();
  LocalModelStatePB createEmptyInstance() => create();
  static $pb.PbList<LocalModelStatePB> createRepeated() => $pb.PbList<LocalModelStatePB>();
  @$core.pragma('dart2js:noInline')
  static LocalModelStatePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LocalModelStatePB>(create);
  static LocalModelStatePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelName => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelName($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelName() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelName() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelSize => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelSize($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelSize() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get needDownload => $_getBF(2);
  @$pb.TagNumber(3)
  set needDownload($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasNeedDownload() => $_has(2);
  @$pb.TagNumber(3)
  void clearNeedDownload() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get requirements => $_getSZ(3);
  @$pb.TagNumber(4)
  set requirements($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRequirements() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequirements() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get isDownloading => $_getBF(4);
  @$pb.TagNumber(5)
  set isDownloading($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasIsDownloading() => $_has(4);
  @$pb.TagNumber(5)
  void clearIsDownloading() => clearField(5);
}

class PendingResourcePB extends $pb.GeneratedMessage {
  factory PendingResourcePB({
    $core.String? name,
    $core.String? fileSize,
    $core.String? requirements,
    PendingResourceTypePB? resType,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (fileSize != null) {
      $result.fileSize = fileSize;
    }
    if (requirements != null) {
      $result.requirements = requirements;
    }
    if (resType != null) {
      $result.resType = resType;
    }
    return $result;
  }
  PendingResourcePB._() : super();
  factory PendingResourcePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PendingResourcePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PendingResourcePB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'fileSize')
    ..aOS(3, _omitFieldNames ? '' : 'requirements')
    ..e<PendingResourceTypePB>(4, _omitFieldNames ? '' : 'resType', $pb.PbFieldType.OE, defaultOrMaker: PendingResourceTypePB.LocalAIAppRes, valueOf: PendingResourceTypePB.valueOf, enumValues: PendingResourceTypePB.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PendingResourcePB clone() => PendingResourcePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PendingResourcePB copyWith(void Function(PendingResourcePB) updates) => super.copyWith((message) => updates(message as PendingResourcePB)) as PendingResourcePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PendingResourcePB create() => PendingResourcePB._();
  PendingResourcePB createEmptyInstance() => create();
  static $pb.PbList<PendingResourcePB> createRepeated() => $pb.PbList<PendingResourcePB>();
  @$core.pragma('dart2js:noInline')
  static PendingResourcePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PendingResourcePB>(create);
  static PendingResourcePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get fileSize => $_getSZ(1);
  @$pb.TagNumber(2)
  set fileSize($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFileSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileSize() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get requirements => $_getSZ(2);
  @$pb.TagNumber(3)
  set requirements($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRequirements() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequirements() => clearField(3);

  @$pb.TagNumber(4)
  PendingResourceTypePB get resType => $_getN(3);
  @$pb.TagNumber(4)
  set resType(PendingResourceTypePB v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasResType() => $_has(3);
  @$pb.TagNumber(4)
  void clearResType() => clearField(4);
}

enum LocalAIPB_OneOfLackOfResource {
  lackOfResource, 
  notSet
}

class LocalAIPB extends $pb.GeneratedMessage {
  factory LocalAIPB({
    $core.bool? enabled,
    LackOfAIResourcePB? lackOfResource,
    $core.bool? isReady,
  }) {
    final $result = create();
    if (enabled != null) {
      $result.enabled = enabled;
    }
    if (lackOfResource != null) {
      $result.lackOfResource = lackOfResource;
    }
    if (isReady != null) {
      $result.isReady = isReady;
    }
    return $result;
  }
  LocalAIPB._() : super();
  factory LocalAIPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LocalAIPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, LocalAIPB_OneOfLackOfResource> _LocalAIPB_OneOfLackOfResourceByTag = {
    2 : LocalAIPB_OneOfLackOfResource.lackOfResource,
    0 : LocalAIPB_OneOfLackOfResource.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LocalAIPB', createEmptyInstance: create)
    ..oo(0, [2])
    ..aOB(1, _omitFieldNames ? '' : 'enabled')
    ..aOM<LackOfAIResourcePB>(2, _omitFieldNames ? '' : 'lackOfResource', subBuilder: LackOfAIResourcePB.create)
    ..aOB(3, _omitFieldNames ? '' : 'isReady')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LocalAIPB clone() => LocalAIPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LocalAIPB copyWith(void Function(LocalAIPB) updates) => super.copyWith((message) => updates(message as LocalAIPB)) as LocalAIPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LocalAIPB create() => LocalAIPB._();
  LocalAIPB createEmptyInstance() => create();
  static $pb.PbList<LocalAIPB> createRepeated() => $pb.PbList<LocalAIPB>();
  @$core.pragma('dart2js:noInline')
  static LocalAIPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LocalAIPB>(create);
  static LocalAIPB? _defaultInstance;

  LocalAIPB_OneOfLackOfResource whichOneOfLackOfResource() => _LocalAIPB_OneOfLackOfResourceByTag[$_whichOneof(0)]!;
  void clearOneOfLackOfResource() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.bool get enabled => $_getBF(0);
  @$pb.TagNumber(1)
  set enabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnabled() => clearField(1);

  @$pb.TagNumber(2)
  LackOfAIResourcePB get lackOfResource => $_getN(1);
  @$pb.TagNumber(2)
  set lackOfResource(LackOfAIResourcePB v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasLackOfResource() => $_has(1);
  @$pb.TagNumber(2)
  void clearLackOfResource() => clearField(2);
  @$pb.TagNumber(2)
  LackOfAIResourcePB ensureLackOfResource() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.bool get isReady => $_getBF(2);
  @$pb.TagNumber(3)
  set isReady($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasIsReady() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsReady() => clearField(3);
}

class CreateChatContextPB extends $pb.GeneratedMessage {
  factory CreateChatContextPB({
    $core.String? contentType,
    $core.String? text,
    $core.Map<$core.String, $core.String>? metadata,
    $core.String? chatId,
  }) {
    final $result = create();
    if (contentType != null) {
      $result.contentType = contentType;
    }
    if (text != null) {
      $result.text = text;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  CreateChatContextPB._() : super();
  factory CreateChatContextPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CreateChatContextPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CreateChatContextPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'contentType')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'metadata', entryClassName: 'CreateChatContextPB.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS)
    ..aOS(4, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CreateChatContextPB clone() => CreateChatContextPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CreateChatContextPB copyWith(void Function(CreateChatContextPB) updates) => super.copyWith((message) => updates(message as CreateChatContextPB)) as CreateChatContextPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateChatContextPB create() => CreateChatContextPB._();
  CreateChatContextPB createEmptyInstance() => create();
  static $pb.PbList<CreateChatContextPB> createRepeated() => $pb.PbList<CreateChatContextPB>();
  @$core.pragma('dart2js:noInline')
  static CreateChatContextPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CreateChatContextPB>(create);
  static CreateChatContextPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get contentType => $_getSZ(0);
  @$pb.TagNumber(1)
  set contentType($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasContentType() => $_has(0);
  @$pb.TagNumber(1)
  void clearContentType() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => clearField(2);

  @$pb.TagNumber(3)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(2);

  @$pb.TagNumber(4)
  $core.String get chatId => $_getSZ(3);
  @$pb.TagNumber(4)
  set chatId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasChatId() => $_has(3);
  @$pb.TagNumber(4)
  void clearChatId() => clearField(4);
}

class ChatSettingsPB extends $pb.GeneratedMessage {
  factory ChatSettingsPB({
    $core.Iterable<$core.String>? ragIds,
  }) {
    final $result = create();
    if (ragIds != null) {
      $result.ragIds.addAll(ragIds);
    }
    return $result;
  }
  ChatSettingsPB._() : super();
  factory ChatSettingsPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatSettingsPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatSettingsPB', createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'ragIds')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatSettingsPB clone() => ChatSettingsPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatSettingsPB copyWith(void Function(ChatSettingsPB) updates) => super.copyWith((message) => updates(message as ChatSettingsPB)) as ChatSettingsPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatSettingsPB create() => ChatSettingsPB._();
  ChatSettingsPB createEmptyInstance() => create();
  static $pb.PbList<ChatSettingsPB> createRepeated() => $pb.PbList<ChatSettingsPB>();
  @$core.pragma('dart2js:noInline')
  static ChatSettingsPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatSettingsPB>(create);
  static ChatSettingsPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get ragIds => $_getList(0);
}

class UpdateChatSettingsPB extends $pb.GeneratedMessage {
  factory UpdateChatSettingsPB({
    ChatId? chatId,
    $core.Iterable<$core.String>? ragIds,
  }) {
    final $result = create();
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (ragIds != null) {
      $result.ragIds.addAll(ragIds);
    }
    return $result;
  }
  UpdateChatSettingsPB._() : super();
  factory UpdateChatSettingsPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UpdateChatSettingsPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UpdateChatSettingsPB', createEmptyInstance: create)
    ..aOM<ChatId>(1, _omitFieldNames ? '' : 'chatId', subBuilder: ChatId.create)
    ..pPS(2, _omitFieldNames ? '' : 'ragIds')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UpdateChatSettingsPB clone() => UpdateChatSettingsPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UpdateChatSettingsPB copyWith(void Function(UpdateChatSettingsPB) updates) => super.copyWith((message) => updates(message as UpdateChatSettingsPB)) as UpdateChatSettingsPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateChatSettingsPB create() => UpdateChatSettingsPB._();
  UpdateChatSettingsPB createEmptyInstance() => create();
  static $pb.PbList<UpdateChatSettingsPB> createRepeated() => $pb.PbList<UpdateChatSettingsPB>();
  @$core.pragma('dart2js:noInline')
  static UpdateChatSettingsPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UpdateChatSettingsPB>(create);
  static UpdateChatSettingsPB? _defaultInstance;

  @$pb.TagNumber(1)
  ChatId get chatId => $_getN(0);
  @$pb.TagNumber(1)
  set chatId(ChatId v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasChatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChatId() => clearField(1);
  @$pb.TagNumber(1)
  ChatId ensureChatId() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.List<$core.String> get ragIds => $_getList(1);
}

enum PredefinedFormatPB_OneOfTextFormat {
  textFormat, 
  notSet
}

class PredefinedFormatPB extends $pb.GeneratedMessage {
  factory PredefinedFormatPB({
    ResponseImageFormatPB? imageFormat,
    ResponseTextFormatPB? textFormat,
  }) {
    final $result = create();
    if (imageFormat != null) {
      $result.imageFormat = imageFormat;
    }
    if (textFormat != null) {
      $result.textFormat = textFormat;
    }
    return $result;
  }
  PredefinedFormatPB._() : super();
  factory PredefinedFormatPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PredefinedFormatPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, PredefinedFormatPB_OneOfTextFormat> _PredefinedFormatPB_OneOfTextFormatByTag = {
    2 : PredefinedFormatPB_OneOfTextFormat.textFormat,
    0 : PredefinedFormatPB_OneOfTextFormat.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PredefinedFormatPB', createEmptyInstance: create)
    ..oo(0, [2])
    ..e<ResponseImageFormatPB>(1, _omitFieldNames ? '' : 'imageFormat', $pb.PbFieldType.OE, defaultOrMaker: ResponseImageFormatPB.TextOnly, valueOf: ResponseImageFormatPB.valueOf, enumValues: ResponseImageFormatPB.values)
    ..e<ResponseTextFormatPB>(2, _omitFieldNames ? '' : 'textFormat', $pb.PbFieldType.OE, defaultOrMaker: ResponseTextFormatPB.Paragraph, valueOf: ResponseTextFormatPB.valueOf, enumValues: ResponseTextFormatPB.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PredefinedFormatPB clone() => PredefinedFormatPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PredefinedFormatPB copyWith(void Function(PredefinedFormatPB) updates) => super.copyWith((message) => updates(message as PredefinedFormatPB)) as PredefinedFormatPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PredefinedFormatPB create() => PredefinedFormatPB._();
  PredefinedFormatPB createEmptyInstance() => create();
  static $pb.PbList<PredefinedFormatPB> createRepeated() => $pb.PbList<PredefinedFormatPB>();
  @$core.pragma('dart2js:noInline')
  static PredefinedFormatPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PredefinedFormatPB>(create);
  static PredefinedFormatPB? _defaultInstance;

  PredefinedFormatPB_OneOfTextFormat whichOneOfTextFormat() => _PredefinedFormatPB_OneOfTextFormatByTag[$_whichOneof(0)]!;
  void clearOneOfTextFormat() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  ResponseImageFormatPB get imageFormat => $_getN(0);
  @$pb.TagNumber(1)
  set imageFormat(ResponseImageFormatPB v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasImageFormat() => $_has(0);
  @$pb.TagNumber(1)
  void clearImageFormat() => clearField(1);

  @$pb.TagNumber(2)
  ResponseTextFormatPB get textFormat => $_getN(1);
  @$pb.TagNumber(2)
  set textFormat(ResponseTextFormatPB v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasTextFormat() => $_has(1);
  @$pb.TagNumber(2)
  void clearTextFormat() => clearField(2);
}

class LocalAISettingPB extends $pb.GeneratedMessage {
  factory LocalAISettingPB({
    $core.String? serverUrl,
    $core.String? globalChatModel,
    $core.String? embeddingModelName,
    $core.String? apiKey,
  }) {
    final $result = create();
    if (serverUrl != null) {
      $result.serverUrl = serverUrl;
    }
    if (globalChatModel != null) {
      $result.globalChatModel = globalChatModel;
    }
    if (embeddingModelName != null) {
      $result.embeddingModelName = embeddingModelName;
    }
    if (apiKey != null) {
      $result.apiKey = apiKey;
    }
    return $result;
  }
  LocalAISettingPB._() : super();
  factory LocalAISettingPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LocalAISettingPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LocalAISettingPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'serverUrl')
    ..aOS(2, _omitFieldNames ? '' : 'globalChatModel')
    ..aOS(3, _omitFieldNames ? '' : 'embeddingModelName')
    ..aOS(4, _omitFieldNames ? '' : 'apiKey')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LocalAISettingPB clone() => LocalAISettingPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LocalAISettingPB copyWith(void Function(LocalAISettingPB) updates) => super.copyWith((message) => updates(message as LocalAISettingPB)) as LocalAISettingPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LocalAISettingPB create() => LocalAISettingPB._();
  LocalAISettingPB createEmptyInstance() => create();
  static $pb.PbList<LocalAISettingPB> createRepeated() => $pb.PbList<LocalAISettingPB>();
  @$core.pragma('dart2js:noInline')
  static LocalAISettingPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LocalAISettingPB>(create);
  static LocalAISettingPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get serverUrl => $_getSZ(0);
  @$pb.TagNumber(1)
  set serverUrl($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasServerUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearServerUrl() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get globalChatModel => $_getSZ(1);
  @$pb.TagNumber(2)
  set globalChatModel($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasGlobalChatModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearGlobalChatModel() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get embeddingModelName => $_getSZ(2);
  @$pb.TagNumber(3)
  set embeddingModelName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEmbeddingModelName() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmbeddingModelName() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get apiKey => $_getSZ(3);
  @$pb.TagNumber(4)
  set apiKey($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasApiKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearApiKey() => clearField(4);
}

class LackOfAIResourcePB extends $pb.GeneratedMessage {
  factory LackOfAIResourcePB({
    LackOfAIResourceTypePB? resourceType,
    $core.Iterable<$core.String>? missingModelNames,
  }) {
    final $result = create();
    if (resourceType != null) {
      $result.resourceType = resourceType;
    }
    if (missingModelNames != null) {
      $result.missingModelNames.addAll(missingModelNames);
    }
    return $result;
  }
  LackOfAIResourcePB._() : super();
  factory LackOfAIResourcePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LackOfAIResourcePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LackOfAIResourcePB', createEmptyInstance: create)
    ..e<LackOfAIResourceTypePB>(1, _omitFieldNames ? '' : 'resourceType', $pb.PbFieldType.OE, defaultOrMaker: LackOfAIResourceTypePB.PluginExecutableNotReady, valueOf: LackOfAIResourceTypePB.valueOf, enumValues: LackOfAIResourceTypePB.values)
    ..pPS(2, _omitFieldNames ? '' : 'missingModelNames')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LackOfAIResourcePB clone() => LackOfAIResourcePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LackOfAIResourcePB copyWith(void Function(LackOfAIResourcePB) updates) => super.copyWith((message) => updates(message as LackOfAIResourcePB)) as LackOfAIResourcePB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LackOfAIResourcePB create() => LackOfAIResourcePB._();
  LackOfAIResourcePB createEmptyInstance() => create();
  static $pb.PbList<LackOfAIResourcePB> createRepeated() => $pb.PbList<LackOfAIResourcePB>();
  @$core.pragma('dart2js:noInline')
  static LackOfAIResourcePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LackOfAIResourcePB>(create);
  static LackOfAIResourcePB? _defaultInstance;

  @$pb.TagNumber(1)
  LackOfAIResourceTypePB get resourceType => $_getN(0);
  @$pb.TagNumber(1)
  set resourceType(LackOfAIResourceTypePB v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasResourceType() => $_has(0);
  @$pb.TagNumber(1)
  void clearResourceType() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.String> get missingModelNames => $_getList(1);
}

class CustomPromptDatabaseViewIdPB extends $pb.GeneratedMessage {
  factory CustomPromptDatabaseViewIdPB({
    $core.String? id,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    return $result;
  }
  CustomPromptDatabaseViewIdPB._() : super();
  factory CustomPromptDatabaseViewIdPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CustomPromptDatabaseViewIdPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CustomPromptDatabaseViewIdPB', createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CustomPromptDatabaseViewIdPB clone() => CustomPromptDatabaseViewIdPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CustomPromptDatabaseViewIdPB copyWith(void Function(CustomPromptDatabaseViewIdPB) updates) => super.copyWith((message) => updates(message as CustomPromptDatabaseViewIdPB)) as CustomPromptDatabaseViewIdPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CustomPromptDatabaseViewIdPB create() => CustomPromptDatabaseViewIdPB._();
  CustomPromptDatabaseViewIdPB createEmptyInstance() => create();
  static $pb.PbList<CustomPromptDatabaseViewIdPB> createRepeated() => $pb.PbList<CustomPromptDatabaseViewIdPB>();
  @$core.pragma('dart2js:noInline')
  static CustomPromptDatabaseViewIdPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CustomPromptDatabaseViewIdPB>(create);
  static CustomPromptDatabaseViewIdPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);
}

enum CustomPromptDatabaseConfigurationPB_OneOfExampleFieldId {
  exampleFieldId, 
  notSet
}

enum CustomPromptDatabaseConfigurationPB_OneOfCategoryFieldId {
  categoryFieldId, 
  notSet
}

class CustomPromptDatabaseConfigurationPB extends $pb.GeneratedMessage {
  factory CustomPromptDatabaseConfigurationPB({
    $core.String? viewId,
    $core.String? titleFieldId,
    $core.String? contentFieldId,
    $core.String? exampleFieldId,
    $core.String? categoryFieldId,
  }) {
    final $result = create();
    if (viewId != null) {
      $result.viewId = viewId;
    }
    if (titleFieldId != null) {
      $result.titleFieldId = titleFieldId;
    }
    if (contentFieldId != null) {
      $result.contentFieldId = contentFieldId;
    }
    if (exampleFieldId != null) {
      $result.exampleFieldId = exampleFieldId;
    }
    if (categoryFieldId != null) {
      $result.categoryFieldId = categoryFieldId;
    }
    return $result;
  }
  CustomPromptDatabaseConfigurationPB._() : super();
  factory CustomPromptDatabaseConfigurationPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CustomPromptDatabaseConfigurationPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, CustomPromptDatabaseConfigurationPB_OneOfExampleFieldId> _CustomPromptDatabaseConfigurationPB_OneOfExampleFieldIdByTag = {
    4 : CustomPromptDatabaseConfigurationPB_OneOfExampleFieldId.exampleFieldId,
    0 : CustomPromptDatabaseConfigurationPB_OneOfExampleFieldId.notSet
  };
  static const $core.Map<$core.int, CustomPromptDatabaseConfigurationPB_OneOfCategoryFieldId> _CustomPromptDatabaseConfigurationPB_OneOfCategoryFieldIdByTag = {
    5 : CustomPromptDatabaseConfigurationPB_OneOfCategoryFieldId.categoryFieldId,
    0 : CustomPromptDatabaseConfigurationPB_OneOfCategoryFieldId.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CustomPromptDatabaseConfigurationPB', createEmptyInstance: create)
    ..oo(0, [4])
    ..oo(1, [5])
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..aOS(2, _omitFieldNames ? '' : 'titleFieldId')
    ..aOS(3, _omitFieldNames ? '' : 'contentFieldId')
    ..aOS(4, _omitFieldNames ? '' : 'exampleFieldId')
    ..aOS(5, _omitFieldNames ? '' : 'categoryFieldId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CustomPromptDatabaseConfigurationPB clone() => CustomPromptDatabaseConfigurationPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CustomPromptDatabaseConfigurationPB copyWith(void Function(CustomPromptDatabaseConfigurationPB) updates) => super.copyWith((message) => updates(message as CustomPromptDatabaseConfigurationPB)) as CustomPromptDatabaseConfigurationPB;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CustomPromptDatabaseConfigurationPB create() => CustomPromptDatabaseConfigurationPB._();
  CustomPromptDatabaseConfigurationPB createEmptyInstance() => create();
  static $pb.PbList<CustomPromptDatabaseConfigurationPB> createRepeated() => $pb.PbList<CustomPromptDatabaseConfigurationPB>();
  @$core.pragma('dart2js:noInline')
  static CustomPromptDatabaseConfigurationPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CustomPromptDatabaseConfigurationPB>(create);
  static CustomPromptDatabaseConfigurationPB? _defaultInstance;

  CustomPromptDatabaseConfigurationPB_OneOfExampleFieldId whichOneOfExampleFieldId() => _CustomPromptDatabaseConfigurationPB_OneOfExampleFieldIdByTag[$_whichOneof(0)]!;
  void clearOneOfExampleFieldId() => clearField($_whichOneof(0));

  CustomPromptDatabaseConfigurationPB_OneOfCategoryFieldId whichOneOfCategoryFieldId() => _CustomPromptDatabaseConfigurationPB_OneOfCategoryFieldIdByTag[$_whichOneof(1)]!;
  void clearOneOfCategoryFieldId() => clearField($_whichOneof(1));

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get titleFieldId => $_getSZ(1);
  @$pb.TagNumber(2)
  set titleFieldId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTitleFieldId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitleFieldId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get contentFieldId => $_getSZ(2);
  @$pb.TagNumber(3)
  set contentFieldId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasContentFieldId() => $_has(2);
  @$pb.TagNumber(3)
  void clearContentFieldId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get exampleFieldId => $_getSZ(3);
  @$pb.TagNumber(4)
  set exampleFieldId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasExampleFieldId() => $_has(3);
  @$pb.TagNumber(4)
  void clearExampleFieldId() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get categoryFieldId => $_getSZ(4);
  @$pb.TagNumber(5)
  set categoryFieldId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasCategoryFieldId() => $_has(4);
  @$pb.TagNumber(5)
  void clearCategoryFieldId() => clearField(5);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
