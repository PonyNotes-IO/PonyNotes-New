import 'dart:convert';

import 'package:appflowy/workspace/application/sidebar/space/space_update_executor.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns failure and skips visibility when updating the view fails',
      () async {
    var visibilityCalls = 0;
    final failure = FlowyError()..msg = 'update failed';
    final executor = SpaceUpdateExecutor(
      updateView: ({required viewId, name, extra}) async =>
          FlowyResult.failure(failure),
      updateVisibility: (views, isPublic) async {
        visibilityCalls++;
        return FlowyResult.success(null);
      },
    );

    final result = await executor.execute(
      space: ViewPB.create()
        ..id = 'space-1'
        ..extra = '{"is_space":true,"space_permission":1}',
      permissionIndex: 0,
      isPublic: true,
    );

    expect(result.isFailure, isTrue);
    expect(result.getFailure(), same(failure));
    expect(visibilityCalls, 0);
  });

  test('updates merged metadata before making the space public', () async {
    final calls = <String>[];
    String? submittedExtra;
    final space = ViewPB.create()
      ..id = 'space-1'
      ..extra = '{"is_space":true,"space_permission":1,"preserved":42}';
    final executor = SpaceUpdateExecutor(
      updateView: ({required viewId, name, extra}) async {
        calls.add('view');
        submittedExtra = extra;
        return FlowyResult.success(space);
      },
      updateVisibility: (views, isPublic) async {
        calls.add('visibility');
        expect(views.map((view) => view.id), ['space-1']);
        expect(isPublic, isTrue);
        return FlowyResult.success(null);
      },
    );

    final result = await executor.execute(
      space: space,
      name: 'Public space',
      icon: 'interface_essential/home-3',
      iconColor: '0xFFA34AFD',
      permissionIndex: 0,
      isPublic: true,
    );

    expect(result.isSuccess, isTrue);
    expect(calls, ['view', 'visibility']);
    expect(
      jsonDecode(submittedExtra!),
      {
        'is_space': true,
        'space_permission': 0,
        'preserved': 42,
        'space_icon': 'interface_essential/home-3',
        'space_icon_color': '0xFFA34AFD',
      },
    );
  });

  test('returns visibility failure after the metadata update succeeds',
      () async {
    final failure = FlowyError()..msg = 'visibility failed';
    final space = ViewPB.create()
      ..id = 'space-1'
      ..extra = '{"is_space":true,"space_permission":1}';
    final executor = SpaceUpdateExecutor(
      updateView: ({required viewId, name, extra}) async =>
          FlowyResult.success(space),
      updateVisibility: (views, isPublic) async => FlowyResult.failure(failure),
    );

    final result = await executor.execute(
      space: space,
      permissionIndex: 0,
      isPublic: true,
    );

    expect(result.isFailure, isTrue);
    expect(result.getFailure(), same(failure));
  });
}
