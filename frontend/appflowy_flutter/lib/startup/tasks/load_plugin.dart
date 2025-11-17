import 'package:appflowy/plugins/ai_chat/chat.dart';
import 'package:appflowy/plugins/database/calendar/calendar.dart';
import 'package:appflowy/plugins/database/board/board.dart';
import 'package:appflowy/plugins/database/grid/grid.dart';
import 'package:appflowy/plugins/database_document/database_document_plugin.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/document/document.dart';
import 'package:appflowy/plugins/trash/trash.dart';
import 'package:appflowy/plugins/import_page/import_page_plugin.dart';
import 'package:appflowy/plugins/homepage/homepage.dart';
import 'package:appflowy/plugins/file_library/file_library_plugin.dart';
import 'package:appflowy/plugins/inbox/inbox_plugin.dart';
import 'package:appflowy/plugins/whiteboard/whiteboard.dart';
import 'package:appflowy/plugins/template/template_plugin.dart';
import 'package:appflowy/plugins/folder/folder.dart';
import 'package:appflowy/plugins/notebook/notebook.dart';
class PluginLoadTask extends LaunchTask {
  const PluginLoadTask();

  @override
  LaunchTaskType get type => LaunchTaskType.dataProcessing;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    registerPlugin(builder: BlankPluginBuilder(), config: BlankPluginConfig());
    registerPlugin(builder: TrashPluginBuilder(), config: TrashPluginConfig());
    registerPlugin(builder: DocumentPluginBuilder());
    registerPlugin(builder: GridPluginBuilder(), config: GridPluginConfig());
    registerPlugin(builder: BoardPluginBuilder(), config: BoardPluginConfig());
    registerPlugin(
      builder: CalendarPluginBuilder(),
      config: CalendarPluginConfig(),
    );
    registerPlugin(
      builder: DatabaseDocumentPluginBuilder(),
      config: DatabaseDocumentPluginConfig(),
    );
    registerPlugin(
      builder: DatabaseDocumentPluginBuilder(),
      config: DatabaseDocumentPluginConfig(),
    );
    registerPlugin(
      builder: AIChatPluginBuilder(),
      config: AIChatPluginConfig(),
    );
    registerPlugin(
      builder: ImportPagePluginBuilder(),
    );
    registerPlugin(
      builder: HomePagePluginBuilder(),
      config: HomePagePluginConfig(),
    );
    registerPlugin(
      builder: FileLibraryPluginBuilder(),
      config: FileLibraryPluginConfig(),
    );
    registerPlugin(
      builder: InboxPluginBuilder(),
      config: InboxPluginConfig(),
    );
    registerPlugin(
      builder: WhiteboardPluginBuilder(),
    );
    registerPlugin(
      builder: TemplatePluginBuilder(),
      config: TemplatePluginConfig(),
    );
    registerPlugin(
      builder: FolderPluginBuilder(),
    );
    registerPlugin(
      builder: NotebookPluginBuilder(),
    );
  }
}
