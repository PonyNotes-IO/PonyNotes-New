import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

class TemplateService {
  static const String _baseUrl = 'https://appflowy.com';
  static const String _templateCenterEndpoint = '/api/template-center';
  static const List<String> _websiteCategories = [
    // 官网可见的常见分类 slug（可按需增减）
    'project-management',
    'engineering',
    'startups',
    'education',
    'marketing',
    'management',
    'human-resources',
    'sales-crm',
    'product-design',
    'ai-powered',
    'docs',
    'wiki',
    'database',
    'kanban'
  ];
  
  // 缓存相关
  static List<TemplateItem>? _cachedTemplates;
  static DateTime? _cacheTimestamp;
  static const Duration _cacheExpiry = Duration(minutes: 30);
  
  // 性能优化：预加载和懒加载
  static bool _isLoading = false;
  static final Map<String, List<TemplateItem>> _categoryCache = {};
  
  // 分类缓存大小限制：最多缓存 50 个分类，防止内存溢出
  static const int _maxCategoryCacheSize = 50;
  
  // 模拟模板数据，实际应用中应该从 API 获取
  static final List<TemplateItem> _mockTemplates = [
    TemplateItem(
      id: '1',
      title: 'Weekly To-Do List',
      description: 'Stay organized and productive with this simple yet effective Weekly To-Do List Template',
      category: 'project-management',
      author: 'AppFlowy',
      previewUrl: 'assets/images/template_placeholder_1.png',
      featured: true,
      tags: ['productivity', 'planning', 'weekly'],
      downloadUrl: 'https://appflowy.com/templates/weekly-todo-list',
    ),
    TemplateItem(
      id: '2',
      title: 'Bug Tracker',
      description: 'Streamline your bug reporting and tracking with this easy-to-use template.',
      category: 'engineering',
      author: 'Robin, Founder at Blue Cat Reports',
      previewUrl: 'assets/images/template_placeholder_2.png',
      featured: true,
      tags: ['development', 'bug-tracking', 'engineering'],
      downloadUrl: 'https://appflowy.com/templates/bug-tracker',
    ),
    TemplateItem(
      id: '3',
      title: 'Project planning doc',
      description: 'Start every project with this planning doc.',
      category: 'project-management',
      author: 'AppFlowy',
      previewUrl: 'assets/images/template_placeholder_3.png',
      featured: false,
      tags: ['project', 'planning', 'documentation'],
      downloadUrl: 'https://appflowy.com/templates/project-planning',
    ),
    TemplateItem(
      id: '4',
      title: 'Fundraising tracker',
      description: 'Track your fundraising progress with this comprehensive template.',
      category: 'startups',
      author: 'AppFlowy',
      previewUrl: 'assets/images/built_in_cover_images/m_cover_image_1.png9C27B0/FFFFFF?text=Fundraising+Tracker',
      featured: false,
      tags: ['fundraising', 'startup', 'tracking'],
      downloadUrl: 'https://appflowy.com/templates/fundraising-tracker',
    ),
    TemplateItem(
      id: '5',
      title: 'Meeting Notes',
      description: 'Keep track of your meetings with this structured template.',
      category: 'management',
      author: 'AppFlowy',
      previewUrl: 'assets/images/built_in_cover_images/m_cover_image_1.png607D8B/FFFFFF?text=Meeting+Notes',
      featured: false,
      tags: ['meetings', 'notes', 'management'],
      downloadUrl: 'https://appflowy.com/templates/meeting-notes',
    ),
    TemplateItem(
      id: '6',
      title: 'Content Calendar',
      description: 'Plan and organize your content with this calendar template.',
      category: 'marketing',
      author: 'AppFlowy',
      previewUrl: 'assets/images/built_in_cover_images/m_cover_image_1.pngE91E63/FFFFFF?text=Content+Calendar',
      featured: true,
      tags: ['content', 'calendar', 'marketing'],
      downloadUrl: 'https://appflowy.com/templates/content-calendar',
    ),
    TemplateItem(
      id: '7',
      title: 'Employee Onboarding',
      description: 'Streamline your employee onboarding process with this template.',
      category: 'human-resources',
      author: 'AppFlowy',
      previewUrl: 'assets/images/built_in_cover_images/m_cover_image_1.png795548/FFFFFF?text=Employee+Onboarding',
      featured: false,
      tags: ['hr', 'onboarding', 'employee'],
      downloadUrl: 'https://appflowy.com/templates/employee-onboarding',
    ),
    TemplateItem(
      id: '8',
      title: 'Customer Feedback',
      description: 'Collect and analyze customer feedback with this template.',
      category: 'sales-crm',
      author: 'AppFlowy',
      previewUrl: 'assets/images/built_in_cover_images/m_cover_image_1.pngFF5722/FFFFFF?text=Customer+Feedback',
      featured: false,
      tags: ['customer', 'feedback', 'crm'],
      downloadUrl: 'https://appflowy.com/templates/customer-feedback',
    ),
    TemplateItem(
      id: '9',
      title: 'Simple Weekly To-Do List',
      description: 'Easily manage your daily to-dos',
      category: 'project-management',
      author: 'AppFlowy',
      previewUrl: 'assets/images/built_in_cover_images/m_cover_image_1.png795548/FFFFFF?text=Simple+Weekly+To-Do',
      featured: false,
      tags: ['simple', 'todo', 'daily', 'my-space'],
      downloadUrl: 'https://appflowy.com/templates/simple-weekly-todo',
    ),
    TemplateItem(
      id: '10',
      title: 'Eisenhower Matrix',
      description: 'Use this template to prioritize your tasks and focus on the most important work.',
      category: 'project-management',
      author: 'Crystal @ c_solutions',
      previewUrl: 'assets/images/built_in_cover_images/m_cover_image_1.png009688/FFFFFF?text=Eisenhower+Matrix',
      featured: false,
      tags: ['prioritization', 'matrix', 'productivity', 'my-space'],
      downloadUrl: 'https://appflowy.com/templates/eisenhower-matrix',
    ),
    TemplateItem(
      id: '11',
      title: 'Team Sprint Planning',
      description: 'Plan your team sprints with this comprehensive template.',
      category: 'engineering',
      author: 'AppFlowy',
      previewUrl: 'assets/images/built_in_cover_images/m_cover_image_1.png3F51B5/FFFFFF?text=Team+Sprint+Planning',
      featured: false,
      tags: ['sprint', 'planning', 'team', 'team'],
      downloadUrl: 'https://appflowy.com/templates/team-sprint-planning',
    ),
    TemplateItem(
      id: '12',
      title: 'Product Roadmap',
      description: 'Plan your product development with this roadmap template.',
      category: 'product-design',
      author: 'AppFlowy',
      previewUrl: 'assets/images/built_in_cover_images/m_cover_image_1.pngFF9800/FFFFFF?text=Product+Roadmap',
      featured: true,
      tags: ['product', 'roadmap', 'planning', 'team'],
      downloadUrl: 'https://appflowy.com/templates/product-roadmap',
    ),
  ];

