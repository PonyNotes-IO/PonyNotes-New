import 'dart:convert';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/ai_chat/chat.dart';
import 'package:appflowy/plugins/database/board/presentation/board_page.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_page.dart';
import 'package:appflowy/plugins/database/grid/presentation/grid_page.dart';
import 'package:appflowy/plugins/database/grid/presentation/mobile_grid_page.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/document.dart';
import 'package:appflowy/plugins/space_hub/space_hub.dart';
import 'package:appflowy/plugins/whiteboard/whiteboard.dart';
import 'package:appflowy/plugins/handwriting_saber/handwriting_saber.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class PluginArgumentKeys {
  static String selection = "selection";
  static String rowId = "row_id";
  static String blockId = "block_id";
}

class ViewExtKeys {
  // used for customizing the font family.
  static String fontKey = 'font';

  // used for customizing the font layout.
  static String fontLayoutKey = 'font_layout';

  // used for customizing the line height layout.
  static String lineHeightLayoutKey = 'line_height_layout';

  // cover keys
  static String coverKey = 'cover';
  static String coverTypeKey = 'type';
  static String coverValueKey = 'value';

  // is pinned
  static String isPinnedKey = 'is_pinned';

  // space
  static String isSpaceKey = 'is_space';
  static String spaceCreatorKey = 'space_creator';
  static String spaceCreatedAtKey = 'space_created_at';
  static String spaceIconKey = 'space_icon';
  static String spaceIconColorKey = 'space_icon_color';
  static String spacePermissionKey = 'space_permission';
}

extension MinimalViewExtension on FolderViewMinimalPB {
  Widget defaultIcon({Size? size}) {
    // 为 Folder 和 Notebook 返回 emoji 图标
    if (layout == ViewLayoutPB.Folder) {
      return const Text(
        '📂',
        style: TextStyle(fontSize: 16.0),
      );
    } else if (layout == ViewLayoutPB.Notebook) {
      return const Text(
        '📓',
        style: TextStyle(fontSize: 16.0),
      );
    }
    
    // 其他类型返回 SVG 图标
    return FlowySvg(
      switch (layout) {
        ViewLayoutPB.Board => FlowySvgs.icon_board_s,
        ViewLayoutPB.Calendar => FlowySvgs.icon_calendar_m,
        ViewLayoutPB.Grid => FlowySvgs.icon_grid_s,
        ViewLayoutPB.Document => FlowySvgs.icon_document_s,
        ViewLayoutPB.Chat => FlowySvgs.chat_ai_page_s,
        _ => FlowySvgs.icon_document_s,
      },
      size: size,
    );
  }
}

extension ViewExtension on ViewPB {
  String get nameOrDefault =>
      name.isEmpty ? LocaleKeys.menuAppHeader_defaultNewPageName.tr() : name;

  bool get isDocument => pluginType == PluginType.document;
  bool get isDatabase => [
        PluginType.grid,
        PluginType.board,
        PluginType.calendar,
      ].contains(pluginType);

  Widget defaultIcon({Size? size}) {
    // 为 Folder 和 Notebook 返回 emoji 图标
    if (layout == ViewLayoutPB.Folder) {
      return const Text(
        '📂',
        style: TextStyle(fontSize: 16.0),
      );
    } else if (layout == ViewLayoutPB.Notebook) {
      return const Text(
        '📓',
        style: TextStyle(fontSize: 16.0),
      );
    }
    
    // 其他类型返回 SVG 图标
    return FlowySvg(
      switch (layout) {
        ViewLayoutPB.Board => FlowySvgs.icon_board_s,
        ViewLayoutPB.Calendar => FlowySvgs.icon_calendar_m,
        ViewLayoutPB.Grid => FlowySvgs.icon_grid_s,
        ViewLayoutPB.Document => FlowySvgs.icon_document_s,
        ViewLayoutPB.Chat => FlowySvgs.chat_ai_page_s,
        _ => FlowySvgs.icon_document_s,
      },
      size: size,
    );
  }

