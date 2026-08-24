import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ImportType {
  historyDocument,
  historyDatabase,
  markdownOrText,
  csv,
  pdf,
  html,
  afDatabase;

  @override
  String toString() {
    switch (this) {
      case ImportType.historyDocument:
        return LocaleKeys.importPanel_documentFromV010.tr();
      case ImportType.historyDatabase:
        return LocaleKeys.importPanel_databaseFromV010.tr();
      case ImportType.markdownOrText:
        return LocaleKeys.importPanel_textAndMarkdown.tr();
      case ImportType.csv:
        return LocaleKeys.importPanel_csv.tr();
      case ImportType.pdf:
        return 'PDF';
      case ImportType.html:
        return 'HTML';
      case ImportType.afDatabase:
        return LocaleKeys.importPanel_database.tr();
    }
  }

  WidgetBuilder get icon => (context) {
        final FlowySvgData svg;
        switch (this) {
          case ImportType.historyDatabase:
            svg = FlowySvgs.document_s;
          case ImportType.historyDocument:
          case ImportType.afDatabase:
            svg = FlowySvgs.board_s;
          case ImportType.csv:
            svg = FlowySvgs.database_layout_s;
          case ImportType.pdf:
            svg = FlowySvgs.document_s;
          case ImportType.markdownOrText:
            svg = FlowySvgs.export_markdown_s;
          case ImportType.html:
            svg = FlowySvgs.export_html_s;
        }

        return FlowySvg(
          svg,
          color: Theme.of(context).colorScheme.tertiary,
        );
      };

  /// The import card icons used by the desktop import page.
  ///
  /// Mobile import options use the same Material icons so both surfaces stay
  /// visually consistent.
  IconData get cardIcon {
    switch (this) {
      case ImportType.csv:
        return Icons.table_chart;
      case ImportType.pdf:
        return Icons.picture_as_pdf;
      case ImportType.markdownOrText:
        return Icons.text_snippet;
      case ImportType.html:
        return Icons.code;
      case ImportType.historyDocument:
      case ImportType.historyDatabase:
      case ImportType.afDatabase:
        return Icons.description;
    }
  }

  bool get enableOnRelease {
    switch (this) {
      case ImportType.historyDatabase:
      case ImportType.historyDocument:
      case ImportType.afDatabase:
        return kDebugMode;
      case ImportType.pdf:
      case ImportType.html:
      default:
        return true;
    }
  }

  List<String> get allowedExtensions {
    switch (this) {
      case ImportType.historyDocument:
        return ['afdoc'];
      case ImportType.historyDatabase:
      case ImportType.afDatabase:
        return ['afdb'];
      case ImportType.markdownOrText:
        return ['md', 'txt'];
      case ImportType.csv:
        return ['csv'];
      case ImportType.pdf:
        return ['pdf'];
      case ImportType.html:
        return ['html', 'htm'];
    }
  }

  bool get allowMultiSelect {
    switch (this) {
      case ImportType.historyDocument:
      case ImportType.historyDatabase:
      case ImportType.csv:
      case ImportType.afDatabase:
      case ImportType.markdownOrText:
      case ImportType.pdf:
      case ImportType.html:
        return true;
    }
  }
}