  /// 获取所有模板（带缓存）
  static Future<List<TemplateItem>> getAllTemplates() async {
    // 检查缓存是否有效
    if (_cachedTemplates != null && 
        _cacheTimestamp != null && 
        DateTime.now().difference(_cacheTimestamp!) < _cacheExpiry) {
      return _cachedTemplates!;
    }

    // 防止重复加载
    if (_isLoading) {
      // 等待当前加载完成
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _cachedTemplates ?? _mockTemplates;
    }

    _isLoading = true;
    
    try {
      List<TemplateItem> templates = [];

      // 方案1: 优先从 AppFlowy 官网多分类抓取模板数据
      try {
        templates = await _fetchTemplatesFromWebsiteAll();
        if (templates.isNotEmpty) {
          _updateCache(templates);
          return templates;
        }
      } catch (e) {
        // 官网抓取失败，继续尝试其他方案
      }
      
      // 方案2: 尝试从本地 JSON 文件加载模板数据
      try {
        final jsonString = await rootBundle.loadString('lib/plugins/template/templates_data.json');
        final jsonData = json.decode(jsonString);
        templates = (jsonData['templates'] as List)
            .map((item) => TemplateItem.fromJson(item))
            .toList();
        
        if (templates.isNotEmpty) {
          _updateCache(templates);
          return templates;
        }
      } catch (e) {
        // 本地文件加载失败，继续尝试其他方案
      }
      
      // 方案3: 如果所有方法都失败，返回模拟数据
      await Future.delayed(const Duration(milliseconds: 500));
      templates = _mockTemplates;
      _updateCache(templates);
      return templates;
      
    } catch (e) {
      // 如果所有方法都失败，返回模拟数据
      final templates = _mockTemplates;
      _updateCache(templates);
      return templates;
    } finally {
      _isLoading = false;
    }
  }

