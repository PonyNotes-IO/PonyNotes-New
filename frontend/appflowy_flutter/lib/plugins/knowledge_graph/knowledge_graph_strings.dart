import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

String graphText(BuildContext context, String key) =>
    'knowledgeGraph.$key'.tr(context: context);
