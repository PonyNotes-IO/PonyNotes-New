import 'package:appflowy/mobile/application/base/mobile_view_page_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sharedView = ViewPB()
    ..id = 'shared-view'
    ..workspaceId = 'owner-workspace';

  test('uses shared navigation view when local metadata is missing', () {
    final result = mobileViewResultWithFallback(
      localResult: FlowyResult.failure(
        FlowyError(
          code: ErrorCode.RecordNotFound,
          msg: 'Record not found',
        ),
      ),
      fallbackView: sharedView,
      viewId: sharedView.id,
    );

    expect(result.toNullable(), sharedView);
  });

  test('does not hide non-record-not-found errors', () {
    final error = FlowyError(
      code: ErrorCode.NetworkError,
      msg: 'Network error',
    );
    final result = mobileViewResultWithFallback(
      localResult: FlowyResult.failure(error),
      fallbackView: sharedView,
      viewId: sharedView.id,
    );

    expect(result.isFailure, isTrue);
    expect(result.getFailure().code, ErrorCode.NetworkError);
  });

  test('does not use fallback from another route', () {
    final result = mobileViewResultWithFallback(
      localResult: FlowyResult.failure(
        FlowyError(
          code: ErrorCode.RecordNotFound,
          msg: 'Record not found',
        ),
      ),
      fallbackView: sharedView,
      viewId: 'another-view',
    );

    expect(result.isFailure, isTrue);
  });
}
