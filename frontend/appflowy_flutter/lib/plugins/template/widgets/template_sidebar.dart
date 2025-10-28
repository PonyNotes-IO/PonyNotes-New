import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

class TemplateSidebar extends StatefulWidget {
  final String selectedCategory;
  final String selectedView;
  final String searchQuery;
  final Function(String) onCategoryChanged;
  final Function(String) onViewChanged;
  final Function(String) onSearchChanged;

  const TemplateSidebar({
    super.key,
    required this.selectedCategory,
    required this.selectedView,
    required this.searchQuery,
    required this.onCategoryChanged,
    required this.onViewChanged,
    required this.onSearchChanged,
  });

  @override
  State<TemplateSidebar> createState() => _TemplateSidebarState();
}

class _TemplateSidebarState extends State<TemplateSidebar> {
  // 按用例分类
  final List<CategoryItem> useCaseCategories = [
    const CategoryItem(id: 'project-management', name: '项目管理', icon: Icons.assignment),
    const CategoryItem(id: 'engineering', name: '工程', icon: Icons.engineering),
    const CategoryItem(id: 'startups', name: '初创企业', icon: Icons.lightbulb),
    const CategoryItem(id: 'education', name: '教育', icon: Icons.school),
    const CategoryItem(id: 'marketing', name: '营销', icon: Icons.campaign),
    const CategoryItem(id: 'management', name: '管理', icon: Icons.manage_accounts),
    const CategoryItem(id: 'human-resources', name: '人力资源', icon: Icons.person),
    const CategoryItem(id: 'sales-crm', name: '销售和客户关系管理', icon: Icons.attach_money),
    const CategoryItem(id: 'team-meeting', name: '团队会议', icon: Icons.groups),
    const CategoryItem(id: 'product-design', name: '产品与设计', icon: Icons.design_services),
  ];

  // 按功能分类
  final List<CategoryItem> functionCategories = [
    const CategoryItem(id: 'ai-powered', name: '人工智能驱动', icon: Icons.auto_awesome),
    const CategoryItem(id: 'docs', name: '文档', icon: Icons.description),
    const CategoryItem(id: 'wiki', name: '维基百科', icon: Icons.article),
    const CategoryItem(id: 'database', name: '数据库', icon: Icons.storage),
    const CategoryItem(id: 'kanban', name: '看板', icon: Icons.view_column),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据可用宽度动态调整侧边栏宽度
        final availableWidth = constraints.maxWidth;
        final sidebarWidth = availableWidth > 0 ? availableWidth : 280;
        
        return Container(
          width: sidebarWidth.toDouble(),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              right: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // 分类导航
              Expanded(
                child: _buildSidebarNavigation(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarNavigation(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // 所有模版 - 突出显示
          _buildAllTemplatesItem(context),
          const SizedBox(height: 16),
          // 按用例分类
          _buildSidebarSection(context, '按用例', useCaseCategories.map((category) => 
            _buildSidebarItem(context, category.name, category.icon, category.id)
          ).toList()),
          const SizedBox(height: 16),
          // 按功能分类
          _buildSidebarSection(context, '按功能', functionCategories.map((category) => 
            _buildSidebarItem(context, category.name, category.icon, category.id)
          ).toList()),
          const SizedBox(height: 16),
          // 我的模版和团队模版
          _buildUserTemplatesSection(context),
        ],
      ),
    );
  }

  Widget _buildAllTemplatesItem(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = widget.selectedCategory == 'all' && widget.selectedView == 'all';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            widget.onCategoryChanged('all');
            widget.onViewChanged('all');
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected 
                  ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected 
                    ? theme.colorScheme.primary.withOpacity(0.5)
                    : theme.colorScheme.outline.withOpacity(0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.apps,
                    size: 20,
                    color: isSelected 
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FlowyText.medium(
                    '所有模版',
                    color: isSelected 
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserTemplatesSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FlowyText.small(
            '我的空间',
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        _buildSidebarItem(context, '我的模版', Icons.person, 'my'),
        _buildSidebarItem(context, '团队模版', Icons.group, 'team'),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSidebarSection(BuildContext context, String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FlowyText.small(
            title.toUpperCase(),
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        ...children,
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSidebarItem(BuildContext context, String title, IconData icon, String categoryId) {
    final theme = Theme.of(context);
    final isSelected = widget.selectedCategory == categoryId && widget.selectedView == categoryId;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            widget.onCategoryChanged(categoryId);
            widget.onViewChanged(categoryId);
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected 
                  ? theme.colorScheme.primaryContainer.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected 
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FlowyText.medium(
                    title,
                    color: isSelected 
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    fontSize: 14,
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CategoryItem {
  final String id;
  final String name;
  final IconData icon;

  const CategoryItem({
    required this.id,
    required this.name,
    required this.icon,
  });
}