  /// 更新缓存
  static void _updateCache(List<TemplateItem> templates) {
    _cachedTemplates = templates;
    _cacheTimestamp = DateTime.now();
    // 清除分类缓存，因为数据已更新
    _categoryCache.clear();
  }

  /// 根据类别获取模板（带缓存）
  static Future<List<TemplateItem>> getTemplatesByCategory(String category) async {
    // 检查分类缓存
    if (_categoryCache.containsKey(category)) {
      return _categoryCache[category]!;
    }

    // 如果是官网分类，优先实时抓取该分类页面
    if (_websiteCategories.contains(category)) {
      try {
        final websiteCategoryTemplates = await _fetchTemplatesFromWebsiteCategory(category);
        if (websiteCategoryTemplates.isNotEmpty) {
          _categoryCache[category] = websiteCategoryTemplates;
          
          // 清理缓存，防止内存溢出
          if (_categoryCache.length > _maxCategoryCacheSize) {
            final oldestKey = _categoryCache.keys.first;
            _categoryCache.remove(oldestKey);
          }
          
          return websiteCategoryTemplates;
        }
      } catch (_) {
        // 忽略抓取失败，回退到本地过滤
      }
    }

    final allTemplates = await getAllTemplates();
    List<TemplateItem> filteredTemplates;
    
    if (category == 'all') {
      filteredTemplates = allTemplates;
    } else {
      filteredTemplates = allTemplates.where((template) => template.category == category).toList();
    }
    
    // 缓存结果
    _categoryCache[category] = filteredTemplates;
    
    // 清理缓存，防止内存溢出
    if (_categoryCache.length > _maxCategoryCacheSize) {
      // 删除最旧的缓存（简化实现：删除第一个）
      final oldestKey = _categoryCache.keys.first;
      _categoryCache.remove(oldestKey);
    }
    
    return filteredTemplates;
  }

  /// 搜索模板
  static Future<List<TemplateItem>> searchTemplates(String query) async {
    final allTemplates = await getAllTemplates();
    if (query.isEmpty) {
      return allTemplates;
    }
    
    final lowercaseQuery = query.toLowerCase();
    return allTemplates.where((template) {
      return template.title.toLowerCase().contains(lowercaseQuery) ||
             template.description.toLowerCase().contains(lowercaseQuery) ||
             template.tags.any((tag) => tag.toLowerCase().contains(lowercaseQuery));
    }).toList();
  }

  /// 获取特色模板
  static Future<List<TemplateItem>> getFeaturedTemplates() async {
    final allTemplates = await getAllTemplates();
    return allTemplates.where((template) => template.featured).toList();
  }

  /// 获取我的模板（个人空间）
  static Future<List<TemplateItem>> getMyTemplates() async {
    try {
      // 优先从 Rust 后端数据库获取
      final rustTemplates = await _getMyTemplatesFromRust();
      if (rustTemplates.isNotEmpty) {
        return rustTemplates;
      }
      
      // 回退到本地缓存
      final allTemplates = await getAllTemplates();
      return allTemplates.where((template) => 
        template.tags.contains('my-space'),).toList();
    } catch (e) {
      // 如果 Rust 后端失败，回退到本地缓存
      final allTemplates = await getAllTemplates();
      return allTemplates.where((template) => 
        template.tags.contains('my-space'),).toList();
    }
  }

  /// 获取团队模板
  static Future<List<TemplateItem>> getTeamTemplates() async {
    final allTemplates = await getAllTemplates();
    return allTemplates.where((template) => 
      template.tags.contains('team'),).toList();
  }

  /// 检查模版是否在我的模版中
  static Future<bool> isTemplateInMyTemplates(String templateId) async {
    final myTemplates = await getMyTemplates();
    return myTemplates.any((template) => template.id == templateId);
  }

