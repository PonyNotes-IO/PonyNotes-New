//
//  Generated code. Do not modify.
//  source: entities.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use contextLoaderTypePBDescriptor instead')
const ContextLoaderTypePB$json = {
  '1': 'ContextLoaderTypePB',
  '2': [
    {'1': 'UnknownLoaderType', '2': 0},
    {'1': 'Txt', '2': 1},
    {'1': 'Markdown', '2': 2},
    {'1': 'PDF', '2': 3},
  ],
};

/// Descriptor for `ContextLoaderTypePB`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List contextLoaderTypePBDescriptor = $convert.base64Decode(
    'ChNDb250ZXh0TG9hZGVyVHlwZVBCEhUKEVVua25vd25Mb2FkZXJUeXBlEAASBwoDVHh0EAESDA'
    'oITWFya2Rvd24QAhIHCgNQREYQAw==');

@$core.Deprecated('Use chatMessageTypePBDescriptor instead')
const ChatMessageTypePB$json = {
  '1': 'ChatMessageTypePB',
  '2': [
    {'1': 'System', '2': 0},
    {'1': 'User', '2': 1},
  ],
};

/// Descriptor for `ChatMessageTypePB`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List chatMessageTypePBDescriptor = $convert.base64Decode(
    'ChFDaGF0TWVzc2FnZVR5cGVQQhIKCgZTeXN0ZW0QABIICgRVc2VyEAE=');

@$core.Deprecated('Use completionTypePBDescriptor instead')
const CompletionTypePB$json = {
  '1': 'CompletionTypePB',
  '2': [
    {'1': 'UserQuestion', '2': 0},
    {'1': 'ExplainSelected', '2': 1},
    {'1': 'ContinueWriting', '2': 2},
    {'1': 'SpellingAndGrammar', '2': 3},
    {'1': 'ImproveWriting', '2': 4},
    {'1': 'MakeShorter', '2': 5},
    {'1': 'MakeLonger', '2': 6},
    {'1': 'CustomPrompt', '2': 7},
  ],
};

/// Descriptor for `CompletionTypePB`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List completionTypePBDescriptor = $convert.base64Decode(
    'ChBDb21wbGV0aW9uVHlwZVBCEhAKDFVzZXJRdWVzdGlvbhAAEhMKD0V4cGxhaW5TZWxlY3RlZB'
    'ABEhMKD0NvbnRpbnVlV3JpdGluZxACEhYKElNwZWxsaW5nQW5kR3JhbW1hchADEhIKDkltcHJv'
    'dmVXcml0aW5nEAQSDwoLTWFrZVNob3J0ZXIQBRIOCgpNYWtlTG9uZ2VyEAYSEAoMQ3VzdG9tUH'
    'JvbXB0EAc=');

@$core.Deprecated('Use modelTypePBDescriptor instead')
const ModelTypePB$json = {
  '1': 'ModelTypePB',
  '2': [
    {'1': 'LocalAI', '2': 0},
    {'1': 'RemoteAI', '2': 1},
  ],
};

/// Descriptor for `ModelTypePB`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelTypePBDescriptor = $convert.base64Decode(
    'CgtNb2RlbFR5cGVQQhILCgdMb2NhbEFJEAASDAoIUmVtb3RlQUkQAQ==');

@$core.Deprecated('Use pendingResourceTypePBDescriptor instead')
const PendingResourceTypePB$json = {
  '1': 'PendingResourceTypePB',
  '2': [
    {'1': 'LocalAIAppRes', '2': 0},
    {'1': 'ModelRes', '2': 1},
  ],
};

/// Descriptor for `PendingResourceTypePB`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List pendingResourceTypePBDescriptor = $convert.base64Decode(
    'ChVQZW5kaW5nUmVzb3VyY2VUeXBlUEISEQoNTG9jYWxBSUFwcFJlcxAAEgwKCE1vZGVsUmVzEA'
    'E=');

@$core.Deprecated('Use runningStatePBDescriptor instead')
const RunningStatePB$json = {
  '1': 'RunningStatePB',
  '2': [
    {'1': 'ReadyToRun', '2': 0},
    {'1': 'Connecting', '2': 1},
    {'1': 'Connected', '2': 2},
    {'1': 'Running', '2': 3},
    {'1': 'Stopped', '2': 4},
  ],
};

/// Descriptor for `RunningStatePB`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List runningStatePBDescriptor = $convert.base64Decode(
    'Cg5SdW5uaW5nU3RhdGVQQhIOCgpSZWFkeVRvUnVuEAASDgoKQ29ubmVjdGluZxABEg0KCUNvbm'
    '5lY3RlZBACEgsKB1J1bm5pbmcQAxILCgdTdG9wcGVkEAQ=');

@$core.Deprecated('Use responseImageFormatPBDescriptor instead')
const ResponseImageFormatPB$json = {
  '1': 'ResponseImageFormatPB',
  '2': [
    {'1': 'TextOnly', '2': 0},
    {'1': 'ImageOnly', '2': 1},
    {'1': 'TextAndImage', '2': 2},
  ],
};

/// Descriptor for `ResponseImageFormatPB`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List responseImageFormatPBDescriptor = $convert.base64Decode(
    'ChVSZXNwb25zZUltYWdlRm9ybWF0UEISDAoIVGV4dE9ubHkQABINCglJbWFnZU9ubHkQARIQCg'
    'xUZXh0QW5kSW1hZ2UQAg==');

@$core.Deprecated('Use responseTextFormatPBDescriptor instead')
const ResponseTextFormatPB$json = {
  '1': 'ResponseTextFormatPB',
  '2': [
    {'1': 'Paragraph', '2': 0},
    {'1': 'BulletedList', '2': 1},
    {'1': 'NumberedList', '2': 2},
    {'1': 'Table', '2': 3},
  ],
};

/// Descriptor for `ResponseTextFormatPB`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List responseTextFormatPBDescriptor = $convert.base64Decode(
    'ChRSZXNwb25zZVRleHRGb3JtYXRQQhINCglQYXJhZ3JhcGgQABIQCgxCdWxsZXRlZExpc3QQAR'
    'IQCgxOdW1iZXJlZExpc3QQAhIJCgVUYWJsZRAD');

