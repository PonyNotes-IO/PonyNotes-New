import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_row.dart';
import 'package:appflowy/mobile/presentation/widgets/widgets.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/date_time/date_format_ext.dart';
import 'package:appflowy/workspace/application/settings/date_time/time_format_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-user/date_time.pbenum.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../setting.dart';

class DateTimeSettingGroup extends StatelessWidget {
  const DateTimeSettingGroup({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppearanceSettingsCubit, AppearanceSettingsState>(
      builder: (context, state) {
        return MobileSettingGroup(
          groupTitle: LocaleKeys.settings_workspacePage_dateTime_title.tr(),
          settingItemList: [
            MobileSettingRow(
              name: LocaleKeys.settings_workspacePage_dateTime_dateFormat_label
                  .tr(),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dateFormatLabel(state.dateFormat),
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
              onTap: () => _showDateFormatPicker(context, state.dateFormat),
            ),
            MobileSettingRow(
              name: LocaleKeys.settings_workspacePage_dateTime_24HourTime.tr(),
              trailing: Switch.adaptive(
                activeColor: Theme.of(context).colorScheme.primary,
                value: state.timeFormat == UserTimeFormatPB.TwentyFourHour,
                onChanged: (value) {
                  context.read<AppearanceSettingsCubit>().setTimeFormat(
                        value
                            ? UserTimeFormatPB.TwentyFourHour
                            : UserTimeFormatPB.TwelveHour,
                      );
                },
              ),
            ),
          ],
          wrapInCard: true,
          showDivider: false,
        );
      },
    );
  }

  String _dateFormatLabel(UserDateFormatPB format) => switch (format) {
        UserDateFormatPB.Locally =>
          LocaleKeys.settings_workspacePage_dateTime_dateFormat_local.tr(),
        UserDateFormatPB.US =>
          LocaleKeys.settings_workspacePage_dateTime_dateFormat_us.tr(),
        UserDateFormatPB.ISO =>
          LocaleKeys.settings_workspacePage_dateTime_dateFormat_iso.tr(),
        UserDateFormatPB.Friendly =>
          LocaleKeys.settings_workspacePage_dateTime_dateFormat_friendly.tr(),
        UserDateFormatPB.DayMonthYear =>
          LocaleKeys.settings_workspacePage_dateTime_dateFormat_dmy.tr(),
        _ => "Unknown",
      };

  void _showDateFormatPicker(
      BuildContext context, UserDateFormatPB currentFormat) {
    showMobileBottomSheet(
      context,
      showHeader: true,
      showDragHandle: true,
      showDivider: false,
      title:
          LocaleKeys.settings_workspacePage_dateTime_dateFormat_label.tr(),
      builder: (_) {
        return Column(
          children: [
            UserDateFormatPB.Locally,
            UserDateFormatPB.US,
            UserDateFormatPB.ISO,
            UserDateFormatPB.Friendly,
            UserDateFormatPB.DayMonthYear,
          ]
              .asMap()
              .entries
              .map(
                (entry) {
                  final format = entry.value;
                  final label = _dateFormatLabel(format);
                  return FlowyOptionTile.checkbox(
                    text: label,
                    showTopBorder: entry.key == 0,
                    isSelected: currentFormat == format,
                    onTap: () {
                      context
                          .read<AppearanceSettingsCubit>()
                          .setDateFormat(format);
                      context.pop();
                    },
                  );
                },
              )
              .toList(),
        );
      },
    );
  }
}

