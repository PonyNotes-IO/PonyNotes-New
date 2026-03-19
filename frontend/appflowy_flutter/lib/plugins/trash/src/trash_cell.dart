import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy/workspace/application/settings/date_time/date_format_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-user/date_time.pbenum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/icon_button.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/trash.pb.dart';
import 'package:flutter/material.dart';

import 'sizes.dart';

class TrashCell extends StatelessWidget {
  const TrashCell({
    super.key,
    required this.object,
    required this.onRestore,
    required this.onDelete,
    required this.dateFormat,
    required this.timeFormat,
  });

  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final TrashPB object;
  final UserDateFormatPB dateFormat;
  final UserTimeFormatPB timeFormat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: TrashSizes.fileNameWidth,
          child: FlowyText(
            object.name.isEmpty
                ? LocaleKeys.menuAppHeader_defaultNewPageName.tr()
                : object.name,
          ),
        ),
        SizedBox(
          width: TrashSizes.lashModifyWidth,
          child: FlowyText(formatTimestamp(object.modifiedTime.toDateTime())),
        ),
        SizedBox(
          width: TrashSizes.createTimeWidth,
          child: FlowyText(formatTimestamp(object.createTime.toDateTime())),
        ),
        const Spacer(),
        FlowyIconButton(
          iconColorOnHover: Theme.of(context).colorScheme.onSurface,
          width: TrashSizes.actionIconWidth,
          onPressed: onRestore,
          iconPadding: const EdgeInsets.all(5),
          icon: const FlowySvg(FlowySvgs.restore_s),
        ),
        const HSpace(20),
        FlowyIconButton(
          iconColorOnHover: Theme.of(context).colorScheme.onSurface,
          width: TrashSizes.actionIconWidth,
          onPressed: onDelete,
          iconPadding: const EdgeInsets.all(5),
          icon: const FlowySvg(FlowySvgs.delete_s),
        ),
      ],
    );
  }

  String formatTimestamp(DateTime dateTime) {
    return dateFormat.formatDate(dateTime, true, timeFormat);
  }
}
