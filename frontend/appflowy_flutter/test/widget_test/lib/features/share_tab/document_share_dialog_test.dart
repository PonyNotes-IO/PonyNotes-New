import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/plugins/shared/share/publish_tab.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/plugins/shared/share/share_menu.dart';
import 'package:appflowy/plugins/shared/share/share_settings_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MembersBloc extends MockBloc<ShareTabEvent, ShareTabState>
    implements ShareTabBloc {}

class _ChineseStrings extends AssetLoader {
  const _ChineseStrings();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/zh-CN.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _PublishBloc extends MockBloc<ShareEvent, ShareState>
    implements ShareBloc {}

const _capturePath = String.fromEnvironment('SHARE_CAPTURE_PATH');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    registerFallbackValue(ShareTabEvent.clearState());
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    if (_capturePath.isEmpty) return;
    final font = FontLoader('ShareCapture')
      ..addFont(Future.value(ByteData.sublistView(
        File('$_capturePath/capture-font.ttf').readAsBytesSync(),
      )));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final dark in [false, true]) {
    testWidgets(
        'document share layout and actions (${dark ? 'dark' : 'light'})',
        (tester) async {
      if (_capturePath.isNotEmpty) {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
      }
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final members = _MembersBloc();
      when(() => members.isClosed).thenReturn(false);
      final publish = _PublishBloc();
      addTearDown(members.close);
      addTearDown(publish.close);
      when(() => publish.state).thenReturn(ShareState.initial());
      when(() => publish.view)
          .thenReturn(ViewPB(layout: ViewLayoutPB.Document));
      final owner = SharedUser(
        name: '小马用户',
        email: 'owner@example.test',
        role: ShareRole.owner,
        accessLevel: ShareAccessLevel.fullAccess,
        userId: '1',
      );
      final invitee = SharedUser(
        name: '小马用户959882',
        email: '',
        phone: '15601188899',
        role: ShareRole.member,
        accessLevel: ShareAccessLevel.readAndWrite,
        userId: 'candidate',
      );
      final initial = ShareTabState(
        currentUser: UserProfilePB(name: owner.name, email: owner.email),
        shareLink: 'https://example.test/share',
        selectedPermissionId: 3,
      );
      final states = StreamController<ShareTabState>();
      addTearDown(states.close);
      whenListen(members, states.stream, initialState: initial);
      final captureKey = GlobalKey();
      final theme = dark
          ? AppFlowyDefaultTheme().dark(fontFamily: 'ShareCapture')
          : AppFlowyDefaultTheme().light(fontFamily: 'ShareCapture');
      final material = ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        useMaterial3: false,
        fontFamily: 'ShareCapture',
      );
      const locale = Locale('zh', 'CN');
      await tester.pumpWidget(RepaintBoundary(
        key: captureKey,
        child: EasyLocalization(
          supportedLocales: const [locale],
          path: 'assets/translations',
          assetLoader: const _ChineseStrings(),
          startLocale: locale,
          saveLocale: false,
          child: Builder(
              builder: (context) => AppFlowyTheme(
                    data: theme,
                    child: ToastificationWrapper(
                        child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      localizationsDelegates: context.localizationDelegates,
                      supportedLocales: context.supportedLocales,
                      locale: context.locale,
                      theme: material.copyWith(
                          colorScheme: material.colorScheme.copyWith(
                        primary: const Color(0xFFFF3800),
                        onPrimary: Colors.white,
                      )),
                      home: Scaffold(
                        backgroundColor: theme.backgroundColorScheme.primary,
                        body: Builder(
                            builder: (context) => TextButton(
                                  onPressed: () => showDialog<void>(
                                    context: context,
                                    barrierColor: Colors.transparent,
                                    builder: (_) => MultiBlocProvider(
                                      providers: [
                                        BlocProvider<ShareTabBloc>.value(
                                            value: members),
                                        BlocProvider<ShareBloc>.value(
                                            value: publish),
                                      ],
                                      child: const ShareSettingsDialog(
                                        tabs: [
                                          ShareMenuTab.share,
                                          ShareMenuTab.publish
                                        ],
                                        viewName: '11-10 问题',
                                        anchor: Offset(1288, 47),
                                      ),
                                    ),
                                  ),
                                  child: const Text('Open dialog'),
                                )),
                      ),
                    )),
                  )),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      final dialog = find.byKey(const ValueKey('document-share-dialog'));
      final invite = find.widgetWithText(FilledButton, '邀请');
      final copy = find.text('复制链接');
      final search = find.byType(TextField);
      expect(tester.getSize(dialog), const Size(498, 217));
      expect(
          tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
          dark
              ? const Color(0xFF262626)
              : theme.surfaceContainerColorScheme.layer01);
      expect(tester.widget<FilledButton>(invite).onPressed, isNull);

      Future<void> capture(String state) async {
        if (_capturePath.isEmpty) return;
        await tester.runAsync(() async {
          final boundary = captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$_capturePath/$state-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('empty');
      await tester.tap(copy);
      verify(() => members.add(any(that: isA<ShareTabEventCopyShareLink>())))
          .called(1);
      await tester.enterText(search, '15601188899');
      verify(() =>
          members.add(any(that: isA<ShareTabEventSearchAvailableUsers>())));
      states.add(initial.copyWith(availableUsers: [
        invitee,
        for (var i = 1; i < 4; i++)
          invitee.copyWith(userId: 'candidate-$i', name: '小马用户${959882 + i}'),
      ]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(invitee.name));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(invite).onPressed, isNotNull);
      await capture('selected');
      final trigger = find.widgetWithText(TextButton, '编辑');
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(trigger));
      addTearDown(mouse.removePointer);
      await tester.pumpAndSettle();
      final hovered = tester.widget<TextButton>(trigger).style!;
      expect(hovered.backgroundColor!.resolve({WidgetState.hovered}),
          dark ? const Color(0xFF2E2E2) : const Color(0xFFF7F7F7));
      expect(hovered.overlayColor!.resolve({WidgetState.hovered}),
          Colors.transparent);
      await capture('permission-hover');

      final menu = find.byKey(const ValueKey('document-share-permission-menu'));
      await tester.tap(trigger);
      await tester.pump();
      final initialMenuSize = tester.getSize(menu);
      await tester.pump(const Duration(milliseconds: 45));
      final fade = find.descendant(of: menu, matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(fade).opacity, inExclusiveRange(0.0, 1.0));
      expect(tester.getSize(menu), initialMenuSize);
      await tester.pumpAndSettle();
      expect(find.text('无法更改'), findsOneWidget);
      final currentLevel = find.descendant(
          of: menu, matching: find.widgetWithText(MenuItemButton, '编辑'));
      expect(
          tester
              .widget<MenuItemButton>(currentLevel)
              .style!
              .backgroundColor!
              .resolve({}),
          dark ? const Color(0xFF343434) : const Color(0xFFF2F2F2));
      await capture('permissions');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      expect(dialog, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();
      await tester.tap(invite);
      verify(() => members.add(any(
          that: isA<ShareTabEventAddCollaborator>()
              .having((event) => event.user.userId, 'invitee', 'candidate')
              .having((event) => event.accessLevel, 'permission',
                  ShareAccessLevel.readOnly)))).called(1);

      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(find.byType(PublishTab), findsOneWidget);
      await tester.tap(find.text('共享'));
      final collaborator = invitee.copyWith(email: 'member@example.test');
      states.add(initial.copyWith(users: [owner, collaborator]));
      await tester.pumpAndSettle();
      final memberTrigger = find.widgetWithText(TextButton, '编辑');
      await mouse.moveTo(tester.getCenter(memberTrigger));
      await tester.pumpAndSettle();
      await capture('member-permission-hover');
      await tester.tap(memberTrigger);
      await tester.pumpAndSettle();
      expect(find.text('移除访问权限'), findsOneWidget);
      await capture('member-permissions');
      await tester.tap(find.text('移除访问权限'));
      await tester.pumpAndSettle();
      verify(() =>
              members.add(any(that: isA<ShareTabEventRemoveCollabMember>())))
          .called(1);
      states.add(initial.copyWith(users: [
        owner,
        collaborator,
        for (var i = 1; i < 18; i++)
          collaborator.copyWith(userId: 'member-$i', name: '协作者 $i'),
      ]));
      await tester.pumpAndSettle();
      expect(tester.getSize(dialog), const Size(498, 560));
      final inputPosition = tester.getTopLeft(search);
      final footerPosition = tester.getTopLeft(copy);
      final list = find.byKey(const ValueKey('share-members'));
      await tester.drag(list, const Offset(0, -350));
      await tester.pumpAndSettle();
      final scrollable =
          find.descendant(of: list, matching: find.byType(Scrollable));
      expect(tester.state<ScrollableState>(scrollable).position.pixels,
          greaterThan(0));
      expect(tester.getTopLeft(search), inputPosition);
      expect(tester.getTopLeft(copy), footerPosition);
      tester.view.physicalSize = const Size(320, 520);
      await tester.pumpAndSettle();
      expect(tester.getSize(dialog).width, 288);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      await tester.pumpWidget(const SizedBox());
      if (_capturePath.isNotEmpty) debugDisableShadows = true;
    });
  }
}
