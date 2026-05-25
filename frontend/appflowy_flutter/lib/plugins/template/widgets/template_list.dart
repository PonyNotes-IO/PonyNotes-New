import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';
import '../services/template_service.dart';

class TemplateList extends StatefulWidget {
  final String selectedView;
  final String selectedCategory;
  final String searchQuery;
  final List<TemplateItem> allTemplates;
  final List<TemplateItem> myTemplates;
  final List<TemplateItem> teamTemplates;
  final bool isLoading;
  final String? error;
  final Function(String) onViewChanged;
  final Function(TemplateItem) onTemplateUsed;

  const TemplateList({
    super.key,
    required this.selectedView,
    required this.selectedCategory,
    required this.searchQuery,
    required this.allTemplates,
    required this.myTemplates,
    required this.teamTemplates,
    required this.isLoading,
    required this.error,
    required this.onViewChanged,
    required this.onTemplateUsed,
  });

  @override
  State<TemplateList> createState() => _TemplateListState();
}

class _TemplateListState extends State<TemplateList> {
  List<TemplateItem> get filteredTemplates {
    List<TemplateItem> templates;
    
    switch (widget.selectedView) {
      case 'my':
        templates = widget.myTemplates;
        break;
      case 'team':
        templates = widget.teamTemplates;
        break;
      default:
        templates = widget.allTemplates;
        break;
    }

    // 按分类过滤
    if (widget.selectedCategory != 'all' && 
        widget.selectedCategory != 'my' && 
        widget.selectedCategory != 'team') {
      templates = templates.where((template) => 
        template.category == widget.selectedCategory,).toList();
    }

    // 按搜索关键词过滤
    if (widget.searchQuery.isNotEmpty) {
      templates = templates.where((template) =>
        template.title.toLowerCase().contains(widget.searchQuery.toLowerCase()) ||
        template.description.toLowerCase().contains(widget.searchQuery.toLowerCase()) ||
        template.author.toLowerCase().contains(widget.searchQuery.toLowerCase()) ||
        template.tags.any((tag) => tag.toLowerCase().contains(widget.searchQuery.toLowerCase())),
      ).toList();
    }

    return templates;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredTemplates = this.filteredTemplates;
    
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // 头部工具栏
          // _buildContentHeader(context, filteredTemplates),
          // 模版内容
          Expanded(
            child: widget.isLoading
                ? _buildLoadingState(context)
                : widget.error != null
                    ? _buildErrorState(context)
                    : filteredTemplates.isEmpty
                        ? _buildEmptyState(context)
                        : _buildTemplateGrid(context, filteredTemplates),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          FlowyText.medium(
            '加载模版中...',
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          FlowyText.medium(
            '加载失败',
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 8),
          FlowyText.small(
            widget.error ?? '未知错误',
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              // 可以添加重试逻辑
            },
            child: FlowyText.small('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_outlined,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          FlowyText.medium(
            '暂无模版',
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          FlowyText.small(
            '尝试选择其他分类或搜索关键词',
            color: theme.colorScheme.onSurface.withOpacity(0.4),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateGrid(BuildContext context, List<TemplateItem> templates) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 检查约束是否有效
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        
        // 根据可用宽度动态计算网格列数
        final availableWidth = constraints.maxWidth;
        int crossAxisCount;
        double crossAxisSpacing;
        double mainAxisSpacing;
        double childAspectRatio;
        
        // 计算合适的列数，确保卡片不会太小
        if (availableWidth > 1400) {
          // 超大屏幕：5列
          crossAxisCount = 5;
          crossAxisSpacing = 20;
          mainAxisSpacing = 20;
          childAspectRatio = 0.8;
        } else if (availableWidth > 1200) {
          // 大屏幕：4列
          crossAxisCount = 4;
          crossAxisSpacing = 20;
          mainAxisSpacing = 20;
          childAspectRatio = 0.75;
        } else if (availableWidth > 900) {
          // 中等屏幕：3列
          crossAxisCount = 3;
          crossAxisSpacing = 16;
          mainAxisSpacing = 16;
          childAspectRatio = 0.8;
        } else if (availableWidth > 600) {
          // 小屏幕：2列
          crossAxisCount = 2;
          crossAxisSpacing = 12;
          mainAxisSpacing = 12;
          childAspectRatio = 0.85;
        } else {
          // 很小屏幕：1列
          crossAxisCount = 1;
          crossAxisSpacing = 8;
          mainAxisSpacing = 8;
          childAspectRatio = 1.2;
        }
        
        // 确保卡片有合理的高度
        final cardWidth = (availableWidth - (crossAxisSpacing * (crossAxisCount - 1)) - 48) / crossAxisCount;
        final minCardHeight = 180.0; // 降低最小高度要求
        final maxCardHeight = 300.0; // 设置最大高度
        final calculatedHeight = cardWidth / childAspectRatio;
        
        // 调整 aspectRatio 确保高度在合理范围内
        if (calculatedHeight < minCardHeight) {
          childAspectRatio = cardWidth / minCardHeight;
        } else if (calculatedHeight > maxCardHeight) {
          childAspectRatio = cardWidth / maxCardHeight;
        }
        
        // 确保 childAspectRatio 不为 0 或负数
        if (childAspectRatio <= 0) {
          childAspectRatio = 0.8; // 默认值
        }
        
        return Padding(
          padding: const EdgeInsets.all(24),
          child: GridView.builder(
            shrinkWrap: false,
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: crossAxisSpacing,
              mainAxisSpacing: mainAxisSpacing,
              childAspectRatio: childAspectRatio,
            ),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              return _buildTemplateCard(context, templates[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildTemplateCard(BuildContext context, TemplateItem template) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTemplateUsed(template),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 模版预览图
                Expanded(
                  flex: 3,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: template.previewUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: template.previewUrl.startsWith('http')
                                ? Image.network(
                                    template.previewUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return _buildPlaceholderImage(context);
                                    },
                                  )
                                : Image.asset(
                                    template.previewUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return _buildPlaceholderImage(context);
                                    },
                                  ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                  theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.description_outlined,
                              size: 40,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                // 模版信息
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: FlowyText.medium(
                              template.title,
                              fontSize: 16,
                              color: theme.colorScheme.onSurface,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (template.featured)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    theme.colorScheme.primary,
                                    theme.colorScheme.primary.withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: FlowyText.small(
                                '推荐',
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: FlowyText.small(
                              template.author,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: FlowyText.small(
                                '使用模版',
                                color: theme.colorScheme.primary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Icon(
          Icons.description_outlined,
          size: 48,
          color: theme.colorScheme.primary.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
