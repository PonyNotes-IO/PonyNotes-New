import 'package:appflowy/mobile/presentation/search/mobile_search_ai_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android mobile search AI entrance', () {
    test('stays visible above recent items when the query is empty', () {
      expect(
        shouldShowMobileSearchAiEntrance(
          isAndroid: true,
          aiEnabled: true,
          query: '',
          hasResults: false,
          searching: false,
        ),
        isTrue,
      );
    });

    test('stays visible above best matches when search has results', () {
      expect(
        shouldShowMobileSearchAiEntrance(
          isAndroid: true,
          aiEnabled: true,
          query: '  release notes  ',
          hasResults: true,
          searching: false,
        ),
        isTrue,
      );
    });

    test('keeps the existing non-Android visibility behavior', () {
      expect(
        shouldShowMobileSearchAiEntrance(
          isAndroid: false,
          aiEnabled: true,
          query: '',
          hasResults: false,
          searching: false,
        ),
        isFalse,
      );
      expect(
        shouldShowMobileSearchAiEntrance(
          isAndroid: false,
          aiEnabled: true,
          query: 'release notes',
          hasResults: false,
          searching: false,
        ),
        isTrue,
      );
    });

    test('remains hidden when AI is unavailable', () {
      expect(
        shouldShowMobileSearchAiEntrance(
          isAndroid: true,
          aiEnabled: false,
          query: '',
          hasResults: false,
          searching: false,
        ),
        isFalse,
      );
    });

    test('keeps the ask action while Android search summaries update', () {
      expect(
        shouldUseMobileSearchAskAction(isAndroid: true),
        isTrue,
      );
      expect(
        shouldUseMobileSearchAskAction(isAndroid: false),
        isFalse,
      );
    });
  });

  group('Android search to AI chat handoff', () {
    test('trims and marks a non-empty Android query for automatic sending', () {
      expect(
        buildMobileSearchChatExtra(
          isAndroid: true,
          query: '  release notes  ',
        ),
        {
          'initial_message': 'release notes',
          'auto_send': true,
        },
      );
    });

    test('does not request automatic sending for an empty Android query', () {
      expect(
        buildMobileSearchChatExtra(isAndroid: true, query: '   '),
        {'initial_message': ''},
      );
    });

    test('preserves the existing non-Android handoff', () {
      expect(
        buildMobileSearchChatExtra(
          isAndroid: false,
          query: '  release notes  ',
        ),
        {'initial_message': '  release notes  '},
      );
    });

    test('automatically sends once only on Android', () {
      expect(
        shouldAutoSendMobileSearchMessage(
          isAndroid: true,
          requested: true,
          alreadyHandled: false,
          message: 'release notes',
        ),
        isTrue,
      );
      expect(
        shouldAutoSendMobileSearchMessage(
          isAndroid: true,
          requested: true,
          alreadyHandled: true,
          message: 'release notes',
        ),
        isFalse,
      );
      expect(
        shouldAutoSendMobileSearchMessage(
          isAndroid: false,
          requested: true,
          alreadyHandled: false,
          message: 'release notes',
        ),
        isFalse,
      );
    });
  });
}