@$core.Deprecated('Use lackOfAIResourceTypePBDescriptor instead')
const LackOfAIResourceTypePB$json = {
  '1': 'LackOfAIResourceTypePB',
  '2': [
    {'1': 'PluginExecutableNotReady', '2': 0},
    {'1': 'OllamaServerNotReady', '2': 1},
    {'1': 'MissingModel', '2': 2},
  ],
};

/// Descriptor for `LackOfAIResourceTypePB`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List lackOfAIResourceTypePBDescriptor = $convert.base64Decode(
    'ChZMYWNrT2ZBSVJlc291cmNlVHlwZVBCEhwKGFBsdWdpbkV4ZWN1dGFibGVOb3RSZWFkeRAAEh'
    'gKFE9sbGFtYVNlcnZlck5vdFJlYWR5EAESEAoMTWlzc2luZ01vZGVsEAI=');

@$core.Deprecated('Use chatIdDescriptor instead')
const ChatId$json = {
  '1': 'ChatId',
  '2': [
    {'1': 'value', '3': 1, '4': 1, '5': 9, '10': 'value'},
  ],
};

/// Descriptor for `ChatId`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatIdDescriptor = $convert.base64Decode(
    'CgZDaGF0SWQSFAoFdmFsdWUYASABKAlSBXZhbHVl');

@$core.Deprecated('Use chatInfoPBDescriptor instead')
const ChatInfoPB$json = {
  '1': 'ChatInfoPB',
  '2': [
    {'1': 'chat_id', '3': 1, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'files', '3': 2, '4': 3, '5': 11, '6': '.FilePB', '10': 'files'},
  ],
};

/// Descriptor for `ChatInfoPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatInfoPBDescriptor = $convert.base64Decode(
    'CgpDaGF0SW5mb1BCEhcKB2NoYXRfaWQYASABKAlSBmNoYXRJZBIdCgVmaWxlcxgCIAMoCzIHLk'
    'ZpbGVQQlIFZmlsZXM=');

@$core.Deprecated('Use filePBDescriptor instead')
const FilePB$json = {
  '1': 'FilePB',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `FilePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filePBDescriptor = $convert.base64Decode(
    'CgZGaWxlUEISDgoCaWQYASABKAlSAmlkEhIKBG5hbWUYAiABKAlSBG5hbWU=');

@$core.Deprecated('Use sendChatPayloadPBDescriptor instead')
const SendChatPayloadPB$json = {
  '1': 'SendChatPayloadPB',
  '2': [
    {'1': 'chat_id', '3': 1, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'message_type', '3': 3, '4': 1, '5': 14, '6': '.ChatMessageTypePB', '10': 'messageType'},
  ],
};

/// Descriptor for `SendChatPayloadPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendChatPayloadPBDescriptor = $convert.base64Decode(
    'ChFTZW5kQ2hhdFBheWxvYWRQQhIXCgdjaGF0X2lkGAEgASgJUgZjaGF0SWQSGAoHbWVzc2FnZR'
    'gCIAEoCVIHbWVzc2FnZRI1CgxtZXNzYWdlX3R5cGUYAyABKA4yEi5DaGF0TWVzc2FnZVR5cGVQ'
    'QlILbWVzc2FnZVR5cGU=');

@$core.Deprecated('Use streamChatPayloadPBDescriptor instead')
const StreamChatPayloadPB$json = {
  '1': 'StreamChatPayloadPB',
  '2': [
    {'1': 'chat_id', '3': 1, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'message_type', '3': 3, '4': 1, '5': 14, '6': '.ChatMessageTypePB', '10': 'messageType'},
    {'1': 'answer_stream_port', '3': 4, '4': 1, '5': 3, '10': 'answerStreamPort'},
    {'1': 'question_stream_port', '3': 5, '4': 1, '5': 3, '10': 'questionStreamPort'},
    {'1': 'format', '3': 6, '4': 1, '5': 11, '6': '.PredefinedFormatPB', '9': 0, '10': 'format'},
    {'1': 'prompt_id', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'promptId'},
    {'1': 'model', '3': 8, '4': 1, '5': 11, '6': '.AIModelPB', '9': 2, '10': 'model'},
    {'1': 'enable_thinking', '3': 9, '4': 1, '5': 8, '10': 'enableThinking'},
    {'1': 'enable_web_search', '3': 10, '4': 1, '5': 8, '10': 'enableWebSearch'},
    {'1': 'images', '3': 11, '4': 3, '5': 9, '10': 'images'},
    {'1': 'has_images', '3': 12, '4': 1, '5': 8, '10': 'hasImages'},
  ],
  '8': [
    {'1': 'one_of_format'},
    {'1': 'one_of_prompt_id'},
    {'1': 'one_of_model'},
  ],
};

/// Descriptor for `StreamChatPayloadPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamChatPayloadPBDescriptor = $convert.base64Decode(
    'ChNTdHJlYW1DaGF0UGF5bG9hZFBCEhcKB2NoYXRfaWQYASABKAlSBmNoYXRJZBIYCgdtZXNzYW'
    'dlGAIgASgJUgdtZXNzYWdlEjUKDG1lc3NhZ2VfdHlwZRgDIAEoDjISLkNoYXRNZXNzYWdlVHlw'
    'ZVBCUgttZXNzYWdlVHlwZRIsChJhbnN3ZXJfc3RyZWFtX3BvcnQYBCABKANSEGFuc3dlclN0cm'
    'VhbVBvcnQSMAoUcXVlc3Rpb25fc3RyZWFtX3BvcnQYBSABKANSEnF1ZXN0aW9uU3RyZWFtUG9y'
    'dBItCgZmb3JtYXQYBiABKAsyEy5QcmVkZWZpbmVkRm9ybWF0UEJIAFIGZm9ybWF0Eh0KCXByb2'
    '1wdF9pZBgHIAEoCUgBUghwcm9tcHRJZBIiCgVtb2RlbBgIIAEoCzIKLkFJTW9kZWxQQkgCUgVt'
    'b2RlbBInCg9lbmFibGVfdGhpbmtpbmcYCSABKAhSDmVuYWJsZVRoaW5raW5nEioKEWVuYWJsZV'
    '93ZWJfc2VhcmNoGAogASgIUg9lbmFibGVXZWJTZWFyY2gSFgoGaW1hZ2VzGAsgAygJUgZpbWFn'
    'ZXMSHQoKaGFzX2ltYWdlcxgMIAEoCFIJaGFzSW1hZ2VzQg8KDW9uZV9vZl9mb3JtYXRCEgoQb2'
    '5lX29mX3Byb21wdF9pZEIOCgxvbmVfb2ZfbW9kZWw=');

