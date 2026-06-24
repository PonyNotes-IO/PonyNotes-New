import 'package:appflowy/features/page_access_level/data/repositories/page_access_level_repository.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// Mock repository for testing
class MockPageAccessLevelRepository extends Mock
    implements PageAccessLevelRepository {}

void main() {
  late MockPageAccessLevelRepository mockRepository;
  late ViewPB testView;

  setUp(() {
    mockRepository = MockPageAccessLevelRepository();
    testView = ViewPB.create()..id = 'test-view-id';

    // Default stubs for initial load
    when(() => mockRepository.getSectionType(any()))
        .thenAnswer((_) async => FlowyResult.success(SharedSectionType.public));
    when(() => mockRepository.getView(any()))
        .thenAnswer((_) async => FlowyResult.success(testView));
  });

  group('PageAccessLevelBloc - refreshAccessLevel optimization', () {
    blocTest<PageAccessLevelBloc, PageAccessLevelState>(
      'should NOT emit new state when access level has NOT changed',
      build: () {
        // First call returns readOnly (initial state)
        when(() => mockRepository.getAccessLevel(any()))
            .thenAnswer((_) async => FlowyResult.success(ShareAccessLevel.readOnly));
        return PageAccessLevelBloc(
          view: testView,
          repository: mockRepository,
        );
      },
      act: (bloc) async {
        // Wait for initial load
        await Future.delayed(const Duration(milliseconds: 100));

        // Reset the mock to track subsequent calls
        reset(mockRepository);
        when(() => mockRepository.getAccessLevel(any()))
            .thenAnswer((_) async => FlowyResult.success(ShareAccessLevel.readOnly));

        // Trigger refresh - should NOT emit because access level is still readOnly
        bloc.add(const PageAccessLevelEvent.refreshAccessLevel());
        await Future.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [],
      verify: (_) {
        // Verify getAccessLevel was called
        verify(() => mockRepository.getAccessLevel('test-view-id')).called(1);
      },
    );

    blocTest<PageAccessLevelBloc, PageAccessLevelState>(
      'should emit new state when access level HAS changed from readOnly to fullAccess',
      build: () {
        // First call returns readOnly (initial state)
        when(() => mockRepository.getAccessLevel(any()))
            .thenAnswer((_) async => FlowyResult.success(ShareAccessLevel.readOnly));
        return PageAccessLevelBloc(
          view: testView,
          repository: mockRepository,
        );
      },
      act: (bloc) async {
        // Wait for initial load
        await Future.delayed(const Duration(milliseconds: 100));

        // Reset the mock to return a DIFFERENT access level
        reset(mockRepository);
        when(() => mockRepository.getAccessLevel(any()))
            .thenAnswer((_) async => FlowyResult.success(ShareAccessLevel.fullAccess));

        // Trigger refresh - SHOULD emit because access level changed
        bloc.add(const PageAccessLevelEvent.refreshAccessLevel());
        await Future.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [
        isA<PageAccessLevelState>()
            .having((s) => s.accessLevel, 'accessLevel', ShareAccessLevel.fullAccess),
      ],
      verify: (_) {
        verify(() => mockRepository.getAccessLevel('test-view-id')).called(1);
      },
    );

    blocTest<PageAccessLevelBloc, PageAccessLevelState>(
      'should NOT emit when refresh is called multiple times with same access level',
      build: () {
        when(() => mockRepository.getAccessLevel(any()))
            .thenAnswer((_) async => FlowyResult.success(ShareAccessLevel.readOnly));
        return PageAccessLevelBloc(
          view: testView,
          repository: mockRepository,
        );
      },
      act: (bloc) async {
        // Wait for initial load
        await Future.delayed(const Duration(milliseconds: 100));

        // Call refresh 3 times with same access level
        bloc.add(const PageAccessLevelEvent.refreshAccessLevel());
        await Future.delayed(const Duration(milliseconds: 50));
        bloc.add(const PageAccessLevelEvent.refreshAccessLevel());
        await Future.delayed(const Duration(milliseconds: 50));
        bloc.add(const PageAccessLevelEvent.refreshAccessLevel());
        await Future.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [], // No state changes expected
      verify: (_) {
        // Verify getAccessLevel was called at least 3 times (for the 3 refresh events)
        verify(() => mockRepository.getAccessLevel('test-view-id')).called(greaterThanOrEqualTo(3));
      },
    );

    blocTest<PageAccessLevelBloc, PageAccessLevelState>(
      'should emit each time access level actually changes',
      build: () {
        when(() => mockRepository.getAccessLevel(any()))
            .thenAnswer((_) async => FlowyResult.success(ShareAccessLevel.readOnly));
        return PageAccessLevelBloc(
          view: testView,
          repository: mockRepository,
        );
      },
      act: (bloc) async {
        // Wait for initial load
        await Future.delayed(const Duration(milliseconds: 100));

        // Change to fullAccess
        reset(mockRepository);
        when(() => mockRepository.getAccessLevel(any()))
            .thenAnswer((_) async => FlowyResult.success(ShareAccessLevel.fullAccess));
        bloc.add(const PageAccessLevelEvent.refreshAccessLevel());
        await Future.delayed(const Duration(milliseconds: 100));

        // Keep same - should NOT emit
        bloc.add(const PageAccessLevelEvent.refreshAccessLevel());
        await Future.delayed(const Duration(milliseconds: 100));

        // Change to readOnly - SHOULD emit
        reset(mockRepository);
        when(() => mockRepository.getAccessLevel(any()))
            .thenAnswer((_) async => FlowyResult.success(ShareAccessLevel.readOnly));
        bloc.add(const PageAccessLevelEvent.refreshAccessLevel());
        await Future.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [
        // First change: readOnly -> fullAccess
        isA<PageAccessLevelState>()
            .having((s) => s.accessLevel, 'accessLevel', ShareAccessLevel.fullAccess),
        // Second change: fullAccess -> readOnly
        isA<PageAccessLevelState>()
            .having((s) => s.accessLevel, 'accessLevel', ShareAccessLevel.readOnly),
      ],
    );
  });
}
