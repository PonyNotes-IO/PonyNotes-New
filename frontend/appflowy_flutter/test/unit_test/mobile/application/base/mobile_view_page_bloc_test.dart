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

  test('immersion updates do not finish initial loading', () async {
    final bloc = MobileViewPageBloc(viewId: 'view');
    addTearDown(bloc.close);
    final nextState = bloc.stream.first;

    bloc.add(const MobileViewPageEvent.updateImmersionMode(true));

    expect((await nextState).isLoading, isTrue);
  });

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

  test('uses matching navigation view for transient local errors', () {
    final error = FlowyError(
      code: ErrorCode.NetworkError,
      msg: 'Network error',
    );
    final result = mobileViewResultWithFallback(
      localResult: FlowyResult.failure(error),
      fallbackView: sharedView,
      viewId: sharedView.id,
    );

    expect(result.toNullable(), sharedView);
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
