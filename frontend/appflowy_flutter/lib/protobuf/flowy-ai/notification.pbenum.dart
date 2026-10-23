//
//  Generated code. Do not modify.
//  source: notification.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class ChatNotification extends $pb.ProtobufEnum {
  static const ChatNotification Unknown = ChatNotification._(0, _omitEnumNames ? '' : 'Unknown');
  static const ChatNotification DidLoadLatestChatMessage = ChatNotification._(1, _omitEnumNames ? '' : 'DidLoadLatestChatMessage');
  static const ChatNotification DidLoadPrevChatMessage = ChatNotification._(2, _omitEnumNames ? '' : 'DidLoadPrevChatMessage');
  static const ChatNotification DidReceiveChatMessage = ChatNotification._(3, _omitEnumNames ? '' : 'DidReceiveChatMessage');
  static const ChatNotification StreamChatMessageError = ChatNotification._(4, _omitEnumNames ? '' : 'StreamChatMessageError');
  static const ChatNotification FinishStreaming = ChatNotification._(5, _omitEnumNames ? '' : 'FinishStreaming');
  static const ChatNotification UpdateLocalAIState = ChatNotification._(6, _omitEnumNames ? '' : 'UpdateLocalAIState');
  static const ChatNotification DidUpdateChatSettings = ChatNotification._(7, _omitEnumNames ? '' : 'DidUpdateChatSettings');
  static const ChatNotification LocalAIResourceUpdated = ChatNotification._(8, _omitEnumNames ? '' : 'LocalAIResourceUpdated');
  static const ChatNotification DidUpdateSelectedModel = ChatNotification._(9, _omitEnumNames ? '' : 'DidUpdateSelectedModel');

  static const $core.List<ChatNotification> values = <ChatNotification> [
    Unknown,
    DidLoadLatestChatMessage,
    DidLoadPrevChatMessage,
    DidReceiveChatMessage,
    StreamChatMessageError,
    FinishStreaming,
    UpdateLocalAIState,
    DidUpdateChatSettings,
    LocalAIResourceUpdated,
    DidUpdateSelectedModel,
  ];

  static final $core.Map<$core.int, ChatNotification> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ChatNotification? valueOf($core.int value) => _byValue[value];

  const ChatNotification._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
