import 'dart:convert';
import 'package:appflowy/features/ai_internal/application/knowledge_model_service.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

const modelAccent = Color(0xFFFF3800);
IconData knowledgeModelIcon(KnowledgeModelType? type) => switch (type) {
      null => Symbols.grid_view,
      KnowledgeModelType.chat => Symbols.chat_bubble,
      KnowledgeModelType.embedding => Symbols.scatter_plot,
      KnowledgeModelType.rerank => Symbols.filter_alt,
      KnowledgeModelType.vision => Symbols.image,
      KnowledgeModelType.speech => Symbols.volume_up,
    };
String modelError(Object error, {bool deleting = false}) => switch (error) {
      KnowledgeBaseException(status: 400 || 409) when deleting =>
        '模型仍被知识库、智能体或记忆使用，请先解除绑定后再删除。',
      KnowledgeBaseException(status: 401) => '请登录云端账号后管理知识库模型。',
      KnowledgeBaseException(status: 403) => '你没有此模型或知识库的管理权限，请刷新后重试。',
      KnowledgeBaseException(status: 409) =>
        '配置冲突：已有文档的知识库不能切换向量模型；已保存的向量定义请另建模型。后台同步期间请稍后重试。',
      KnowledgeBaseException(status: 400) => '模型配置无效，请检查服务端可访问的地址、厂商要求和模型参数。',
      KnowledgeBaseException(status: 404) => '当前服务尚不支持模型管理，请更新 Cloud 服务后重试。',
      _ => '模型服务暂时不可用，请稍后重试。',
    };

Widget modelHeading(BuildContext context, String text) => Text(
      text,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppFlowyTheme.of(context).textColorScheme.primary,
      ),
    );

class KnowledgeProviderIcon extends StatelessWidget {
  const KnowledgeProviderIcon({super.key, this.provider});
  final KnowledgeModelProvider? provider;
  @override
  Widget build(BuildContext context) {
    final value = provider?.icon ?? '';
    if (value.startsWith('data:image/svg+xml;base64,')) {
      return FlowySvg.string(
        utf8.decode(base64Decode(value.split(',').last)),
        size: const Size.square(20),
        blendMode: null,
      );
    }
    return Icon(
      Icons.code,
      size: 20,
      color: AppFlowyTheme.of(context).iconColorScheme.secondary,
    );
  }
}

class KnowledgeModelTypes extends StatelessWidget {
  const KnowledgeModelTypes({
    super.key,
    required this.selected,
    required this.onSelected,
    this.models,
    this.allowAll = true,
    this.enabled = true,
    this.spread = false,
  });
  final KnowledgeModelType? selected;
  final ValueChanged<KnowledgeModelType?> onSelected;
  final List<KnowledgeModel>? models;
  final bool allowAll;
  final bool enabled;
  final bool spread;
  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: spread && constraints.maxWidth >= 850
            ? constraints.maxWidth - 80
            : constraints.maxWidth,
        child: Wrap(
          alignment: spread && constraints.maxWidth >= 850
              ? WrapAlignment.spaceBetween
              : WrapAlignment.start,
          spacing: spread && constraints.maxWidth >= 700 ? 24 : 6,
          runSpacing: 8,
          children: [
            for (final type in <KnowledgeModelType?>[
              if (allowAll) null,
              ...KnowledgeModelType.values,
            ])
              Semantics(
                selected: type == selected,
                child: TextButton.icon(
                  onPressed: enabled ? () => onSelected(type) : null,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    backgroundColor: type == selected
                        ? theme.textColorScheme.primary.withValues(alpha: .035)
                        : Colors.transparent,
                    foregroundColor: spread
                        ? theme.textColorScheme.primary.withValues(alpha: .68)
                        : theme.textColorScheme.secondary,
                    textStyle: DefaultTextStyle.of(context).style,
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: Icon(
                    knowledgeModelIcon(type),
                    size: spread && constraints.maxWidth >= 700 ? 24 : 18,
                    weight: 350,
                    color: type == selected
                        ? modelAccent
                        : spread
                            ? theme.textColorScheme.primary
                                .withValues(alpha: .5)
                            : theme.iconColorScheme.secondary,
                  ),
                  label: Text(
                    '${type?.label ?? '全部'}${models == null ? '' : ' (${models!.where((m) => type == null || m.type == type).length})'}',
                    style: TextStyle(
                      fontSize:
                          spread ? (constraints.maxWidth >= 700 ? 18 : 14) : 13,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration modelSurface(BuildContext context, {double radius = 14}) {
  final theme = AppFlowyTheme.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: theme.backgroundColorScheme.primary,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: theme.textColorScheme.primary.withValues(alpha: dark ? .09 : .045),
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? .14 : .035),
        blurRadius: 18,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? .08 : .018),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ],
  );
}

EdgeInsets modelPagePadding(BuildContext context) => EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width < 480 ? 16 : 36,
      28,
      MediaQuery.sizeOf(context).width < 480 ? 16 : 36,
      32,
    );

InputDecoration modelInputDecoration(
  BuildContext context, {
  String? hint,
  Widget? suffix,
}) =>
    InputDecoration(
      hintText: hint,
      suffixIcon: suffix,
      filled: true,
      fillColor: AppFlowyTheme.of(context).backgroundColorScheme.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppFlowyTheme.of(context)
              .textColorScheme
              .primary
              .withValues(alpha: .055),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppFlowyTheme.of(context)
              .textColorScheme
              .primary
              .withValues(alpha: .055),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: modelAccent),
      ),
    );

Widget modelField(
  BuildContext context,
  String label,
  Widget input, {
  String? hint,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppFlowyTheme.of(context).textColorScheme.primary,
                ),
              ),
              if (hint != null)
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppFlowyTheme.of(context)
                        .textColorScheme
                        .primary
                        .withValues(alpha: .52),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: modelSurface(context, radius: 10),
            child: input,
          ),
        ],
      ),
    );