@$core.Deprecated('Use regenerateResponsePBDescriptor instead')
const RegenerateResponsePB$json = {
  '1': 'RegenerateResponsePB',
  '2': [
    {'1': 'chat_id', '3': 1, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'answer_message_id', '3': 2, '4': 1, '5': 3, '10': 'answerMessageId'},
    {'1': 'answer_stream_port', '3': 3, '4': 1, '5': 3, '10': 'answerStreamPort'},
    {'1': 'format', '3': 4, '4': 1, '5': 11, '6': '.PredefinedFormatPB', '9': 0, '10': 'format'},
    {'1': 'model', '3': 5, '4': 1, '5': 11, '6': '.AIModelPB', '9': 1, '10': 'model'},
  ],
  '8': [
    {'1': 'one_of_format'},
    {'1': 'one_of_model'},
  ],
};

/// Descriptor for `RegenerateResponsePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List regenerateResponsePBDescriptor = $convert.base64Decode(
    'ChRSZWdlbmVyYXRlUmVzcG9uc2VQQhIXCgdjaGF0X2lkGAEgASgJUgZjaGF0SWQSKgoRYW5zd2'
    'VyX21lc3NhZ2VfaWQYAiABKANSD2Fuc3dlck1lc3NhZ2VJZBIsChJhbnN3ZXJfc3RyZWFtX3Bv'
    'cnQYAyABKANSEGFuc3dlclN0cmVhbVBvcnQSLQoGZm9ybWF0GAQgASgLMhMuUHJlZGVmaW5lZE'
    'Zvcm1hdFBCSABSBmZvcm1hdBIiCgVtb2RlbBgFIAEoCzIKLkFJTW9kZWxQQkgBUgVtb2RlbEIP'
    'Cg1vbmVfb2ZfZm9ybWF0Qg4KDG9uZV9vZl9tb2RlbA==');

@$core.Deprecated('Use chatMessageMetaPBDescriptor instead')
const ChatMessageMetaPB$json = {
  '1': 'ChatMessageMetaPB',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'data', '3': 3, '4': 1, '5': 9, '10': 'data'},
    {'1': 'loader_type', '3': 4, '4': 1, '5': 14, '6': '.ContextLoaderTypePB', '10': 'loaderType'},
    {'1': 'source', '3': 5, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `ChatMessageMetaPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatMessageMetaPBDescriptor = $convert.base64Decode(
    'ChFDaGF0TWVzc2FnZU1ldGFQQhIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZR'
    'ISCgRkYXRhGAMgASgJUgRkYXRhEjUKC2xvYWRlcl90eXBlGAQgASgOMhQuQ29udGV4dExvYWRl'
    'clR5cGVQQlIKbG9hZGVyVHlwZRIWCgZzb3VyY2UYBSABKAlSBnNvdXJjZQ==');

@$core.Deprecated('Use stopStreamPBDescriptor instead')
const StopStreamPB$json = {
  '1': 'StopStreamPB',
  '2': [
    {'1': 'chat_id', '3': 1, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `StopStreamPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stopStreamPBDescriptor = $convert.base64Decode(
    'CgxTdG9wU3RyZWFtUEISFwoHY2hhdF9pZBgBIAEoCVIGY2hhdElk');

@$core.Deprecated('Use loadPrevChatMessagePBDescriptor instead')
const LoadPrevChatMessagePB$json = {
  '1': 'LoadPrevChatMessagePB',
  '2': [
    {'1': 'chat_id', '3': 1, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'limit', '3': 2, '4': 1, '5': 3, '10': 'limit'},
    {'1': 'before_message_id', '3': 4, '4': 1, '5': 3, '9': 0, '10': 'beforeMessageId'},
  ],
  '8': [
    {'1': 'one_of_before_message_id'},
  ],
};

/// Descriptor for `LoadPrevChatMessagePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loadPrevChatMessagePBDescriptor = $convert.base64Decode(
    'ChVMb2FkUHJldkNoYXRNZXNzYWdlUEISFwoHY2hhdF9pZBgBIAEoCVIGY2hhdElkEhQKBWxpbW'
    'l0GAIgASgDUgVsaW1pdBIsChFiZWZvcmVfbWVzc2FnZV9pZBgEIAEoA0gAUg9iZWZvcmVNZXNz'
    'YWdlSWRCGgoYb25lX29mX2JlZm9yZV9tZXNzYWdlX2lk');

@$core.Deprecated('Use loadNextChatMessagePBDescriptor instead')
const LoadNextChatMessagePB$json = {
  '1': 'LoadNextChatMessagePB',
  '2': [
    {'1': 'chat_id', '3': 1, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'limit', '3': 2, '4': 1, '5': 3, '10': 'limit'},
    {'1': 'after_message_id', '3': 4, '4': 1, '5': 3, '9': 0, '10': 'afterMessageId'},
  ],
  '8': [
    {'1': 'one_of_after_message_id'},
  ],
};

/// Descriptor for `LoadNextChatMessagePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loadNextChatMessagePBDescriptor = $convert.base64Decode(
    'ChVMb2FkTmV4dENoYXRNZXNzYWdlUEISFwoHY2hhdF9pZBgBIAEoCVIGY2hhdElkEhQKBWxpbW'
    'l0GAIgASgDUgVsaW1pdBIqChBhZnRlcl9tZXNzYWdlX2lkGAQgASgDSABSDmFmdGVyTWVzc2Fn'
    'ZUlkQhkKF29uZV9vZl9hZnRlcl9tZXNzYWdlX2lk');

@$core.Deprecated('Use chatMessageListPBDescriptor instead')
const ChatMessageListPB$json = {
  '1': 'ChatMessageListPB',
  '2': [
    {'1': 'has_more', '3': 1, '4': 1, '5': 8, '10': 'hasMore'},
    {'1': 'messages', '3': 2, '4': 3, '5': 11, '6': '.ChatMessagePB', '10': 'messages'},
    {'1': 'total', '3': 3, '4': 1, '5': 3, '10': 'total'},
  ],
};

