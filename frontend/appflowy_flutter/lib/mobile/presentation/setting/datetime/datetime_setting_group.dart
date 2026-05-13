import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_group_widget.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_item_widget.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_trailing.dart';
import 'package:appflowy/mobile/presentation/widgets/flowy_option_tile.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/date_time/date_format_ext.dart';
import 'package:appflowy/workspace/application/settings/date_time/time_format_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-user/date_time.pbenum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class DateTimeSettingGroup extends StatelessWidget {
  const DateTimeSettingGroup({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppearanceSettingsCubit, AppearanceSettingsState>(
      builder: (context, state) {
        return MobileSettingGroup(
          groupTitle: LocaleKeys.settings_workspacePage_dateTime_title.tr(),
          settingItemList: [
            MobileSettingItem(
              name: LocaleKeys.settings_workspacePage_dateTime_dateFormat_label
                  .tr(),
              trailing: MobileSettingTrailing(
                text: _dateFormatLabel(state.dateFormat),
              ),
              onTap: () => _showDateFormatPicker(context, state.dateFormat),
            ),
            MobileSettingItem(
              name:
                  LocaleKeys.settings_workspacePage_dateTime_24HourTime.tr(),
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
