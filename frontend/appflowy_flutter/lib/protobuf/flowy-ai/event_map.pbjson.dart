//
//  Generated code. Do not modify.
//  source: event_map.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use aIEventDescriptor instead')
const AIEvent$json = {
  '1': 'AIEvent',
  '2': [
    {'1': 'LoadPrevMessage', '2': 0},
    {'1': 'LoadNextMessage', '2': 1},
    {'1': 'StreamMessage', '2': 2},
    {'1': 'StopStream', '2': 3},
    {'1': 'GetRelatedQuestion', '2': 4},
    {'1': 'GetAnswerForQuestion', '2': 5},
    {'1': 'CompleteText', '2': 9},
    {'1': 'StopCompleteText', '2': 10},
    {'1': 'ChatWithFile', '2': 11},
    {'1': 'RestartLocalAI', '2': 17},
    {'1': 'ToggleLocalAI', '2': 18},
    {'1': 'GetLocalAIState', '2': 19},
    {'1': 'CreateChatContext', '2': 23},
    {'1': 'GetChatInfo', '2': 24},
    {'1': 'GetChatSettings', '2': 25},
    {'1': 'UpdateChatSettings', '2': 26},
    {'1': 'RegenerateResponse', '2': 27},
    {'1': 'GetLocalAISetting', '2': 29},
    {'1': 'UpdateLocalAISetting', '2': 30},
    {'1': 'GetSettingModelSelection', '2': 31},
    {'1': 'UpdateSelectedModel', '2': 32},
    {'1': 'GetLocalModelSelection', '2': 33},
    {'1': 'GetSourceModelSelection', '2': 34},
    {'1': 'GetCustomPromptDatabaseConfiguration', '2': 35},
    {'1': 'SetCustomPromptDatabaseConfiguration', '2': 36},
  ],
};

/// Descriptor for `AIEvent`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List aIEventDescriptor = $convert.base64Decode(
    'CgdBSUV2ZW50EhMKD0xvYWRQcmV2TWVzc2FnZRAAEhMKD0xvYWROZXh0TWVzc2FnZRABEhEKDV'
    'N0cmVhbU1lc3NhZ2UQAhIOCgpTdG9wU3RyZWFtEAMSFgoSR2V0UmVsYXRlZFF1ZXN0aW9uEAQS'
    'GAoUR2V0QW5zd2VyRm9yUXVlc3Rpb24QBRIQCgxDb21wbGV0ZVRleHQQCRIUChBTdG9wQ29tcG'
    'xldGVUZXh0EAoSEAoMQ2hhdFdpdGhGaWxlEAsSEgoOUmVzdGFydExvY2FsQUkQERIRCg1Ub2dn'
    'bGVMb2NhbEFJEBISEwoPR2V0TG9jYWxBSVN0YXRlEBMSFQoRQ3JlYXRlQ2hhdENvbnRleHQQFx'
    'IPCgtHZXRDaGF0SW5mbxAYEhMKD0dldENoYXRTZXR0aW5ncxAZEhYKElVwZGF0ZUNoYXRTZXR0'
    'aW5ncxAaEhYKElJlZ2VuZXJhdGVSZXNwb25zZRAbEhUKEUdldExvY2FsQUlTZXR0aW5nEB0SGA'
    'oUVXBkYXRlTG9jYWxBSVNldHRpbmcQHhIcChhHZXRTZXR0aW5nTW9kZWxTZWxlY3Rpb24QHxIX'
    'ChNVcGRhdGVTZWxlY3RlZE1vZGVsECASGgoWR2V0TG9jYWxNb2RlbFNlbGVjdGlvbhAhEhsKF0'
    'dldFNvdXJjZU1vZGVsU2VsZWN0aW9uECISKAokR2V0Q3VzdG9tUHJvbXB0RGF0YWJhc2VDb25m'
    'aWd1cmF0aW9uECMSKAokU2V0Q3VzdG9tUHJvbXB0RGF0YWJhc2VDb25maWd1cmF0aW9uECQ=');