/// Descriptor for `ChatMessageListPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatMessageListPBDescriptor = $convert.base64Decode(
    'ChFDaGF0TWVzc2FnZUxpc3RQQhIZCghoYXNfbW9yZRgBIAEoCFIHaGFzTW9yZRIqCghtZXNzYW'
    'dlcxgCIAMoCzIOLkNoYXRNZXNzYWdlUEJSCG1lc3NhZ2VzEhQKBXRvdGFsGAMgASgDUgV0b3Rh'
    'bA==');

@$core.Deprecated('Use serverModelSelectionPBDescriptor instead')
const ServerModelSelectionPB$json = {
  '1': 'ServerModelSelectionPB',
  '2': [
    {'1': 'models', '3': 1, '4': 3, '5': 11, '6': '.AvailableModelPB', '10': 'models'},
  ],
};

/// Descriptor for `ServerModelSelectionPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverModelSelectionPBDescriptor = $convert.base64Decode(
    'ChZTZXJ2ZXJNb2RlbFNlbGVjdGlvblBCEikKBm1vZGVscxgBIAMoCzIRLkF2YWlsYWJsZU1vZG'
    'VsUEJSBm1vZGVscw==');

@$core.Deprecated('Use availableModelPBDescriptor instead')
const AvailableModelPB$json = {
  '1': 'AvailableModelPB',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'is_default', '3': 2, '4': 1, '5': 8, '10': 'isDefault'},
    {'1': 'desc', '3': 3, '4': 1, '5': 9, '10': 'desc'},
  ],
};

/// Descriptor for `AvailableModelPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List availableModelPBDescriptor = $convert.base64Decode(
    'ChBBdmFpbGFibGVNb2RlbFBCEhIKBG5hbWUYASABKAlSBG5hbWUSHQoKaXNfZGVmYXVsdBgCIA'
    'EoCFIJaXNEZWZhdWx0EhIKBGRlc2MYAyABKAlSBGRlc2M=');

@$core.Deprecated('Use modelSourcePBDescriptor instead')
const ModelSourcePB$json = {
  '1': 'ModelSourcePB',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `ModelSourcePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelSourcePBDescriptor = $convert.base64Decode(
    'Cg1Nb2RlbFNvdXJjZVBCEhYKBnNvdXJjZRgBIAEoCVIGc291cmNl');

@$core.Deprecated('Use updateSelectedModelPBDescriptor instead')
const UpdateSelectedModelPB$json = {
  '1': 'UpdateSelectedModelPB',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
    {'1': 'selected_model', '3': 2, '4': 1, '5': 11, '6': '.AIModelPB', '10': 'selectedModel'},
  ],
};

/// Descriptor for `UpdateSelectedModelPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateSelectedModelPBDescriptor = $convert.base64Decode(
    'ChVVcGRhdGVTZWxlY3RlZE1vZGVsUEISFgoGc291cmNlGAEgASgJUgZzb3VyY2USMQoOc2VsZW'
    'N0ZWRfbW9kZWwYAiABKAsyCi5BSU1vZGVsUEJSDXNlbGVjdGVkTW9kZWw=');

@$core.Deprecated('Use modelSelectionPBDescriptor instead')
const ModelSelectionPB$json = {
  '1': 'ModelSelectionPB',
  '2': [
    {'1': 'models', '3': 1, '4': 3, '5': 11, '6': '.AIModelPB', '10': 'models'},
    {'1': 'selected_model', '3': 2, '4': 1, '5': 11, '6': '.AIModelPB', '10': 'selectedModel'},
  ],
};

/// Descriptor for `ModelSelectionPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelSelectionPBDescriptor = $convert.base64Decode(
    'ChBNb2RlbFNlbGVjdGlvblBCEiIKBm1vZGVscxgBIAMoCzIKLkFJTW9kZWxQQlIGbW9kZWxzEj'
    'EKDnNlbGVjdGVkX21vZGVsGAIgASgLMgouQUlNb2RlbFBCUg1zZWxlY3RlZE1vZGVs');

@$core.Deprecated('Use repeatedAIModelPBDescriptor instead')
const RepeatedAIModelPB$json = {
  '1': 'RepeatedAIModelPB',
  '2': [
    {'1': 'items', '3': 1, '4': 3, '5': 11, '6': '.AIModelPB', '10': 'items'},
  ],
};

/// Descriptor for `RepeatedAIModelPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List repeatedAIModelPBDescriptor = $convert.base64Decode(
    'ChFSZXBlYXRlZEFJTW9kZWxQQhIgCgVpdGVtcxgBIAMoCzIKLkFJTW9kZWxQQlIFaXRlbXM=');

@$core.Deprecated('Use aIModelPBDescriptor instead')
const AIModelPB$json = {
  '1': 'AIModelPB',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'is_local', '3': 2, '4': 1, '5': 8, '10': 'isLocal'},
    {'1': 'desc', '3': 3, '4': 1, '5': 9, '10': 'desc'},
  ],
};

/// Descriptor for `AIModelPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List aIModelPBDescriptor = $convert.base64Decode(
    'CglBSU1vZGVsUEISEgoEbmFtZRgBIAEoCVIEbmFtZRIZCghpc19sb2NhbBgCIAEoCFIHaXNMb2'
    'NhbBISCgRkZXNjGAMgASgJUgRkZXNj');

@$core.Deprecated('Use chatMessagePBDescriptor instead')
const ChatMessagePB$json = {
  '1': 'ChatMessagePB',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 3, '10': 'messageId'},
    {'1': 'content', '3': 2, '4': 1, '5': 9, '10': 'content'},
    {'1': 'created_at', '3': 3, '4': 1, '5': 3, '10': 'createdAt'},
    {'1': 'author_type', '3': 4, '4': 1, '5': 3, '10': 'authorType'},
    {'1': 'author_id', '3': 5, '4': 1, '5': 9, '10': 'authorId'},
    {'1': 'reply_message_id', '3': 6, '4': 1, '5': 3, '9': 0, '10': 'replyMessageId'},
    {'1': 'metadata', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'metadata'},
  ],
  '8': [
    {'1': 'one_of_reply_message_id'},
    {'1': 'one_of_metadata'},
  ],
};

