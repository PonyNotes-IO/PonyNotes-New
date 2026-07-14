import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/plugins/whiteboard/presentation/mobile_whiteboard_body.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

class MobileWhiteboardScreen extends StatelessWidget {
  const MobileWhiteboardScreen({
    super.key,
    required this.id,
    this.title,
  });

  final String id;
  final String? title;

  static const routeName = '/whiteboard';
  static const viewId = 'id';
  static const viewTitle = 'title';

  @override
  Widget build(BuildContext context) {
    final view = ViewPB(id: id, name: title ?? '');

    return Scaffold(
      appBar: MobileAppBar(
        title: title ?? '白板',
      ),
      body: MobileWhiteboardBody(view: view),
    );
  }
}