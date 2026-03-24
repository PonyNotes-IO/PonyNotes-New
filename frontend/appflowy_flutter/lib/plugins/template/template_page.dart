import 'package:appflowy/plugins/template/services/template_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'widgets/template_sidebar.dart';
import 'widgets/template_list.dart';
import 'services/appflowy_template_integration.dart';

class TemplatePage extends StatefulWidget {
  const TemplatePage({super.key});

  @override
  State<TemplatePage> createState() => _TemplatePageState();
}

class _TemplatePageState extends State<TemplatePage>
    with TickerProviderStateMixin {
  // 动画控制器
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // 模版数据
  List<TemplateItem> allTemplates = [];
  List<TemplateItem> myTemplates = [];
  List<TemplateItem> teamTemplates = [];
  bool isLoading = true;
  String? error;
  String selectedCategory = 'all';
  String searchQuery = '';
  String selectedView = 'all'; // 'all', 'my', 'team'
  String dataSourceInfo = '加载中...';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ),);
    _animationController.forward();
    _loadTemplates();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      // 并行加载所有模版数据
      final results = await Future.wait([
        TemplateService.getAllTemplates(),
        TemplateService.getMyTemplates(),
        TemplateService.getTeamTemplates(),
        TemplateService.getDataSourceInfo(),
      ]);

      setState(() {
        allTemplates = results[0] as List<TemplateItem>;
        myTemplates = results[1] as List<TemplateItem>;
        teamTemplates = results[2] as List<TemplateItem>;
        dataSourceInfo = results[3] as String;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _useTemplate(BuildContext context, TemplateItem template) async {
    // 显示确认对话框
    final confirmed = await _showTemplateConfirmDialog(context, template);
    if (!confirmed) {
      return;
    }

    try {
      // 获取当前用户和工作空间信息
      final userProfileResult =
          await UserBackendService.getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => null,
      );

      if (userProfile == null) {
        if (context.mounted) {
          showToastNotification(
            message: '无法获取当前用户信息',
            type: ToastificationType.error,
          );
        }
        return;
      }

      // 获取工作空间ID
      final workspaceResult = await UserBackendService.getCurrentWorkspace();
      final workspaceId = workspaceResult.fold(
        (workspace) => workspace.id,
        (error) => '',
      );

      if (workspaceId.isEmpty) {
        if (context.mounted) {
          showToastNotification(
            message: '无法获取工作空间信息',
            type: ToastificationType.error,
          );
        }
        return;
      }

      // 显示加载提示
      if (context.mounted) {
        showToastNotification(
          message: '正在创建模版文档: ${template.title}...',
        );
      }

      // 使用AppFlowy模版集成服务创建文档
      if (context.mounted) {
        final success = await AppFlowyTemplateIntegration.useTemplate(
          context: context,
          template: template,
          workspaceId: workspaceId,
          userId: userProfile.id.toInt(),
        );

        if (success) {
          // 刷新模版列表，包括我的模版列表
          await _loadTemplates();
          
          // 显示添加到我的模版的提示
          if (context.mounted) {
            showToastNotification(
              message: '模版已添加到"我的模版"列表',
              type: ToastificationType.success,
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        showToastNotification(
          message: '使用模版时发生错误: $e',
          type: ToastificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 确保有有效的上下文
    if (!mounted) {
      return const SizedBox.shrink();
    }
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 检查约束是否有效
              if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
              
              // 根据屏幕宽度决定布局方式
              final screenWidth = constraints.maxWidth;
              final screenHeight = constraints.maxHeight;
              final isWideScreen = screenWidth > 1200;
              final isMediumScreen = screenWidth > 800;
              final isVeryWideScreen = screenWidth > 1600; // 超宽屏幕
              
              Widget layoutWidget;
              
              if (isVeryWideScreen) {
                // 超宽屏幕：使用更大的侧边栏和更多列
                layoutWidget = Row(
                  children: [
                    SizedBox(
                      width: 320, // 更大的侧边栏
                      child: TemplateSidebar(
                        selectedCategory: selectedCategory,
                        selectedView: selectedView,
                        searchQuery: searchQuery,
                        onCategoryChanged: (category) {
                          if (mounted) {
                            setState(() {
                              selectedCategory = category;
                            });
                          }
                        },
                        onViewChanged: (view) {
                          if (mounted) {
                            setState(() {
                              selectedView = view;
                            });
                          }
                        },
                        onSearchChanged: (query) {
                          if (mounted) {
                            setState(() {
                              searchQuery = query;
                            });
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: TemplateList(
                        selectedView: selectedView,
                        selectedCategory: selectedCategory,
                        searchQuery: searchQuery,
                        allTemplates: allTemplates,
                        myTemplates: myTemplates,
                        teamTemplates: teamTemplates,
                        isLoading: isLoading,
                        error: error,
                        onViewChanged: (view) {
                          if (mounted) {
                            setState(() {
                              selectedView = view;
                            });
                          }
                        },
                        onTemplateUsed: (template) => _useTemplate(context, template),
                      ),
                    ),
                  ],
                );
              } else if (isWideScreen) {
                // 宽屏：使用水平布局
                layoutWidget = Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: TemplateSidebar(
                        selectedCategory: selectedCategory,
                        selectedView: selectedView,
                        searchQuery: searchQuery,
                        onCategoryChanged: (category) {
                          if (mounted) {
                            setState(() {
                              selectedCategory = category;
                            });
                          }
                        },
                        onViewChanged: (view) {
                          if (mounted) {
                            setState(() {
                              selectedView = view;
                            });
                          }
                        },
                        onSearchChanged: (query) {
                          if (mounted) {
                            setState(() {
                              searchQuery = query;
                            });
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: TemplateList(
                        selectedView: selectedView,
                        selectedCategory: selectedCategory,
                        searchQuery: searchQuery,
                        allTemplates: allTemplates,
                        myTemplates: myTemplates,
                        teamTemplates: teamTemplates,
                        isLoading: isLoading,
                        error: error,
                        onViewChanged: (view) {
                          if (mounted) {
                            setState(() {
                              selectedView = view;
                            });
                          }
                        },
                        onTemplateUsed: (template) => _useTemplate(context, template),
                      ),
                    ),
                  ],
                );
              } else if (isMediumScreen) {
                // 中等屏幕：使用可折叠的侧边栏
                layoutWidget = Row(
                  children: [
                    SizedBox(
                      width: 250, // 稍微缩小侧边栏宽度
                      child: TemplateSidebar(
                        selectedCategory: selectedCategory,
                        selectedView: selectedView,
                        searchQuery: searchQuery,
                        onCategoryChanged: (category) {
                          if (mounted) {
                            setState(() {
                              selectedCategory = category;
                            });
                          }
                        },
                        onViewChanged: (view) {
                          if (mounted) {
                            setState(() {
                              selectedView = view;
                            });
                          }
                        },
                        onSearchChanged: (query) {
                          if (mounted) {
                            setState(() {
                              searchQuery = query;
                            });
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: TemplateList(
                        selectedView: selectedView,
                        selectedCategory: selectedCategory,
                        searchQuery: searchQuery,
                        allTemplates: allTemplates,
                        myTemplates: myTemplates,
                        teamTemplates: teamTemplates,
                        isLoading: isLoading,
                        error: error,
                        onViewChanged: (view) {
                          if (mounted) {
                            setState(() {
                              selectedView = view;
                            });
                          }
                        },
                        onTemplateUsed: (template) => _useTemplate(context, template),
                      ),
                    ),
                  ],
                );
              } else {
                // 小屏幕：使用垂直布局
                layoutWidget = Column(
                  children: [
                    SizedBox(
                      height: screenHeight * 0.3, // 根据屏幕高度调整侧边栏高度
                      child: TemplateSidebar(
                        selectedCategory: selectedCategory,
                        selectedView: selectedView,
                        searchQuery: searchQuery,
                        onCategoryChanged: (category) {
                          if (mounted) {
                            setState(() {
                              selectedCategory = category;
                            });
                          }
                        },
                        onViewChanged: (view) {
                          if (mounted) {
                            setState(() {
                              selectedView = view;
                            });
                          }
                        },
                        onSearchChanged: (query) {
                          if (mounted) {
                            setState(() {
                              searchQuery = query;
                            });
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: TemplateList(
                        selectedView: selectedView,
                        selectedCategory: selectedCategory,
                        searchQuery: searchQuery,
                        allTemplates: allTemplates,
                        myTemplates: myTemplates,
                        teamTemplates: teamTemplates,
                        isLoading: isLoading,
                        error: error,
                        onViewChanged: (view) {
                          if (mounted) {
                            setState(() {
                              selectedView = view;
                            });
                          }
                        },
                        onTemplateUsed: (template) => _useTemplate(context, template),
                      ),
                    ),
                  ],
                );
              }
              
              return layoutWidget;
            },
          ),
        ),
      ),
    );
  }

  /// 显示模版使用确认对话框
  Future<bool> _showTemplateConfirmDialog(BuildContext context, TemplateItem template) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
          children: [
            Icon(
                Icons.description_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
          ),
          const SizedBox(width: 8),
              const Text('使用模版'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Text(
                '确定要使用模版 "${template.title}" 创建新文档吗？',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '模版信息',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      template.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    if (template.author.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '作者: ${template.author}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '使用此模版将创建一个新的文档，您可以在其中开始编写内容。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                '取消',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('确定使用'),
            ),
          ],
        );
      },
    );
    
    return result ?? false;
  }
}