/// Descriptor for `ChatMessagePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatMessagePBDescriptor = $convert.base64Decode(
    'Cg1DaGF0TWVzc2FnZVBCEh0KCm1lc3NhZ2VfaWQYASABKANSCW1lc3NhZ2VJZBIYCgdjb250ZW'
    '50GAIgASgJUgdjb250ZW50Eh0KCmNyZWF0ZWRfYXQYAyABKANSCWNyZWF0ZWRBdBIfCgthdXRo'
    'b3JfdHlwZRgEIAEoA1IKYXV0aG9yVHlwZRIbCglhdXRob3JfaWQYBSABKAlSCGF1dGhvcklkEi'
    'oKEHJlcGx5X21lc3NhZ2VfaWQYBiABKANIAFIOcmVwbHlNZXNzYWdlSWQSHAoIbWV0YWRhdGEY'
    'ByABKAlIAVIIbWV0YWRhdGFCGQoXb25lX29mX3JlcGx5X21lc3NhZ2VfaWRCEQoPb25lX29mX2'
    '1ldGFkYXRh');

@$core.Deprecated('Use chatMessageErrorPBDescriptor instead')
const ChatMessageErrorPB$json = {
  '1': 'ChatMessageErrorPB',
  '2': [
    {'1': 'chat_id', '3': 1, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'error_message', '3': 2, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `ChatMessageErrorPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatMessageErrorPBDescriptor = $convert.base64Decode(
    'ChJDaGF0TWVzc2FnZUVycm9yUEISFwoHY2hhdF9pZBgBIAEoCVIGY2hhdElkEiMKDWVycm9yX2'
    '1lc3NhZ2UYAiABKAlSDGVycm9yTWVzc2FnZQ==');

@$core.Deprecated('Use repeatedChatMessagePBDescriptor instead')
const RepeatedChatMessagePB$json = {
  '1': 'RepeatedChatMessagePB',
  '2': [
    {'1': 'items', '3': 1, '4': 3, '5': 11, '6': '.ChatMessagePB', '10': 'items'},
  ],
};

/// Descriptor for `RepeatedChatMessagePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List repeatedChatMessagePBDescriptor = $convert.base64Decode(
    'ChVSZXBlYXRlZENoYXRNZXNzYWdlUEISJAoFaXRlbXMYASADKAsyDi5DaGF0TWVzc2FnZVBCUg'
    'VpdGVtcw==');

@$core.Deprecated('Use chatMessageIdPBDescriptor instead')
const ChatMessageIdPB$json = {
  '1': 'ChatMessageIdPB',
  '2': [
    {'1': 'chat_id', '3': 1, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'message_id', '3': 2, '4': 1, '5': 3, '10': 'messageId'},
  ],
};

/// Descriptor for `ChatMessageIdPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatMessageIdPBDescriptor = $convert.base64Decode(
    'Cg9DaGF0TWVzc2FnZUlkUEISFwoHY2hhdF9pZBgBIAEoCVIGY2hhdElkEh0KCm1lc3NhZ2VfaW'
    'QYAiABKANSCW1lc3NhZ2VJZA==');

@$core.Deprecated('Use relatedQuestionPBDescriptor instead')
const RelatedQuestionPB$json = {
  '1': 'RelatedQuestionPB',
  '2': [
    {'1': 'content', '3': 1, '4': 1, '5': 9, '10': 'content'},
  ],
};

/// Descriptor for `RelatedQuestionPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relatedQuestionPBDescriptor = $convert.base64Decode(
    'ChFSZWxhdGVkUXVlc3Rpb25QQhIYCgdjb250ZW50GAEgASgJUgdjb250ZW50');

@$core.Deprecated('Use repeatedRelatedQuestionPBDescriptor instead')
const RepeatedRelatedQuestionPB$json = {
  '1': 'RepeatedRelatedQuestionPB',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 3, '10': 'messageId'},
    {'1': 'items', '3': 2, '4': 3, '5': 11, '6': '.RelatedQuestionPB', '10': 'items'},
  ],
};

/// Descriptor for `RepeatedRelatedQuestionPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List repeatedRelatedQuestionPBDescriptor = $convert.base64Decode(
    'ChlSZXBlYXRlZFJlbGF0ZWRRdWVzdGlvblBCEh0KCm1lc3NhZ2VfaWQYASABKANSCW1lc3NhZ2'
    'VJZBIoCgVpdGVtcxgCIAMoCzISLlJlbGF0ZWRRdWVzdGlvblBCUgVpdGVtcw==');

@$core.Deprecated('Use lLMModelPBDescriptor instead')
const LLMModelPB$json = {
  '1': 'LLMModelPB',
  '2': [
    {'1': 'llm_id', '3': 1, '4': 1, '5': 3, '10': 'llmId'},
    {'1': 'embedding_model', '3': 2, '4': 1, '5': 9, '10': 'embeddingModel'},
    {'1': 'chat_model', '3': 3, '4': 1, '5': 9, '10': 'chatModel'},
    {'1': 'requirement', '3': 4, '4': 1, '5': 9, '10': 'requirement'},
    {'1': 'file_size', '3': 5, '4': 1, '5': 3, '10': 'fileSize'},
  ],
};

/// Descriptor for `LLMModelPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMModelPBDescriptor = $convert.base64Decode(
    'CgpMTE1Nb2RlbFBCEhUKBmxsbV9pZBgBIAEoA1IFbGxtSWQSJwoPZW1iZWRkaW5nX21vZGVsGA'
    'IgASgJUg5lbWJlZGRpbmdNb2RlbBIdCgpjaGF0X21vZGVsGAMgASgJUgljaGF0TW9kZWwSIAoL'
    'cmVxdWlyZW1lbnQYBCABKAlSC3JlcXVpcmVtZW50EhsKCWZpbGVfc2l6ZRgFIAEoA1IIZmlsZV'
    'NpemU=');

