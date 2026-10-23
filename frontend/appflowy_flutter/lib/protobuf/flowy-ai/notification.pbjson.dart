//
//  Generated code. Do not modify.
//  source: notification.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use chatNotificationDescriptor instead')
const ChatNotification$json = {
  '1': 'ChatNotification',
  '2': [
    {'1': 'Unknown', '2': 0},
    {'1': 'DidLoadLatestChatMessage', '2': 1},
    {'1': 'DidLoadPrevChatMessage', '2': 2},
    {'1': 'DidReceiveChatMessage', '2': 3},
    {'1': 'StreamChatMessageError', '2': 4},
    {'1': 'FinishStreaming', '2': 5},
    {'1': 'UpdateLocalAIState', '2': 6},
    {'1': 'DidUpdateChatSettings', '2': 7},
    {'1': 'LocalAIResourceUpdated', '2': 8},
    {'1': 'DidUpdateSelectedModel', '2': 9},
  ],
};

/// Descriptor for `ChatNotification`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List chatNotificationDescriptor = $convert.base64Decode(
    'ChBDaGF0Tm90aWZpY2F0aW9uEgsKB1Vua25vd24QABIcChhEaWRMb2FkTGF0ZXN0Q2hhdE1lc3'
    'NhZ2UQARIaChZEaWRMb2FkUHJldkNoYXRNZXNzYWdlEAISGQoVRGlkUmVjZWl2ZUNoYXRNZXNz'
    'YWdlEAMSGgoWU3RyZWFtQ2hhdE1lc3NhZ2VFcnJvchAEEhMKD0ZpbmlzaFN0cmVhbWluZxAFEh'
    'YKElVwZGF0ZUxvY2FsQUlTdGF0ZRAGEhkKFURpZFVwZGF0ZUNoYXRTZXR0aW5ncxAHEhoKFkxv'
    'Y2FsQUlSZXNvdXJjZVVwZGF0ZWQQCBIaChZEaWRVcGRhdGVTZWxlY3RlZE1vZGVsEAk=');

