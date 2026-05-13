import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_row.dart';
import 'package:appflowy/mobile/presentation/widgets/widgets.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_window_size_manager.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/font_size_stepper.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/util/theme_mode_extension.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scaled_app/scaled_app.dart';

import '../setting.dart';

const int _divisions = 4;
const double _minMobileScaleFactor = 0.8;
const double _maxMobileScaleFactor = 1.2;

class AppearanceSettingGroup extends StatelessWidget {
  const AppearanceSettingGroup({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MobileSettingGroup(
      groupTitle: LocaleKeys.settings_menu_appearance.tr(),
      settingItemList: const [
        ThemeSetting(),
        FontSetting(),
        DisplaySizeSetting(),
        RTLSetting(),
      ],
      wrapInCard: true,
      showDivider: false,
    );
  }
}

class ThemeSetting extends StatelessWidget {
  const ThemeSetting({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<AppearanceSettingsCubit>().state.themeMode;
    return MobileSettingRow(
      name: LocaleKeys.settings_appearance_themeMode_label.tr(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            themeMode.labelText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
          ),
          const SizedBox(width: 8),
          FlowySvg(
            FlowySvgs.toolbar_arrow_right_m,
            size: const Size.square(24),
            color: AppFlowyTheme.of(context).iconColorScheme.tertiary,
          ),
        ],
      ),
      onTap: () => _showThemePicker(context),
    );
  }