@$core.Deprecated('Use completeTextPBDescriptor instead')
const CompleteTextPB$json = {
  '1': 'CompleteTextPB',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'completion_type', '3': 2, '4': 1, '5': 14, '6': '.CompletionTypePB', '10': 'completionType'},
    {'1': 'format', '3': 3, '4': 1, '5': 11, '6': '.PredefinedFormatPB', '9': 0, '10': 'format'},
    {'1': 'stream_port', '3': 4, '4': 1, '5': 3, '10': 'streamPort'},
    {'1': 'object_id', '3': 5, '4': 1, '5': 9, '10': 'objectId'},
    {'1': 'rag_ids', '3': 6, '4': 3, '5': 9, '10': 'ragIds'},
    {'1': 'history', '3': 7, '4': 3, '5': 11, '6': '.CompletionRecordPB', '10': 'history'},
    {'1': 'custom_prompt', '3': 8, '4': 1, '5': 9, '9': 1, '10': 'customPrompt'},
    {'1': 'prompt_id', '3': 9, '4': 1, '5': 9, '9': 2, '10': 'promptId'},
    {'1': 'enable_thinking', '3': 10, '4': 1, '5': 8, '10': 'enableThinking'},
    {'1': 'enable_web_search', '3': 11, '4': 1, '5': 8, '10': 'enableWebSearch'},
    {'1': 'images', '3': 12, '4': 3, '5': 9, '10': 'images'},
    {'1': 'has_images', '3': 13, '4': 1, '5': 8, '10': 'hasImages'},
  ],
  '8': [
    {'1': 'one_of_format'},
    {'1': 'one_of_custom_prompt'},
    {'1': 'one_of_prompt_id'},
  ],
};

/// Descriptor for `CompleteTextPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List completeTextPBDescriptor = $convert.base64Decode(
    'Cg5Db21wbGV0ZVRleHRQQhISCgR0ZXh0GAEgASgJUgR0ZXh0EjoKD2NvbXBsZXRpb25fdHlwZR'
    'gCIAEoDjIRLkNvbXBsZXRpb25UeXBlUEJSDmNvbXBsZXRpb25UeXBlEi0KBmZvcm1hdBgDIAEo'
    'CzITLlByZWRlZmluZWRGb3JtYXRQQkgAUgZmb3JtYXQSHwoLc3RyZWFtX3BvcnQYBCABKANSCn'
    'N0cmVhbVBvcnQSGwoJb2JqZWN0X2lkGAUgASgJUghvYmplY3RJZBIXCgdyYWdfaWRzGAYgAygJ'
    'UgZyYWdJZHMSLQoHaGlzdG9yeRgHIAMoCzITLkNvbXBsZXRpb25SZWNvcmRQQlIHaGlzdG9yeR'
    'IlCg1jdXN0b21fcHJvbXB0GAggASgJSAFSDGN1c3RvbVByb21wdBIdCglwcm9tcHRfaWQYCSAB'
    'KAlIAlIIcHJvbXB0SWQSJwoPZW5hYmxlX3RoaW5raW5nGAogASgIUg5lbmFibGVUaGlua2luZx'
    'IqChFlbmFibGVfd2ViX3NlYXJjaBgLIAEoCFIPZW5hYmxlV2ViU2VhcmNoEhYKBmltYWdlcxgM'
    'IAMoCVIGaW1hZ2VzEh0KCmhhc19pbWFnZXMYDSABKAhSCWhhc0ltYWdlc0IPCg1vbmVfb2ZfZm'
    '9ybWF0QhYKFG9uZV9vZl9jdXN0b21fcHJvbXB0QhIKEG9uZV9vZl9wcm9tcHRfaWQ=');

@$core.Deprecated('Use completeTextTaskPBDescriptor instead')
const CompleteTextTaskPB$json = {
  '1': 'CompleteTextTaskPB',
  '2': [
    {'1': 'task_id', '3': 1, '4': 1, '5': 9, '10': 'taskId'},
  ],
};

/// Descriptor for `CompleteTextTaskPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List completeTextTaskPBDescriptor = $convert.base64Decode(
    'ChJDb21wbGV0ZVRleHRUYXNrUEISFwoHdGFza19pZBgBIAEoCVIGdGFza0lk');

@$core.Deprecated('Use completionRecordPBDescriptor instead')
const CompletionRecordPB$json = {
  '1': 'CompletionRecordPB',
  '2': [
    {'1': 'role', '3': 1, '4': 1, '5': 14, '6': '.ChatMessageTypePB', '10': 'role'},
    {'1': 'content', '3': 2, '4': 1, '5': 9, '10': 'content'},
  ],
};

/// Descriptor for `CompletionRecordPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List completionRecordPBDescriptor = $convert.base64Decode(
    'ChJDb21wbGV0aW9uUmVjb3JkUEISJgoEcm9sZRgBIAEoDjISLkNoYXRNZXNzYWdlVHlwZVBCUg'
    'Ryb2xlEhgKB2NvbnRlbnQYAiABKAlSB2NvbnRlbnQ=');

@$core.Deprecated('Use chatStatePBDescriptor instead')
const ChatStatePB$json = {
  '1': 'ChatStatePB',
  '2': [
    {'1': 'model_type', '3': 1, '4': 1, '5': 14, '6': '.ModelTypePB', '10': 'modelType'},
    {'1': 'available', '3': 2, '4': 1, '5': 8, '10': 'available'},
  ],
};

/// Descriptor for `ChatStatePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatStatePBDescriptor = $convert.base64Decode(
    'CgtDaGF0U3RhdGVQQhIrCgptb2RlbF90eXBlGAEgASgOMgwuTW9kZWxUeXBlUEJSCW1vZGVsVH'
    'lwZRIcCglhdmFpbGFibGUYAiABKAhSCWF2YWlsYWJsZQ==');

