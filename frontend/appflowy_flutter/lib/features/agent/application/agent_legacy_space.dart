import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';

bool isLegacyAiSpace(ViewPB view) =>
    view.isSpace && const {'我的AI会话', '我的AI对话'}.contains(view.name);
