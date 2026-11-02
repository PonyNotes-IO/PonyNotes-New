import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  group('DocumentAppearanceCubit', () {
    late SharedPreferences preferences;
    late DocumentAppearanceCubit cubit;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
    });

    setUp(() async {
      preferences = await SharedPreferences.getInstance();
      cubit = DocumentAppearanceCubit();
    });

    tearDown(() async {
      await preferences.clear();
      await cubit.close();
    });

    test('Initial state', () {
      expect(cubit.state.fontSize, 16.0);
      expect(cubit.state.fontFamily, defaultFontFamily);
    });

    test('Fetch document appearance from SharedPreferences', () async {
      await preferences.setDouble(KVKeys.kDocumentAppearanceFontSize, 18.0);
      await preferences.setString(
        KVKeys.kDocumentAppearanceFontFamily,
        'Arial',
      );

      await cubit.fetch();

      expect(cubit.state.fontSize, 18.0);
      expect(cubit.state.fontFamily, 'Arial');
    });

    test('Sync font size to SharedPreferences', () async {
      await cubit.syncFontSize(20.0);

      final fontSize =
          preferences.getDouble(KVKeys.kDocumentAppearanceFontSize);
      expect(fontSize, 20.0);
      expect(cubit.state.fontSize, 20.0);
    });

    for (final scale in [0.9, 1.0, 1.3]) {
      test('Document font size survives reload at display scale $scale',
          () async {
        await preferences.setString(KVKeys.textScaleFactor, scale.toString());

        await cubit.fetch();
        expect(cubit.state.fontSize, 16.0);

        await cubit.syncFontSize(20.0);
        await cubit.fetch();
        expect(cubit.state.fontSize, 20.0);

        final restartedCubit = DocumentAppearanceCubit();
        addTearDown(restartedCubit.close);
        await restartedCubit.fetch();

        expect(restartedCubit.state.fontSize, 20.0);
        expect(preferences.getDouble(KVKeys.kDocumentAppearanceFontSize), 20.0);
        expect(preferences.getString(KVKeys.textScaleFactor), scale.toString());
      });
    }

    test('Sync font family to SharedPreferences', () async {
      await cubit.syncFontFamily('Helvetica');

      final fontFamily =
          preferences.getString(KVKeys.kDocumentAppearanceFontFamily);
      expect(fontFamily, 'Helvetica');
      expect(cubit.state.fontFamily, 'Helvetica');
    });
  });
}