@$core.Deprecated('Use chatFilePBDescriptor instead')
const ChatFilePB$json = {
  '1': 'ChatFilePB',
  '2': [
    {'1': 'file_path', '3': 1, '4': 1, '5': 9, '10': 'filePath'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `ChatFilePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatFilePBDescriptor = $convert.base64Decode(
    'CgpDaGF0RmlsZVBCEhsKCWZpbGVfcGF0aBgBIAEoCVIIZmlsZVBhdGgSFwoHY2hhdF9pZBgCIA'
    'EoCVIGY2hhdElk');

@$core.Deprecated('Use localModelStatePBDescriptor instead')
const LocalModelStatePB$json = {
  '1': 'LocalModelStatePB',
  '2': [
    {'1': 'model_name', '3': 1, '4': 1, '5': 9, '10': 'modelName'},
    {'1': 'model_size', '3': 2, '4': 1, '5': 9, '10': 'modelSize'},
    {'1': 'need_download', '3': 3, '4': 1, '5': 8, '10': 'needDownload'},
    {'1': 'requirements', '3': 4, '4': 1, '5': 9, '10': 'requirements'},
    {'1': 'is_downloading', '3': 5, '4': 1, '5': 8, '10': 'isDownloading'},
  ],
};

/// Descriptor for `LocalModelStatePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List localModelStatePBDescriptor = $convert.base64Decode(
    'ChFMb2NhbE1vZGVsU3RhdGVQQhIdCgptb2RlbF9uYW1lGAEgASgJUgltb2RlbE5hbWUSHQoKbW'
    '9kZWxfc2l6ZRgCIAEoCVIJbW9kZWxTaXplEiMKDW5lZWRfZG93bmxvYWQYAyABKAhSDG5lZWRE'
    'b3dubG9hZBIiCgxyZXF1aXJlbWVudHMYBCABKAlSDHJlcXVpcmVtZW50cxIlCg5pc19kb3dubG'
    '9hZGluZxgFIAEoCFINaXNEb3dubG9hZGluZw==');

@$core.Deprecated('Use pendingResourcePBDescriptor instead')
const PendingResourcePB$json = {
  '1': 'PendingResourcePB',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'file_size', '3': 2, '4': 1, '5': 9, '10': 'fileSize'},
    {'1': 'requirements', '3': 3, '4': 1, '5': 9, '10': 'requirements'},
    {'1': 'res_type', '3': 4, '4': 1, '5': 14, '6': '.PendingResourceTypePB', '10': 'resType'},
  ],
};

/// Descriptor for `PendingResourcePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pendingResourcePBDescriptor = $convert.base64Decode(
    'ChFQZW5kaW5nUmVzb3VyY2VQQhISCgRuYW1lGAEgASgJUgRuYW1lEhsKCWZpbGVfc2l6ZRgCIA'
    'EoCVIIZmlsZVNpemUSIgoMcmVxdWlyZW1lbnRzGAMgASgJUgxyZXF1aXJlbWVudHMSMQoIcmVz'
    'X3R5cGUYBCABKA4yFi5QZW5kaW5nUmVzb3VyY2VUeXBlUEJSB3Jlc1R5cGU=');

@$core.Deprecated('Use localAIPBDescriptor instead')
const LocalAIPB$json = {
  '1': 'LocalAIPB',
  '2': [
    {'1': 'enabled', '3': 1, '4': 1, '5': 8, '10': 'enabled'},
    {'1': 'lack_of_resource', '3': 2, '4': 1, '5': 11, '6': '.LackOfAIResourcePB', '9': 0, '10': 'lackOfResource'},
    {'1': 'is_ready', '3': 3, '4': 1, '5': 8, '10': 'isReady'},
  ],
  '8': [
    {'1': 'one_of_lack_of_resource'},
  ],
};

/// Descriptor for `LocalAIPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List localAIPBDescriptor = $convert.base64Decode(
    'CglMb2NhbEFJUEISGAoHZW5hYmxlZBgBIAEoCFIHZW5hYmxlZBI/ChBsYWNrX29mX3Jlc291cm'
    'NlGAIgASgLMhMuTGFja09mQUlSZXNvdXJjZVBCSABSDmxhY2tPZlJlc291cmNlEhkKCGlzX3Jl'
    'YWR5GAMgASgIUgdpc1JlYWR5QhkKF29uZV9vZl9sYWNrX29mX3Jlc291cmNl');

@$core.Deprecated('Use createChatContextPBDescriptor instead')
const CreateChatContextPB$json = {
  '1': 'CreateChatContextPB',
  '2': [
    {'1': 'content_type', '3': 1, '4': 1, '5': 9, '10': 'contentType'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    {'1': 'metadata', '3': 3, '4': 3, '5': 11, '6': '.CreateChatContextPB.MetadataEntry', '10': 'metadata'},
    {'1': 'chat_id', '3': 4, '4': 1, '5': 9, '10': 'chatId'},
  ],
  '3': [CreateChatContextPB_MetadataEntry$json],
};

@$core.Deprecated('Use createChatContextPBDescriptor instead')
const CreateChatContextPB_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `CreateChatContextPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createChatContextPBDescriptor = $convert.base64Decode(
    'ChNDcmVhdGVDaGF0Q29udGV4dFBCEiEKDGNvbnRlbnRfdHlwZRgBIAEoCVILY29udGVudFR5cG'
    'USEgoEdGV4dBgCIAEoCVIEdGV4dBI+CghtZXRhZGF0YRgDIAMoCzIiLkNyZWF0ZUNoYXRDb250'
    'ZXh0UEIuTWV0YWRhdGFFbnRyeVIIbWV0YWRhdGESFwoHY2hhdF9pZBgEIAEoCVIGY2hhdElkGj'
    'sKDU1ldGFkYXRhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVl'
    'OgI4AQ==');

@$core.Deprecated('Use chatSettingsPBDescriptor instead')
const ChatSettingsPB$json = {
  '1': 'ChatSettingsPB',
  '2': [
    {'1': 'rag_ids', '3': 1, '4': 3, '5': 9, '10': 'ragIds'},
  ],
};

/// Descriptor for `ChatSettingsPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatSettingsPBDescriptor = $convert.base64Decode(
    'Cg5DaGF0U2V0dGluZ3NQQhIXCgdyYWdfaWRzGAEgAygJUgZyYWdJZHM=');

@$core.Deprecated('Use updateChatSettingsPBDescriptor instead')
const UpdateChatSettingsPB$json = {
  '1': 'UpdateChatSettingsPB',
  '2': [
    {'1': 'chat_id', '3': 1, '4': 1, '5': 11, '6': '.ChatId', '10': 'chatId'},
    {'1': 'rag_ids', '3': 2, '4': 3, '5': 9, '10': 'ragIds'},
  ],
};

/// Descriptor for `UpdateChatSettingsPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateChatSettingsPBDescriptor = $convert.base64Decode(
    'ChRVcGRhdGVDaGF0U2V0dGluZ3NQQhIgCgdjaGF0X2lkGAEgASgLMgcuQ2hhdElkUgZjaGF0SW'
    'QSFwoHcmFnX2lkcxgCIAMoCVIGcmFnSWRz');