  PluginType get pluginType {
    return switch (layout) {
      ViewLayoutPB.Board => PluginType.board,
      ViewLayoutPB.Calendar => PluginType.calendar,
      ViewLayoutPB.Document => PluginType.document,
      ViewLayoutPB.Grid => PluginType.grid,
      ViewLayoutPB.Chat => PluginType.chat,
      ViewLayoutPB.Whiteboard => PluginType.whiteboard,
      ViewLayoutPB.Folder => PluginType.folder,
      ViewLayoutPB.Notebook => PluginType.notebook,
      _ => PluginType.document,
    };
  }

  Plugin plugin({
    Map<String, dynamic> arguments = const {},
  }) {
    // 如果是空间类型，返回 SpaceHubPlugin（空间统一页面）
    if (isSpace) {
      return SpaceHubPlugin(view: this);
    }

    switch (layout) {
      case ViewLayoutPB.Board:
      case ViewLayoutPB.Calendar:
      case ViewLayoutPB.Grid:
        final String? rowId = arguments[PluginArgumentKeys.rowId];

        return DatabaseTabBarViewPlugin(
          view: this,
          pluginType: pluginType,
          initialRowId: rowId,
        );
      case ViewLayoutPB.Document:
        // 检查是否是 handwriting_saber 类型
        // 优先从 extra 字段解析
        String? viewType;

        if (extra.isNotEmpty) {
          try {
            final ext = jsonDecode(extra);
            if (ext is Map<String, dynamic>) {
              viewType = ext['view_type'] as String?;
            }
          } catch (e) {
            // 解析失败，忽略 extra
          }
        }

        if (viewType == 'handwriting_saber') {
          return HandwritingSaberPlugin(
            view: this,
            pluginType: PluginType.handwritingSaber,
          );
        }
        // 普通的 Document 视图，返回 DocumentPlugin
        final selectionValue = arguments[PluginArgumentKeys.selection];
        Selection? initialSelection;
        if (selectionValue is Selection) initialSelection = selectionValue;

        final String? initialBlockId = arguments[PluginArgumentKeys.blockId];

        return DocumentPlugin(
          view: this,
          pluginType: pluginType,
          initialSelection: initialSelection,
          initialBlockId: initialBlockId,
        );
      case ViewLayoutPB.Folder:
      case ViewLayoutPB.Notebook:
        final selectionValue = arguments[PluginArgumentKeys.selection];
        Selection? initialSelection;
        if (selectionValue is Selection) initialSelection = selectionValue;

        final String? initialBlockId = arguments[PluginArgumentKeys.blockId];

        return DocumentPlugin(
          view: this,
          pluginType: pluginType,
          initialSelection: initialSelection,
          initialBlockId: initialBlockId,
        );
      case ViewLayoutPB.Chat:
        return AIChatPagePlugin(view: this);
      case ViewLayoutPB.Whiteboard:
        return WhiteboardPlugin(
          view: this,
          pluginType: pluginType,
        );
    }
    throw UnimplementedError;
  }

  DatabaseTabBarItemBuilder tabBarItem() => switch (layout) {
        ViewLayoutPB.Board => BoardPageTabBarBuilderImpl(),
        ViewLayoutPB.Calendar => CalendarPageTabBarBuilderImpl(),
        ViewLayoutPB.Grid => DesktopGridTabBarBuilderImpl(),
        _ => throw UnimplementedError,
      };

  DatabaseTabBarItemBuilder mobileTabBarItem() => switch (layout) {
        ViewLayoutPB.Board => BoardPageTabBarBuilderImpl(),
        ViewLayoutPB.Calendar => CalendarPageTabBarBuilderImpl(),
        ViewLayoutPB.Grid => MobileGridTabBarBuilderImpl(),
        _ => throw UnimplementedError,
      };

  FlowySvgData get iconData => layout.icon;

  bool get isSpace {
    try {
      if (extra.isEmpty) {
        return false;
      }

      final ext = jsonDecode(extra);
      final isSpace = ext[ViewExtKeys.isSpaceKey] ?? false;
      return isSpace;
    } catch (e) {
      return false;
    }
  }