  /// 添加模版到我的模版列表（支持云同步）
  static Future<bool> addTemplateToMyTemplates(TemplateItem template) async {
    try {
      // 优先保存到 Rust 后端数据库
      final rustSuccess = await _addTemplateToRust(template);
      if (rustSuccess) {
        // 尝试同步到云端
        await _syncToCloud();
        return true;
      }
      
      // 回退到本地缓存
      return await _addTemplateToLocalCache(template);
    } catch (e) {
      // 如果 Rust 后端失败，回退到本地缓存
      return await _addTemplateToLocalCache(template);
    }
  }

  /// 从我的模版列表中移除模版（支持云同步）
  static Future<bool> removeTemplateFromMyTemplates(String templateId) async {
    try {
      // 从 Rust 后端数据库移除
      final rustSuccess = await _removeTemplateFromRust(templateId);
      if (rustSuccess) {
        // 尝试同步到云端
        await _syncToCloud();
        return true;
      }
      
      // 回退到本地缓存
      if (_cachedTemplates != null) {
        final index = _cachedTemplates!.indexWhere((t) => t.id == templateId);
        if (index != -1) {
          final template = _cachedTemplates![index];
          final updatedTemplate = TemplateItem(
            id: template.id,
            title: template.title,
            description: template.description,
            category: template.category,
            author: template.author,
            previewUrl: template.previewUrl,
            featured: template.featured,
            tags: template.tags.where((tag) => tag != 'my-space').toList(),
            downloadUrl: template.downloadUrl,
          );
          _cachedTemplates![index] = updatedTemplate;
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取数据源信息
  static Future<String> getDataSourceInfo() async {
    try {
      // 尝试从网站获取
      final response = await http.get(
        Uri.parse('$_baseUrl/templates/project-management'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        return 'AppFlowy 官网';
      }
    } catch (e) {
      // 忽略错误
    }
    
    try {
      // 尝试从本地 JSON 文件
      await rootBundle.loadString('lib/plugins/template/templates_data.json');
      return '本地 JSON 文件';
    } catch (e) {
      // 忽略错误
    }
    
    return '模拟数据';
  }

  /// 测试模板获取功能
  static Future<void> testTemplateFetching() async {
    try {
      // 测试网站解析
      await _parseTemplatesFromWebsite();
      
      // 测试本地 JSON
      try {
        final jsonString = await rootBundle.loadString('lib/plugins/template/templates_data.json');
        final jsonData = json.decode(jsonString);
        (jsonData['templates'] as List)
            .map((item) => TemplateItem.fromJson(item))
            .toList();
      } catch (e) {
        // 忽略错误
      }
    } catch (e) {
      // 忽略错误
    }
  }

  /// 从 AppFlowy 官网解析模板数据
  static Future<List<TemplateItem>> _parseTemplatesFromWebsite() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/templates/project-management'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        
        // 尝试从 HTML 中提取模板数据
        final htmlTemplates = _extractTemplatesFromHtml(document);
        if (htmlTemplates.isNotEmpty) {
          return htmlTemplates;
        }
        
        // 尝试从 JavaScript 中提取模板数据
        final jsTemplates = _extractTemplatesFromJavaScript(response.body);
        if (jsTemplates.isNotEmpty) {
          return jsTemplates;
        }
      }
      
      return [];
    } catch (e) {
      return [];
    }
  }

  /// 从 AppFlowy 官网按多个分类抓取并合并、去重
  static Future<List<TemplateItem>> _fetchTemplatesFromWebsiteAll() async {
    final List<TemplateItem> aggregated = [];
    final Set<String> seenIds = {};

    for (final category in _websiteCategories) {
      try {
        final url = Uri.parse('$_baseUrl/templates/$category');
        final response = await http.get(
          url,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          continue;
        }

        final document = html_parser.parse(response.body);
        // 多通道提取并合并
        List<TemplateItem> parsed = <TemplateItem>[
          ..._extractTemplatesFromHtml(document),
          ..._extractTemplatesFromJsonLd(document),
          ..._extractTemplatesFromNextData(response.body),
          ..._extractTemplatesFromJavaScript(response.body),
        ];

        // 若该分类（尤其是 feature 类）未解析到，尝试备用路由与 API 兜底
        if (parsed.isEmpty) {
          parsed = await _tryAlternativeCategoryRoutes(category);
        }
        if (parsed.isEmpty) {
          parsed = await getTemplatesFromAPI(category);
        }

        for (final t in parsed) {
          // 如果页面未能准确归类，用当前分类兜底
          final normalized = TemplateItem(
            id: t.id,
            title: t.title,
            description: t.description,
            category: (t.category.isEmpty ? category : t.category),
            author: t.author,
            previewUrl: _normalizePreviewUrl(t.previewUrl),
            featured: t.featured,
            tags: t.tags,
            downloadUrl: _normalizeDownloadUrl(t.downloadUrl, t.id),
          );

          if (seenIds.add(normalized.id)) {
            aggregated.add(normalized);
          }
        }
      } catch (_) {
        // 忽略单分类失败，继续其他分类
        continue;
      }
    }

    return aggregated;
  }

  /// 抓取单个分类页面
  static Future<List<TemplateItem>> _fetchTemplatesFromWebsiteCategory(String category) async {
    try {
      final url = Uri.parse('$_baseUrl/templates/$category');
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return [];
      }

      final document = html_parser.parse(response.body);
      List<TemplateItem> parsed = <TemplateItem>[
        ..._extractTemplatesFromHtml(document),
        ..._extractTemplatesFromJsonLd(document),
        ..._extractTemplatesFromNextData(response.body),
        ..._extractTemplatesFromJavaScript(response.body),
      ];

      if (parsed.isEmpty) {
        // 备用路由尝试（Feature 分类常用）
        parsed = await _tryAlternativeCategoryRoutes(category);
      }
      if (parsed.isEmpty) {
        // API 兜底
        parsed = await getTemplatesFromAPI(category);
      }

      return parsed
          .map((t) => TemplateItem(
                id: t.id,
                title: t.title,
                description: t.description,
                category: (t.category.isEmpty ? category : t.category),
                author: t.author,
                previewUrl: _normalizePreviewUrl(t.previewUrl),
                featured: t.featured,
                tags: t.tags,
                downloadUrl: _normalizeDownloadUrl(t.downloadUrl, t.id),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 尝试分类的备用 URL 路由解析（主要覆盖 feature 分类）
  static Future<List<TemplateItem>> _tryAlternativeCategoryRoutes(String category) async {
    final candidates = <String>[
      '$_baseUrl/templates/feature/$category',
      '$_baseUrl/templates/by-feature/$category',
      '$_baseUrl/templates?$category',
      '$_baseUrl/templates?feature=$category',
    ];

    for (final u in candidates) {
      try {
        final resp = await http.get(
          Uri.parse(u),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          },
        ).timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) continue;
        final doc = html_parser.parse(resp.body);
        final parsed = <TemplateItem>[
          ..._extractTemplatesFromHtml(doc),
          ..._extractTemplatesFromJsonLd(doc),
          ..._extractTemplatesFromNextData(resp.body),
          ..._extractTemplatesFromJavaScript(resp.body),
        ];
        if (parsed.isNotEmpty) return parsed;
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  /// 从 JSON-LD (schema.org) 结构化数据中提取
  static List<TemplateItem> _extractTemplatesFromJsonLd(html_dom.Document document) {
    final List<TemplateItem> templates = [];
    try {
      final scripts = document.querySelectorAll('script[type="application/ld+json"]');
      for (final s in scripts) {
        final text = s.text.trim();
        if (text.isEmpty) continue;
        final data = json.decode(text);
        void addFrom(Map<String, dynamic> item) {
          final name = (item['name'] ?? '').toString();
          if (name.isEmpty) return;
          final id = (item['@id'] ?? name).toString();
          final desc = (item['description'] ?? '').toString();
          final author = (item['author'] is Map)
              ? ((item['author']['name'] ?? 'AppFlowy').toString())
              : (item['author']?.toString() ?? 'AppFlowy');
          String img = '';
          final image = item['image'];
          if (image is String) img = image; else if (image is Map) {
            img = (image['url'] ?? '').toString();
          }
          final url = (item['url'] ?? '').toString();
          templates.add(TemplateItem(
            id: id,
            title: name,
            description: desc,
            category: '',
            author: author,
            previewUrl: img,
            featured: false,
            tags: const [],
            downloadUrl: url,
          ));
        }
        if (data is List) {
          for (final e in data) {
            if (e is Map<String, dynamic>) addFrom(e);
          }
        } else if (data is Map<String, dynamic>) {
          if (data['@type'] == 'ItemList' && data['itemListElement'] is List) {
            for (final e in (data['itemListElement'] as List)) {
              final item = (e is Map && e['item'] is Map) ? e['item'] as Map<String, dynamic> : null;
              if (item != null) addFrom(item);
            }
          } else {
            addFrom(data);
          }
        }
      }
    } catch (_) {}
    return templates;
  }

  /// 从 Next.js 的 __NEXT_DATA__ 中提取
  static List<TemplateItem> _extractTemplatesFromNextData(String html) {
    final List<TemplateItem> templates = [];
    try {
      final match = RegExp(r'__NEXT_DATA__"\s*type=\"application/json\">(.*?)<\/script>', dotAll: true).firstMatch(html);
      if (match == null) return templates;
      final jsonStr = match.group(1);
      if (jsonStr == null) return templates;
      final data = json.decode(jsonStr);
      final props = data['props'];
      final pageProps = props?['pageProps'];
      final items = pageProps?['templates'] ?? pageProps?['items'];
      if (items is List) {
        for (final it in items) {
          if (it is Map<String, dynamic>) {
            final id = (it['id'] ?? it['slug'] ?? '').toString();
            final title = (it['title'] ?? it['name'] ?? '').toString();
            if (title.isEmpty) continue;
            final description = (it['description'] ?? '').toString();
            final author = (it['author'] ?? it['creator'] ?? 'AppFlowy').toString();
            final preview = (it['cover'] ?? it['image'] ?? it['thumbnail'] ?? '').toString();
            final url = (it['url'] ?? it['href'] ?? '').toString();
            final tags = (it['tags'] is List) ? List<String>.from(it['tags']) : <String>[];
            templates.add(TemplateItem(
              id: id.isNotEmpty ? id : title.toLowerCase().replaceAll(' ', '-'),
              title: title,
              description: description,
              category: (it['category'] ?? '').toString(),
              author: author,
              previewUrl: preview,
              featured: (it['featured'] ?? false) == true,
              tags: tags,
              downloadUrl: url,
            ));
          }
        }
      }
    } catch (_) {}
    return templates;
  }

  static String _normalizePreviewUrl(String url) {
    if (url.isEmpty) return '';
    // 过滤站内相对路径，转为绝对路径
    if (url.startsWith('/')) {
      return '$_baseUrl$url';
    }
    return url;
  }

  static String _normalizeDownloadUrl(String url, String id) {
    if (url.isEmpty) return '';
    if (url.startsWith('/')) {
      return '$_baseUrl$url/$id?action=duplicate';
    }
    return url;
  }

  /// 从 HTML 文档中提取模板数据
  static List<TemplateItem> _extractTemplatesFromHtml(html_dom.Document document) {
    final List<TemplateItem> templates = [];
    
    try {
      // 查找模板卡片容器 - 使用更精确的选择器
      final templateCards = document.querySelectorAll('.template-item, .MuiGrid-item');
      
      for (final card in templateCards) {
        try {
          // 查找模板名称
          final titleElement = card.querySelector('.template-name, .right-info .template-name');
          if (titleElement == null) continue;
          
          final title = titleElement.text.trim();
          if (title.isEmpty) continue;
          
          // 查找描述
          final descriptionElement = card.querySelector('.template-desc, .template-description');
          final description = descriptionElement?.text.trim() ?? '';
          
          // 查找作者
          final authorElement = card.querySelector('.creator-name, .template-creator .creator-name');
          final author = authorElement?.text.trim().replaceAll('by ', '') ?? 'AppFlowy';
          
          // 查找链接
          final linkElement = card.querySelector('a[href*="template"], a[href*="appflowy.com"]');
          final downloadUrl = linkElement?.attributes['href'] ?? '';
          
          // 查找预览图
          final imageElement = card.querySelector('img');
          final previewUrl = imageElement?.attributes['src'] ?? '';
          
          // 根据标题推断类别
          String category = 'project-management';
          if (title.toLowerCase().contains('bug') || title.toLowerCase().contains('development') || title.toLowerCase().contains('scrum')) {
            category = 'engineering';
          } else if (title.toLowerCase().contains('crm') || title.toLowerCase().contains('investor') || title.toLowerCase().contains('fundraising')) {
            category = 'startups';
          } else if (title.toLowerCase().contains('business') || title.toLowerCase().contains('proposal') || title.toLowerCase().contains('hr')) {
            category = 'management';
          } else if (title.toLowerCase().contains('marketing') || title.toLowerCase().contains('content') || title.toLowerCase().contains('social')) {
            category = 'marketing';
          } else if (title.toLowerCase().contains('education') || title.toLowerCase().contains('learning') || title.toLowerCase().contains('course')) {
            category = 'education';
          } else if (title.toLowerCase().contains('design') || title.toLowerCase().contains('product') || title.toLowerCase().contains('ui')) {
            category = 'product-design';
          }
          
          // 生成唯一 ID
          final id = title.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp('[^a-z0-9-]'), '');
          
          // 推断标签
          final tags = <String>[];
          if (title.toLowerCase().contains('weekly') || title.toLowerCase().contains('daily')) {
            tags.add('productivity');
          }
          if (title.toLowerCase().contains('team') || title.toLowerCase().contains('collaboration')) {
            tags.add('team');
          }
          if (title.toLowerCase().contains('planning') || title.toLowerCase().contains('project')) {
            tags.add('planning');
          }
          
          templates.add(TemplateItem(
            id: id,
            title: title,
            description: description,
            category: category,
            author: author,
            previewUrl: previewUrl,
            featured: false,
            tags: tags,
            downloadUrl: downloadUrl,
          ),);
        } catch (e) {
          // 忽略单个模板解析错误
          continue;
        }
      }
    } catch (e) {
      // 忽略解析错误
    }
    
    return templates;
  }

  /// 从 JavaScript 中提取模板数据
  static List<TemplateItem> _extractTemplatesFromJavaScript(String htmlContent) {
    final List<TemplateItem> templates = [];
    
    try {
      // 查找包含模板数据的 JavaScript 代码
      final regex = RegExp(r'templates\s*:\s*(\[.*?\])', multiLine: true);
      final match = regex.firstMatch(htmlContent);
      
      if (match != null) {
        final jsonString = match.group(1);
        if (jsonString != null) {
          final jsonData = json.decode(jsonString);
          if (jsonData is List) {
            for (final item in jsonData) {
              if (item is Map<String, dynamic>) {
                try {
                  templates.add(TemplateItem.fromJson(item));
                } catch (e) {
                  // 忽略单个模板解析错误
                  continue;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      // 忽略解析错误
    }
    
    return templates;
  }

  /// 从 API 获取模板（如果可用）
  static Future<List<TemplateItem>> getTemplatesFromAPI(String category) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl$_templateCenterEndpoint/category?name_contains=$category'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData is List) {
          return jsonData.map((item) => TemplateItem.fromJson(item)).toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    
    return [];
  }

  /// 从 Rust 后端获取我的模板
  static Future<List<TemplateItem>> _getMyTemplatesFromRust() async {
    try {
      // TODO: 实现与 Rust 后端的通信
      // 这里需要调用 Rust 后端的 get_my_templates 方法
      // 暂时返回空列表，等待 Rust 后端集成
      return [];
    } catch (e) {
      return [];
    }
  }

  /// 添加模板到 Rust 后端数据库
  static Future<bool> _addTemplateToRust(TemplateItem template) async {
    try {
      // TODO: 实现与 Rust 后端的通信
      // 这里需要调用 Rust 后端的 add_to_my_templates 方法
      // 暂时返回 false，等待 Rust 后端集成
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 本地缓存添加模板（回退方案）
  static Future<bool> _addTemplateToLocalCache(TemplateItem template) async {
    try {
      // 检查是否已经存在
      final exists = await isTemplateInMyTemplates(template.id);
      if (exists) {
        return true; // 已经存在，返回成功
      }

      // 创建新的模版项，添加 'my-space' 标签
      final myTemplate = TemplateItem(
        id: template.id,
        title: template.title,
        description: template.description,
        category: template.category,
        author: template.author,
        previewUrl: template.previewUrl,
        featured: template.featured,
        tags: [...template.tags, 'my-space'], // 添加 my-space 标签
        downloadUrl: template.downloadUrl,
      );

      // 更新缓存
      if (_cachedTemplates != null) {
        final index = _cachedTemplates!.indexWhere((t) => t.id == template.id);
        if (index != -1) {
          _cachedTemplates![index] = myTemplate;
        } else {
          _cachedTemplates!.add(myTemplate);
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 从 Rust 后端移除模板
  static Future<bool> _removeTemplateFromRust(String templateId) async {
    try {
      // TODO: 实现与 Rust 后端的通信
      // 这里需要调用 Rust 后端的 remove_from_my_templates 方法
      // 暂时返回 false，等待 Rust 后端集成
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 同步到云端
  static Future<void> _syncToCloud() async {
    try {
      // TODO: 实现与 Rust 后端的云同步通信
      // 这里需要调用 Rust 后端的 sync_to_cloud 方法
      print('Syncing templates to cloud...');
    } catch (e) {
      print('Failed to sync to cloud: $e');
    }
  }

  /// 从云端同步
  static Future<void> syncFromCloud() async {
    try {
      // TODO: 实现与 Rust 后端的云同步通信
      // 这里需要调用 Rust 后端的 sync_from_cloud 方法
      print('Syncing templates from cloud...');
      
      // 刷新本地缓存
      await TemplateServiceCache.refreshCache();
    } catch (e) {
      print('Failed to sync from cloud: $e');
    }
  }

  /// 双向同步
  static Future<void> bidirectionalSync() async {
    try {
      // TODO: 实现与 Rust 后端的双向同步通信
      // 这里需要调用 Rust 后端的 bidirectional_sync 方法
      print('Performing bidirectional sync...');
      
      // 刷新本地缓存
      await TemplateServiceCache.refreshCache();
    } catch (e) {
      print('Failed to perform bidirectional sync: $e');
    }
  }

  /// 获取同步状态
  static Future<Map<String, dynamic>?> getSyncStatus() async {
    try {
      // TODO: 实现与 Rust 后端的同步状态查询
      // 这里需要调用 Rust 后端的 get_sync_status 方法
      return {
        'last_sync_timestamp': 0,
        'pending_changes': false,
        'sync_in_progress': false,
      };
    } catch (e) {
      print('Failed to get sync status: $e');
      return null;
    }
  }
}

class TemplateItem {
  final String id;
  final String title;
  final String description;
  final String category;
  final String author;
  final String previewUrl;
  final bool featured;
  final List<String> tags;
  final String downloadUrl;

  const TemplateItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.author,
    required this.previewUrl,
    required this.featured,
    required this.tags,
    required this.downloadUrl,
  });

  factory TemplateItem.fromJson(Map<String, dynamic> json) {
    return TemplateItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      author: json['author'] ?? '',
      previewUrl: json['previewUrl'] ?? '',
      featured: json['featured'] ?? false,
      tags: List<String>.from(json['tags'] ?? []),
      downloadUrl: json['downloadUrl'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'author': author,
      'previewUrl': previewUrl,
      'featured': featured,
      'tags': tags,
      'downloadUrl': downloadUrl,
    };
  }
}

// 缓存管理方法
extension TemplateServiceCache on TemplateService {
  /// 清除缓存
  static void clearCache() {
    TemplateService._cachedTemplates = null;
    TemplateService._cacheTimestamp = null;
    TemplateService._categoryCache.clear();
  }

  /// 预加载模板数据
  static Future<void> preloadTemplates() async {
    if (TemplateService._cachedTemplates == null) {
      await TemplateService.getAllTemplates();
    }
  }

  /// 获取缓存状态
  static Map<String, dynamic> getCacheStatus() {
    return {
      'hasCache': TemplateService._cachedTemplates != null,
      'cacheSize': TemplateService._cachedTemplates?.length ?? 0,
      'cacheAge': TemplateService._cacheTimestamp != null 
          ? DateTime.now().difference(TemplateService._cacheTimestamp!).inMinutes 
          : null,
      'categoryCacheSize': TemplateService._categoryCache.length,
      'isLoading': TemplateService._isLoading,
    };
  }

  /// 强制刷新缓存
  static Future<List<TemplateItem>> refreshCache() async {
    clearCache();
    return TemplateService.getAllTemplates();
  }
}