@$core.Deprecated('Use predefinedFormatPBDescriptor instead')
const PredefinedFormatPB$json = {
  '1': 'PredefinedFormatPB',
  '2': [
    {'1': 'image_format', '3': 1, '4': 1, '5': 14, '6': '.ResponseImageFormatPB', '10': 'imageFormat'},
    {'1': 'text_format', '3': 2, '4': 1, '5': 14, '6': '.ResponseTextFormatPB', '9': 0, '10': 'textFormat'},
  ],
  '8': [
    {'1': 'one_of_text_format'},
  ],
};

/// Descriptor for `PredefinedFormatPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List predefinedFormatPBDescriptor = $convert.base64Decode(
    'ChJQcmVkZWZpbmVkRm9ybWF0UEISOQoMaW1hZ2VfZm9ybWF0GAEgASgOMhYuUmVzcG9uc2VJbW'
    'FnZUZvcm1hdFBCUgtpbWFnZUZvcm1hdBI4Cgt0ZXh0X2Zvcm1hdBgCIAEoDjIVLlJlc3BvbnNl'
    'VGV4dEZvcm1hdFBCSABSCnRleHRGb3JtYXRCFAoSb25lX29mX3RleHRfZm9ybWF0');

@$core.Deprecated('Use localAISettingPBDescriptor instead')
const LocalAISettingPB$json = {
  '1': 'LocalAISettingPB',
  '2': [
    {'1': 'server_url', '3': 1, '4': 1, '5': 9, '10': 'serverUrl'},
    {'1': 'global_chat_model', '3': 2, '4': 1, '5': 9, '10': 'globalChatModel'},
    {'1': 'embedding_model_name', '3': 3, '4': 1, '5': 9, '10': 'embeddingModelName'},
    {'1': 'api_key', '3': 4, '4': 1, '5': 9, '10': 'apiKey'},
  ],
};

/// Descriptor for `LocalAISettingPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List localAISettingPBDescriptor = $convert.base64Decode(
    'ChBMb2NhbEFJU2V0dGluZ1BCEh0KCnNlcnZlcl91cmwYASABKAlSCXNlcnZlclVybBIqChFnbG'
    '9iYWxfY2hhdF9tb2RlbBgCIAEoCVIPZ2xvYmFsQ2hhdE1vZGVsEjAKFGVtYmVkZGluZ19tb2Rl'
    'bF9uYW1lGAMgASgJUhJlbWJlZGRpbmdNb2RlbE5hbWUSFwoHYXBpX2tleRgEIAEoCVIGYXBpS2'
    'V5');

@$core.Deprecated('Use lackOfAIResourcePBDescriptor instead')
const LackOfAIResourcePB$json = {
  '1': 'LackOfAIResourcePB',
  '2': [
    {'1': 'resource_type', '3': 1, '4': 1, '5': 14, '6': '.LackOfAIResourceTypePB', '10': 'resourceType'},
    {'1': 'missing_model_names', '3': 2, '4': 3, '5': 9, '10': 'missingModelNames'},
  ],
};

/// Descriptor for `LackOfAIResourcePB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lackOfAIResourcePBDescriptor = $convert.base64Decode(
    'ChJMYWNrT2ZBSVJlc291cmNlUEISPAoNcmVzb3VyY2VfdHlwZRgBIAEoDjIXLkxhY2tPZkFJUm'
    'Vzb3VyY2VUeXBlUEJSDHJlc291cmNlVHlwZRIuChNtaXNzaW5nX21vZGVsX25hbWVzGAIgAygJ'
    'UhFtaXNzaW5nTW9kZWxOYW1lcw==');

@$core.Deprecated('Use customPromptDatabaseViewIdPBDescriptor instead')
const CustomPromptDatabaseViewIdPB$json = {
  '1': 'CustomPromptDatabaseViewIdPB',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
  ],
};

/// Descriptor for `CustomPromptDatabaseViewIdPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List customPromptDatabaseViewIdPBDescriptor = $convert.base64Decode(
    'ChxDdXN0b21Qcm9tcHREYXRhYmFzZVZpZXdJZFBCEg4KAmlkGAEgASgJUgJpZA==');

@$core.Deprecated('Use customPromptDatabaseConfigurationPBDescriptor instead')
const CustomPromptDatabaseConfigurationPB$json = {
  '1': 'CustomPromptDatabaseConfigurationPB',
  '2': [
    {'1': 'view_id', '3': 1, '4': 1, '5': 9, '10': 'viewId'},
    {'1': 'title_field_id', '3': 2, '4': 1, '5': 9, '10': 'titleFieldId'},
    {'1': 'content_field_id', '3': 3, '4': 1, '5': 9, '10': 'contentFieldId'},
    {'1': 'example_field_id', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'exampleFieldId'},
    {'1': 'category_field_id', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'categoryFieldId'},
  ],
  '8': [
    {'1': 'one_of_example_field_id'},
    {'1': 'one_of_category_field_id'},
  ],
};

/// Descriptor for `CustomPromptDatabaseConfigurationPB`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List customPromptDatabaseConfigurationPBDescriptor = $convert.base64Decode(
    'CiNDdXN0b21Qcm9tcHREYXRhYmFzZUNvbmZpZ3VyYXRpb25QQhIXCgd2aWV3X2lkGAEgASgJUg'
    'Z2aWV3SWQSJAoOdGl0bGVfZmllbGRfaWQYAiABKAlSDHRpdGxlRmllbGRJZBIoChBjb250ZW50'
    'X2ZpZWxkX2lkGAMgASgJUg5jb250ZW50RmllbGRJZBIqChBleGFtcGxlX2ZpZWxkX2lkGAQgAS'
    'gJSABSDmV4YW1wbGVGaWVsZElkEiwKEWNhdGVnb3J5X2ZpZWxkX2lkGAUgASgJSAFSD2NhdGVn'
    'b3J5RmllbGRJZEIZChdvbmVfb2ZfZXhhbXBsZV9maWVsZF9pZEIaChhvbmVfb2ZfY2F0ZWdvcn'
    'lfZmllbGRfaWQ=');