  SpacePermission get spacePermission {
    try {
      final ext = jsonDecode(extra);
      final permission = ext[ViewExtKeys.spacePermissionKey] ?? 1;
      return SpacePermission.values[permission];
    } catch (e) {
      return SpacePermission.private;
    }
  }

  FlowySvg? buildSpaceIconSvg(BuildContext context, {Size? size}) {
    try {
      if (extra.isEmpty) {
        return null;
      }

      final ext = jsonDecode(extra);
      final icon = ext[ViewExtKeys.spaceIconKey];
      final color = ext[ViewExtKeys.spaceIconColorKey];
      if (icon == null || color == null) {
        return null;
      }
      // before version 0.6.7
      if (icon.contains('space_icon')) {
        return FlowySvg(
          FlowySvgData('assets/flowy_icons/16x/$icon.svg'),
          color: Theme.of(context).colorScheme.surface,
        );
      }

      final values = icon.split('/');
      if (values.length != 2) {
        return null;
      }
      final groupName = values[0];
      final iconName = values[1];
      final svgString = kIconGroups
          ?.firstWhereOrNull(
            (group) => group.name == groupName,
          )
          ?.icons
          .firstWhereOrNull(
            (icon) => icon.name == iconName,
          )
          ?.content;
      if (svgString == null) {
        return null;
      }
      return FlowySvg.string(
        svgString,
        color: Theme.of(context).colorScheme.surface,
        size: size,
      );
    } catch (e) {
      return null;
    }
  }

  String? get spaceIcon {
    try {
      final ext = jsonDecode(extra);
      final icon = ext[ViewExtKeys.spaceIconKey];
      return icon;
    } catch (e) {
      return null;
    }
  }

  String? get spaceIconColor {
    try {
      final ext = jsonDecode(extra);
      final color = ext[ViewExtKeys.spaceIconColorKey];
      return color;
    } catch (e) {
      return null;
    }
  }

  bool get isPinned {
    try {
      final ext = jsonDecode(extra);
      final isPinned = ext[ViewExtKeys.isPinnedKey] ?? false;
      return isPinned;
    } catch (e) {
      return false;
    }
  }

  PageStyleCover? get cover {
    if (layout != ViewLayoutPB.Document) {
      return null;
    }

    if (extra.isEmpty) {
      return null;
    }

    try {
      final ext = jsonDecode(extra);
      final cover = ext[ViewExtKeys.coverKey] ?? {};
      final coverType = cover[ViewExtKeys.coverTypeKey] ??
          PageStyleCoverImageType.none.toString();
      final coverValue = cover[ViewExtKeys.coverValueKey] ?? '';
      return PageStyleCover(
        type: PageStyleCoverImageType.fromString(coverType),
        value: coverValue,
      );
    } catch (e) {
      return null;
    }
  }

  PageStyleLineHeightLayout get lineHeightLayout {
    if (layout != ViewLayoutPB.Document) {
      return PageStyleLineHeightLayout.normal;
    }
    try {
      final ext = jsonDecode(extra);
      final lineHeight = ext[ViewExtKeys.lineHeightLayoutKey];
      return PageStyleLineHeightLayout.fromString(lineHeight);
    } catch (e) {
      return PageStyleLineHeightLayout.normal;
    }
  }

  PageStyleFontLayout get fontLayout {
    if (layout != ViewLayoutPB.Document) {
      return PageStyleFontLayout.normal;
    }
    try {
      final ext = jsonDecode(extra);
      final fontLayout = ext[ViewExtKeys.fontLayoutKey];
      return PageStyleFontLayout.fromString(fontLayout);
    } catch (e) {
      return PageStyleFontLayout.normal;
    }
  }

  @visibleForTesting
  set isSpace(bool value) {
    try {
      if (extra.isEmpty) {
        extra = jsonEncode({ViewExtKeys.isSpaceKey: value});
      } else {
        final ext = jsonDecode(extra);
        ext[ViewExtKeys.isSpaceKey] = value;
        extra = jsonEncode(ext);
      }
    } catch (e) {
      extra = jsonEncode({ViewExtKeys.isSpaceKey: value});
    }
  }
}

