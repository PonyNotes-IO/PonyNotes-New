import 'package:appflowy/plugins/template/services/template_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:fixnum/fixnum.dart';

import '../../document/application/document_service.dart';

/// AppFlowy模版集成服务
/// 负责将模版转换为AppFlowy工作空间中的实际文档
class AppFlowyTemplateIntegration {
  
  /// 使用模版创建新文档
  static Future<bool> useTemplate({
    required BuildContext context,
    required TemplateItem template,
    required String workspaceId,
    required int userId,
  }) async {
    try {
      // 1. 获取模版数据
      final templateData = await _fetchTemplateData(template);
      if (templateData == null) {
        if (context.mounted) {
          _showError(context, '无法获取模版数据');
        }
        return false;
      }

      // 2. 生成初始内容（Markdown -> Document -> bytes）
      final String markdown = (templateData['content'] as String?)?.trim().isNotEmpty == true
          ? (templateData['content'] as String)
          : _generateTemplateContent(template);
      final document = customMarkdownToDocument(markdown, tableWidth: 250.0);
      final initialBytes = DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
      if (initialBytes == null) {
        if (context.mounted) {
          _showError(context, '模板内容生成失败');
        }
        return false;
      }

      // 3. 创建新文档（携带初始内容）
      final result = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Document,
        parentViewId: workspaceId,
        name: template.title,
        openAfterCreate: true,
        initialDataBytes: initialBytes,
        ext: {
          'template_id': template.id,
          if (template.downloadUrl.isNotEmpty) 'template_source': template.downloadUrl,
        },
      );

      return result.fold(
        (view) async {
          // 4. 添加到我的模版列表（如未存在）
          await _addToMyTemplatesIfNeeded(template);
          if (context.mounted) {
            _showSuccess(context, '已根据模版创建文档: ${template.title}');
          }
          return true;
        },
        (error) async {
          if (context.mounted) {
            _showError(context, '创建文档失败: ${error.msg}');
          }
          return false;
        },
      );
    } catch (e) {
      if (context.mounted) {
        _showError(context, '使用模版时发生错误: $e');
      }
      return false;
    }
  }

  /// 从AppFlowy官网获取模版数据
  static Future<Map<String, dynamic>?> _fetchTemplateData(TemplateItem template) async {
    try {
      // 这里可以实现从AppFlowy官网获取模版的具体实现
      // 目前返回模拟数据
      return {
        'title': template.title,
        'content': _generateTemplateContent(template),
        'metadata': {
          'author': template.author,
          'category': template.category,
          'tags': template.tags,
        },
      };
    } catch (e) {
      return null;
    }
  }

  /// 根据模版类型生成内容
  static String _generateTemplateContent(TemplateItem template) {
    switch (template.category) {
      case 'project-management':
        return _generateProjectManagementTemplate();
      case 'engineering':
        return _generateEngineeringTemplate();
      case 'startup':
        return _generateStartupTemplate();
      case 'education':
        return _generateEducationTemplate();
      case 'marketing':
        return _generateMarketingTemplate();
      case 'management':
        return _generateManagementTemplate();
      case 'hr':
        return _generateHRTemplate();
      case 'sales-crm':
        return _generateSalesCRMTemplate();
      case 'team-meeting':
        return _generateTeamMeetingTemplate();
      case 'product-design':
        return _generateProductDesignTemplate();
      default:
        return _generateDefaultTemplate(template);
    }
  }

  /// 项目管理模版内容
  static String _generateProjectManagementTemplate() {
    return '''
# 项目管理模版

## 项目概述
- **项目名称**: [项目名称]
- **项目经理**: [项目经理]
- **开始日期**: [开始日期]
- **预计完成日期**: [完成日期]

## 项目目标
- [ ] 目标1
- [ ] 目标2
- [ ] 目标3

## 项目里程碑
| 里程碑 | 开始日期 | 完成日期 | 状态 |
|--------|----------|----------|------|
| 需求分析 | | | 待开始 |
| 设计阶段 | | | 待开始 |
| 开发阶段 | | | 待开始 |
| 测试阶段 | | | 待开始 |
| 上线部署 | | | 待开始 |

## 团队成员
- [ ] 开发人员
- [ ] 测试人员
- [ ] 设计师
- [ ] 产品经理

## 风险评估
| 风险 | 影响程度 | 发生概率 | 应对措施 |
|------|----------|----------|----------|
| 技术风险 | 高 | 中 | 提前技术调研 |
| 时间风险 | 中 | 高 | 增加缓冲时间 |
| 资源风险 | 中 | 低 | 备用方案 |

## 项目进度
- [ ] 需求确认
- [ ] 技术方案设计
- [ ] 开发环境搭建
- [ ] 核心功能开发
- [ ] 测试用例编写
- [ ] 上线部署

## 会议记录
### [日期] 项目启动会议
- 参会人员: 
- 会议内容: 
- 待办事项: 

## 文档链接
- [需求文档]()
- [技术文档]()
- [测试文档]()
''';
  }

  /// 工程模版内容
  static String _generateEngineeringTemplate() {
    return '''
# 工程开发模版

## 技术栈
- **前端**: 
- **后端**: 
- **数据库**: 
- **部署**: 

## 开发环境
- [ ] 开发工具安装
- [ ] 代码仓库配置
- [ ] 数据库配置
- [ ] 测试环境搭建

## 代码规范
- [ ] 代码风格统一
- [ ] 注释规范
- [ ] 提交信息规范
- [ ] 代码审查流程

## 测试计划
- [ ] 单元测试
- [ ] 集成测试
- [ ] 性能测试
- [ ] 安全测试

## 部署流程
- [ ] 开发环境部署
- [ ] 测试环境部署
- [ ] 生产环境部署
- [ ] 回滚方案

## 技术债务
- [ ] 代码重构
- [ ] 性能优化
- [ ] 安全加固
- [ ] 文档完善
''';
  }

  /// 初创企业模版内容
  static String _generateStartupTemplate() {
    return '''
# 初创企业模版

## 公司信息
- **公司名称**: 
- **成立时间**: 
- **创始人**: 
- **核心团队**: 

## 商业模式
- **目标客户**: 
- **价值主张**: 
- **收入来源**: 
- **成本结构**: 

## 市场分析
- **市场规模**: 
- **竞争对手**: 
- **竞争优势**: 
- **市场机会**: 

## 产品规划
- **MVP功能**: 
- **产品路线图**: 
- **技术架构**: 
- **用户体验**: 

## 财务规划
- **启动资金**: 
- **收入预测**: 
- **成本预算**: 
- **融资计划**: 

## 运营计划
- **营销策略**: 
- **销售渠道**: 
- **客户服务**: 
- **团队建设**: 
''';
  }

  /// 教育模版内容
  static String _generateEducationTemplate() {
    return '''
# 教育课程模版

## 课程信息
- **课程名称**: 
- **授课教师**: 
- **课程时长**: 
- **学分**: 

## 学习目标
- [ ] 目标1
- [ ] 目标2
- [ ] 目标3

## 课程大纲
### 第一章: [章节名称]
- 学习内容: 
- 重点难点: 
- 作业要求: 

### 第二章: [章节名称]
- 学习内容: 
- 重点难点: 
- 作业要求: 

## 学习资源
- [ ] 教材
- [ ] 视频资料
- [ ] 在线资源
- [ ] 实践项目

## 考核方式
- **平时成绩**: 40%
- **期中考试**: 30%
- **期末考试**: 30%

## 学习计划
- [ ] 预习阶段
- [ ] 学习阶段
- [ ] 复习阶段
- [ ] 考试阶段
''';
  }

  /// 营销模版内容
  static String _generateMarketingTemplate() {
    return '''
# 营销活动模版

## 活动概述
- **活动名称**: 
- **活动时间**: 
- **活动地点**: 
- **目标受众**: 

## 营销目标
- **品牌知名度**: 
- **用户增长**: 
- **销售转化**: 
- **用户留存**: 

## 营销策略
- **内容营销**: 
- **社交媒体**: 
- **广告投放**: 
- **合作伙伴**: 

## 预算分配
- **广告费用**: 
- **内容制作**: 
- **活动执行**: 
- **其他费用**: 

## 执行计划
- [ ] 前期准备
- [ ] 内容制作
- [ ] 渠道投放
- [ ] 效果监测

## 效果评估
- **关键指标**: 
- **数据收集**: 
- **分析报告**: 
- **优化建议**: 
''';
  }

  /// 管理模版内容
  static String _generateManagementTemplate() {
    return '''
# 管理模版

## 团队信息
- **团队名称**: 
- **团队规模**: 
- **团队结构**: 
- **管理层次**: 

## 管理目标
- [ ] 目标1
- [ ] 目标2
- [ ] 目标3

## 管理流程
- **决策流程**: 
- **沟通机制**: 
- **反馈机制**: 
- **改进机制**: 

## 团队建设
- [ ] 人员招聘
- [ ] 培训发展
- [ ] 绩效考核
- [ ] 激励机制

## 管理工具
- [ ] 项目管理工具
- [ ] 沟通工具
- [ ] 协作工具
- [ ] 监控工具

## 管理指标
- **团队效率**: 
- **员工满意度**: 
- **项目完成率**: 
- **质量指标**: 
''';
  }

  /// 人力资源模版内容
  static String _generateHRTemplate() {
    return '''
# 人力资源模版

## 招聘计划
- **岗位需求**: 
- **招聘渠道**: 
- **面试流程**: 
- **录用标准**: 

## 员工信息
- **基本信息**: 
- **职位信息**: 
- **薪资信息**: 
- **合同信息**: 

## 培训计划
- **新员工培训**: 
- **技能培训**: 
- **管理培训**: 
- **职业发展**: 

## 绩效考核
- **考核周期**: 
- **考核标准**: 
- **考核流程**: 
- **结果应用**: 

## 员工关系
- **沟通机制**: 
- **问题处理**: 
- **员工关怀**: 
- **离职管理**: 
''';
  }

  /// 销售和客户关系管理模版内容
  static String _generateSalesCRMTemplate() {
    return '''
# 销售和客户关系管理模版

## 客户信息
- **客户名称**: 
- **联系人**: 
- **联系方式**: 
- **客户类型**: 

## 销售机会
- **机会名称**: 
- **预计金额**: 
- **成交概率**: 
- **预计成交时间**: 

## 销售流程
- [ ] 线索获取
- [ ] 需求分析
- [ ] 方案设计
- [ ] 商务谈判
- [ ] 合同签署
- [ ] 项目实施

## 客户服务
- **服务内容**: 
- **服务标准**: 
- **响应时间**: 
- **满意度调查**: 

## 销售指标
- **销售目标**: 
- **完成情况**: 
- **客户满意度**: 
- **续约率**: 
''';
  }

  /// 团队会议模版内容
  static String _generateTeamMeetingTemplate() {
    return '''
# 团队会议模版

## 会议信息
- **会议主题**: 
- **会议时间**: 
- **会议地点**: 
- **参会人员**: 

## 会议议程
- [ ] 议题1
- [ ] 议题2
- [ ] 议题3

## 会议记录
### 讨论内容
- 

### 决策事项
- 

### 待办事项
- [ ] 任务1 - 负责人: - 截止时间: 
- [ ] 任务2 - 负责人: - 截止时间: 
- [ ] 任务3 - 负责人: - 截止时间: 

## 下次会议
- **时间**: 
- **地点**: 
- **议题**: 
''';
  }

  /// 产品与设计模版内容
  static String _generateProductDesignTemplate() {
    return '''
# 产品与设计模版

## 产品信息
- **产品名称**: 
- **产品类型**: 
- **目标用户**: 
- **核心功能**: 

## 设计目标
- **用户体验**: 
- **视觉设计**: 
- **交互设计**: 
- **可用性**: 

## 设计流程
- [ ] 需求分析
- [ ] 用户研究
- [ ] 概念设计
- [ ] 原型设计
- [ ] 视觉设计
- [ ] 开发配合

## 设计规范
- **色彩规范**: 
- **字体规范**: 
- **图标规范**: 
- **组件规范**: 

## 设计工具
- [ ] 设计软件
- [ ] 原型工具
- [ ] 协作工具
- [ ] 版本控制

## 设计评审
- **评审标准**: 
- **评审流程**: 
- **反馈机制**: 
- **迭代优化**: 
''';
  }

  /// 默认模版内容
  static String _generateDefaultTemplate(TemplateItem template) {
    return '''
# ${template.title}

## 模版信息
- **作者**: ${template.author}
- **分类**: ${template.category}
- **标签**: ${template.tags.join(', ')}

## 模版描述
${template.description}

## 使用说明
1. 根据您的需求修改内容
2. 添加必要的详细信息
3. 定期更新和优化

## 自定义内容
- 

## 备注
- 
''';
  }

  /// 显示成功消息
  static void _showSuccess(BuildContext context, String message) {
    showToastNotification(
      message: message,
      type: ToastificationType.success,
    );
  }

  /// 设置模版内容
  static Future<bool> _setTemplateContent(
    BuildContext context,
    ViewPB view,
    TemplateItem template,
  ) async {
    try {
      // 生成模版内容（暂时不使用，因为需要更复杂的API来设置内容）
      // final content = _generateTemplateContent(template);
      
      // 使用 DocumentService 打开文档
      final documentService = DocumentService();
      final documentResult = await documentService.openDocument(
        documentId: view.id,
      );
      
      if (documentResult.isSuccess) {
        // 这里需要设置文档内容，但目前 AppFlowy 的 API 可能不支持直接设置内容
        // 我们可以通过其他方式来实现，比如使用 AppFlowyEditor
        return true;
      } else {
        if (context.mounted) {
          _showError(context, '无法打开文档');
        }
        return false;
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, '设置模版内容失败: $e');
      }
      return false;
    }
  }


  /// 检查并添加到我的模版列表（如果需要）
  static Future<void> _addToMyTemplatesIfNeeded(TemplateItem template) async {
    try {
      // 检查模版是否已经在我的模版中
      final exists = await TemplateService.isTemplateInMyTemplates(template.id);
      if (!exists) {
        // 如果不存在，添加到我的模版列表
        await TemplateService.addTemplateToMyTemplates(template);
      }
    } catch (e) {
      // 静默处理错误，不影响主要功能
      print('添加模版到我的模版列表失败: $e');
    }
  }

  /// 显示错误消息
  static void _showError(BuildContext context, String message) {
    showToastNotification(
      message: message,
      type: ToastificationType.error,
    );
  }
}