  void _showThemePicker(BuildContext context) {
    showMobileBottomSheet(
      context,
      showHeader: true,
      showDragHandle: true,
      showDivider: false,
      title: LocaleKeys.settings_appearance_themeMode_label.tr(),
      builder: (ctx) {
        final themeMode = ctx.read<AppearanceSettingsCubit>().state.themeMode;
        return Column(
          children: [
            FlowyOptionTile.checkbox(
              text: LocaleKeys.settings_appearance_themeMode_system.tr(),
              leftIcon: const FlowySvg(FlowySvgs.m_theme_mode_system_s),
              isSelected: themeMode == ThemeMode.system,
              onTap: () {
                ctx.read<AppearanceSettingsCubit>().setThemeMode(ThemeMode.system);
                Navigator.pop(ctx);
              },
            ),
            FlowyOptionTile.checkbox(
              showTopBorder: false,
              text: LocaleKeys.settings_appearance_themeMode_light.tr(),
              leftIcon: const FlowySvg(FlowySvgs.m_theme_mode_light_s),
              isSelected: themeMode == ThemeMode.light,
              onTap: () {
                ctx.read<AppearanceSettingsCubit>().setThemeMode(ThemeMode.light);
                Navigator.pop(ctx);
              },
            ),
            FlowyOptionTile.checkbox(
              showTopBorder: false,
              text: LocaleKeys.settings_appearance_themeMode_dark.tr(),
              leftIcon: const FlowySvg(FlowySvgs.m_theme_mode_dark_s),
              isSelected: themeMode == ThemeMode.dark,
              onTap: () {
                ctx.read<AppearanceSettingsCubit>().setThemeMode(ThemeMode.dark);
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }
}

class DisplaySizeSetting extends StatefulWidget {
  const DisplaySizeSetting({super.key});

  @override
  State<DisplaySizeSetting> createState() => _DisplaySizeSettingState();
}

class _DisplaySizeSettingState extends State<DisplaySizeSetting> {
  double scaleFactor = 1.0;
  final windowSizeManager = WindowSizeManager();

  @override
  void initState() {
    super.initState();
    windowSizeManager.getScaleFactor().then((v) {
      if (v != scaleFactor && mounted) {
        setState(() => scaleFactor = v);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MobileSettingRow(
      name: LocaleKeys.settings_appearance_displaySize.tr(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            scaleFactor.toStringAsFixed(1),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
          ),
          const SizedBox(width: 8),
          FlowySvg(
            FlowySvgs.toolbar_arrow_right_m,
            size: const Size.square(24),
            color: AppFlowyTheme.of(context).iconColorScheme.tertiary,
          ),
        ],
      ),
      onTap: () {
        showMobileBottomSheet(
          context,
          showHeader: true,
          showDragHandle: true,
          showDivider: false,
          title: LocaleKeys.settings_appearance_displaySize.tr(),
          builder: (ctx) {
            return FontSizeStepper(
              value: scaleFactor,
              minimumValue: _minMobileScaleFactor,
              maximumValue: _maxMobileScaleFactor,
              divisions: _divisions,
              onChanged: (newScaleFactor) async {
                await _setScale(newScaleFactor);
              },
            );
          },
        );
      },
    );
  }

  Future<void> _setScale(double value) async {
    if (FlowyRunner.currentMode == IntegrationMode.integrationTest) {
      // #0      ScaledWidgetsFlutterBinding.Eval ()
      // #1      ScaledWidgetsFlutterBinding.instance (package:scaled_app/scaled_app.dart:66:62)
      // ignore: invalid_use_of_visible_for_testing_member
      appflowyScaleFactor = value;
    } else {
      ScaledWidgetsFlutterBinding.instance.scaleFactor = (_) => value;
    }
    if (mounted) {
      setState(() => scaleFactor = value);
    }
    await windowSizeManager.setScaleFactor(value);
  }
}

class RTLSetting extends StatelessWidget {
  const RTLSetting({super.key});

  @override
  Widget build(BuildContext context) {
    final textDirection =
        context.watch<AppearanceSettingsCubit>().state.textDirection;
    return MobileSettingRow(
      name: LocaleKeys.settings_appearance_textDirection_label.tr(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _textDirectionLabelText(textDirection),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
          ),
          const SizedBox(width: 8),
          FlowySvg(
            FlowySvgs.toolbar_arrow_right_m,
            size: const Size.square(24),
            color: AppFlowyTheme.of(context).iconColorScheme.tertiary,
          ),
        ],
      ),
      onTap: () => _showTextDirectionPicker(context),
    );
  }

  String _textDirectionLabelText(AppFlowyTextDirection textDirection) {
    switch (textDirection) {
      case AppFlowyTextDirection.auto:
        return LocaleKeys.settings_appearance_textDirection_auto.tr();
      case AppFlowyTextDirection.rtl:
        return LocaleKeys.settings_appearance_textDirection_rtl.tr();
      case AppFlowyTextDirection.ltr:
        return LocaleKeys.settings_appearance_textDirection_ltr.tr();
    }
  }

  void _showTextDirectionPicker(BuildContext context) {
    showMobileBottomSheet(
      context,
      showHeader: true,
      showDragHandle: true,
      showDivider: false,
      title: LocaleKeys.settings_appearance_textDirection_label.tr(),
      builder: (ctx) {
        final textDirection =
            ctx.read<AppearanceSettingsCubit>().state.textDirection;
        return Column(
          children: [
            FlowyOptionTile.checkbox(
              text: LocaleKeys.settings_appearance_textDirection_ltr.tr(),
              isSelected: textDirection == AppFlowyTextDirection.ltr,
              onTap: () => _applyAndPop(ctx, AppFlowyTextDirection.ltr),
            ),
            FlowyOptionTile.checkbox(
              showTopBorder: false,
              text: LocaleKeys.settings_appearance_textDirection_rtl.tr(),
              isSelected: textDirection == AppFlowyTextDirection.rtl,
              onTap: () => _applyAndPop(ctx, AppFlowyTextDirection.rtl),
            ),
            FlowyOptionTile.checkbox(
              showTopBorder: false,
              text: LocaleKeys.settings_appearance_textDirection_auto.tr(),
              isSelected: textDirection == AppFlowyTextDirection.auto,
              onTap: () => _applyAndPop(ctx, AppFlowyTextDirection.auto),
            ),
          ],
        );
      },
    );
  }

  void _applyAndPop(BuildContext ctx, AppFlowyTextDirection direction) {
    ctx.read<AppearanceSettingsCubit>().setTextDirection(direction);
    ctx.read<DocumentAppearanceCubit>().syncDefaultTextDirection(direction.name);
    Navigator.pop(ctx);
  }
}