extension ViewLayoutExtension on ViewLayoutPB {
  FlowySvgData get icon => switch (this) {
        ViewLayoutPB.Board => FlowySvgs.icon_board_s,
        ViewLayoutPB.Calendar => FlowySvgs.icon_calendar_m,
        ViewLayoutPB.Grid => FlowySvgs.icon_grid_s,
        ViewLayoutPB.Document => FlowySvgs.icon_document_s,
        ViewLayoutPB.Chat => FlowySvgs.chat_ai_page_s,
        ViewLayoutPB.Whiteboard => FlowySvgs.icon_board_s, // 使用看板图标，后续可更换为专用白板图标
        ViewLayoutPB.Folder => FlowySvgs.folder_m,
        ViewLayoutPB.Notebook => FlowySvgs.folder_m, // 使用文件夹图标，后面可以改为专门的笔记本图标
        _ => FlowySvgs.icon_document_s,
      };

  bool get isDocumentView => switch (this) {
        ViewLayoutPB.Document => true,
        ViewLayoutPB.Chat ||
        ViewLayoutPB.Grid ||
        ViewLayoutPB.Board ||
        ViewLayoutPB.Calendar ||
        ViewLayoutPB.Whiteboard =>
          false,
        _ => false, // 临时处理：未知layout type返回false而不是抛异常
      };

  bool get isDatabaseView => switch (this) {
        ViewLayoutPB.Grid ||
        ViewLayoutPB.Board ||
        ViewLayoutPB.Calendar =>
          true,
        ViewLayoutPB.Document || 
        ViewLayoutPB.Chat ||
        ViewLayoutPB.Whiteboard => false,
        _ => false, // 临时处理：未知layout type返回false而不是抛异常
      };

  /// Returns the localized default name for each view layout type
  String get defaultName => switch (this) {
        ViewLayoutPB.Document => LocaleKeys.menuAppHeader_defaultNewDocumentName.tr(),
        ViewLayoutPB.Grid => LocaleKeys.menuAppHeader_defaultNewGridName.tr(),
        ViewLayoutPB.Board => LocaleKeys.menuAppHeader_defaultNewBoardName.tr(),
        ViewLayoutPB.Calendar => LocaleKeys.menuAppHeader_defaultNewCalendarName.tr(),
        ViewLayoutPB.Chat => LocaleKeys.menuAppHeader_defaultNewChatName.tr(),
        ViewLayoutPB.Whiteboard => LocaleKeys.menuAppHeader_defaultNewWhiteboardName.tr(),
        ViewLayoutPB.Folder => LocaleKeys.menuAppHeader_defaultNewFolderName.tr(),
        ViewLayoutPB.Notebook => LocaleKeys.menuAppHeader_defaultNewNotebookName.tr(),
        _ => LocaleKeys.menuAppHeader_defaultNewPageName.tr(),
      };

  bool get shrinkWrappable => switch (this) {
        ViewLayoutPB.Grid => true,
        ViewLayoutPB.Board => true,
        _ => false,
      };

  double get pluginHeight => switch (this) {
        ViewLayoutPB.Document || ViewLayoutPB.Board || ViewLayoutPB.Chat => 450, // || ViewLayoutPB.Whiteboard 暂时注释
        ViewLayoutPB.Calendar => 650,
        ViewLayoutPB.Grid => double.infinity,
        _ => 450, // 临时处理：未知layout type返回默认高度
      };

  bool get isWhiteboardView => switch (this) {
        ViewLayoutPB.Whiteboard => true,
        ViewLayoutPB.Document ||
        ViewLayoutPB.Chat ||
        ViewLayoutPB.Grid ||
        ViewLayoutPB.Board ||
        ViewLayoutPB.Calendar => false,
        _ => false,
      };
}

extension ViewFinder on List<ViewPB> {
  ViewPB? findView(String id) {
    for (final view in this) {
      if (view.id == id) {
        return view;
      }

      if (view.childViews.isNotEmpty) {
        final v = view.childViews.findView(id);
        if (v != null) {
          return v;
        }
      }
    }

    return null;
  }
}
