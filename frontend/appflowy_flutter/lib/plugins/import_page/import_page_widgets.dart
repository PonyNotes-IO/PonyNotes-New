import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

String _text(BuildContext context, String zh, String en) =>
    context.locale.languageCode == 'zh' ? zh : en;

class ImportPageContent extends StatefulWidget {
  const ImportPageContent({
    super.key,
    required this.onFileImport,
    required this.onNotionImport,
    required this.onObsidianImport,
    required this.syncContent,
  });

  final ValueChanged<String> onFileImport;
  final VoidCallback onNotionImport;
  final VoidCallback onObsidianImport;
  final Widget syncContent;

  @override
  State<ImportPageContent> createState() => _ImportPageContentState();
}

class _ImportPageContentState extends State<ImportPageContent> {
  bool _showSync = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: Material(
        color: colors.surface,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth < 600 ? 24 : 35,
              _showSync ? 29 : 35,
              constraints.maxWidth < 600 ? 24 : (_showSync ? 58 : 65),
              32,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(context, '导入同步', 'Import & sync'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _text(
                        context,
                        '从其他应用和文件导入数据到小马笔记',
                        'Bring your notes and files into PonyNotes',
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: colors.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        _tab(_text(context, '导入', 'Import'), false),
                        const SizedBox(width: 14),
                        _tab(_text(context, '同步', 'Sync'), true),
                      ],
                    ),
                    const SizedBox(height: 28),
                    if (_showSync)
                      widget.syncContent
                    else ...[
                      _heading(_text(context, '基于文件导入', 'Import from a file')),
                      const SizedBox(height: 14),
                      _fileCards(context),
                      const SizedBox(height: 42),
                      _heading(
                        _text(context, '从笔记软件导入', 'Import from a notes app'),
                      ),
                      const SizedBox(height: 14),
                      _serviceCards(context),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, bool sync) {
    final colors = Theme.of(context).colorScheme;
    final selected = _showSync == sync;
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: () => setState(() => _showSync = sync),
        style: TextButton.styleFrom(
          foregroundColor:
              colors.onSurface.withValues(alpha: selected ? 1 : 0.65),
          backgroundColor: selected
              ? colors.onSurface.withValues(alpha: 0.045)
              : Colors.transparent,
          minimumSize: const Size(42, 26),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w400,
              ),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _heading(String title) => Text(
        title,
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );

  Widget _fileCards(BuildContext context) {
    final types = [
      ('csv', 'CSV', Icons.table_chart_outlined),
      ('pdf', 'PDF', FontAwesomeIcons.filePdf),
      (
        'markdown',
        _text(context, '文本与Markdown', 'Text & Markdown'),
        FontAwesomeIcons.fileLines
      ),
      ('html', 'HTML', FontAwesomeIcons.fileCode),
    ];
    Widget card(int index) => ImportFileCard(
          key: ValueKey('import-file-${types[index].$1}'),
          icon: types[index].$3,
          title: types[index].$2,
          onTap: () => widget.onFileImport(types[index].$1),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 680) {
          return Row(
            children: [
              for (var i = 0; i < types.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(flex: i == 2 ? 135 : 100, child: card(i)),
              ],
            ],
          );
        }
        final columns = constraints.maxWidth >= 380 ? 2 : 1;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < types.length; i++)
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 8) / columns,
                child: card(i),
              ),
          ],
        );
      },
    );
  }

  Widget _serviceCards(BuildContext context) {
    final cards = [
      ImportServiceCard(
        title: 'Notion',
        subtitle: _text(
          context,
          '导入完整 ZIP，保留父子页面层级',
          'Import a full ZIP with nested pages',
        ),
        onTap: widget.onNotionImport,
      ),
      ImportServiceCard(
        title: 'Obsidian',
        subtitle: _text(
          context,
          '导入整个仓库，保留文件夹层级',
          'Import a vault with its folder hierarchy',
        ),
        onTap: widget.onObsidianImport,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 680
          ? Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 8),
                Expanded(child: cards[1]),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [cards[0], const SizedBox(height: 8), cards[1]],
            ),
    );
  }
}

class ImportFileCard extends StatelessWidget {
  const ImportFileCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ImportCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class ImportServiceCard extends StatelessWidget {
  const ImportServiceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.actionLabel,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ImportCard(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth >= 340 ? 64 : 24,
            16,
            16,
            16,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.5,
                        color: colors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: colors.onSurface.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    actionLabel ?? _text(context, '导入', 'Import'),
                    style: const TextStyle(fontSize: 11, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(11);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.onSurface.withValues(alpha: 0.055)),
        ),
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            hoverColor: colors.onSurface.withValues(alpha: 0.025),
            focusColor: colors.primary.withValues(alpha: 0.1),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 70),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
