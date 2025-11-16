import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy/workspace/application/settings/share/import_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:markdown_widget/markdown_widget.dart';
import 'mineru_api_processor.dart';

/// 增强的PDF导入对话框，提供多种处理模式和实时预览
class EnhancedPdfImportDialog extends StatefulWidget {
  final String parentViewId;
  final VoidCallback? onImportSuccess;

  const EnhancedPdfImportDialog({
    super.key,
    required this.parentViewId,
    this.onImportSuccess,
  });

  @override
  State<EnhancedPdfImportDialog> createState() => _EnhancedPdfImportDialogState();
}

class _EnhancedPdfImportDialogState extends State<EnhancedPdfImportDialog> {
  File? _selectedFile;
  Uint8List? _pdfBytes;
  String? _extractedContent;
  String? _processingError;
  bool _isProcessing = false;
  PdfImportMode _importMode = PdfImportMode.professional;
  CancellationToken? _cancellationToken;

  @override
  void dispose() {
    // 清理资源：取消正在进行的任务
    _cancelProcessing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double dialogMaxWidth = 900;
    final double dialogMaxHeight = 700;
    final double dialogWidth = screenSize.width * 0.9 > dialogMaxWidth
        ? dialogMaxWidth
        : screenSize.width * 0.9;
    final double dialogHeight = screenSize.height * 0.9 > dialogMaxHeight
        ? dialogMaxHeight
        : screenSize.height * 0.9;

    return Dialog(
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildModeSelector(),
            const SizedBox(height: 16),
            _buildFileSelector(),
            const SizedBox(height: 16),
            if (_selectedFile != null) ...[
              _buildProcessButton(),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: _buildContentPreview(),
            ),
            const SizedBox(height: 16),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.picture_as_pdf, size: 32, color: Colors.red),
        const SizedBox(width: 12),
        const Text(
          '智能PDF导入',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        IconButton(
          onPressed: () {
            _cancelProcessing();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '处理模式',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: PdfImportMode.values.map((mode) {
            return ChoiceChip(
              label: Text(mode.displayName),
              selected: _importMode == mode,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _importMode = mode;
                    _extractedContent = null;
                  });
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          _importMode.description,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildFileSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '选择PDF文件',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_selectedFile == null)
            GestureDetector(
              onTap: _selectFile,
              child: Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey[400]!,
                    style: BorderStyle.solid,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_upload, size: 32, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      '点击选择PDF文件',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFile!.path.split('/').last,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton(
                  onPressed: _selectFile,
                  child: const Text('更换文件'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildProcessButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _selectedFile != null && !_isProcessing ? _processFile : null,
        icon: _isProcessing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome),
        label: Text(_isProcessing ? '处理中...' : '开始处理'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildContentPreview() {
    if (_processingError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          border: Border.all(color: Colors.red[200]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    '处理失败',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_processingError!),
              const SizedBox(height: 12),
              if (_buildErrorHints(_processingError!).isNotEmpty) ...[
                const Text(
                  '建议：',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ..._buildErrorHints(_processingError!).map((h) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(child: Text(h)),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      );
    }

    if (_extractedContent == null || _extractedContent!.isEmpty) {
      String message = '选择文件并点击"开始处理"来预览提取的内容';
      if (_isProcessing) {
        message = '正在处理中，请稍候...';
      }
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isProcessing ? Icons.hourglass_empty : Icons.preview,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '提取内容预览',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (_pdfBytes != null && _extractedContent != null)
              TextButton.icon(
                onPressed: _showHybridPreview,
                icon: const Icon(Icons.preview),
                label: const Text('混合预览'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: MarkdownWidget(
                data: _extractedContent!,
                shrinkWrap: true,
                selectable: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<String> _buildErrorHints(String message) {
    final lower = message.toLowerCase();
    final hints = <String>[];
    if (lower.contains('未授权') || lower.contains('401')) {
      hints.add('请先登录 AppFlowy Cloud，然后重试导入。');
    }
    if (lower.contains('权限不足') || lower.contains('403')) {
      hints.add('确认当前登录账号对文件存储有权限。');
      hints.add('若使用反向代理，请放行 Authorization 头到 /api/file_storage/**，并允许 PUT/POST。');
      hints.add('确保 APPFLOWY_CLOUD_URL 指向正确的 Cloud 根地址（含 http/https）。');
    }
    if (lower.contains('过大') || lower.contains('413')) {
      hints.add('减小 PDF 文件体积，或在反向代理上增大 client_max_body_size。');
    }
    if (lower.contains('服务器错误') || RegExp(r'\b5\d{2}\b').hasMatch(lower)) {
      hints.add('服务器暂时不可用，请稍后重试或检查 Cloud 服务端日志。');
    }
    return hints;
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        TextButton(
          onPressed: () {
            _cancelProcessing();
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        if (_isProcessing)
          ElevatedButton(
            onPressed: () {
              _cancelProcessing();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('取消处理'),
          )
        else
          ElevatedButton(
            onPressed: _extractedContent != null ? _importDocument : null,
            child: const Text('导入文档'),
          ),
      ],
    );
  }
  
  /// Cancel current processing task
  void _cancelProcessing() {
    if (_isProcessing && _cancellationToken != null) {
      _cancellationToken!.cancel();
      setState(() {
        _isProcessing = false;
        _processingError = '处理已取消';
      });
      Log.info('PDF处理任务已取消');
    }
  }

  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        setState(() {
          _selectedFile = file;
          _extractedContent = null;
          _processingError = null;
        });
      }
    } catch (e) {
      Log.error('Failed to select PDF file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败: $e')),
      );
    }
  }

  Future<void> _processFile() async {
    if (_selectedFile == null) return;

    // 创建新的取消令牌
    _cancellationToken = CancellationToken();
    
    // 读取PDF文件bytes用于混合预览
    Uint8List? pdfBytes;
    try {
      pdfBytes = await _selectedFile!.readAsBytes();
    } catch (e) {
      Log.warn('Failed to read PDF bytes: $e');
    }
    
    setState(() {
      _isProcessing = true;
      _processingError = null;
      _extractedContent = null; // 重置提取内容
      _pdfBytes = pdfBytes; // 设置PDF bytes
    });

    try {
      String content;
      
      // 根据选择的模式处理PDF，使用MinerU API
      switch (_importMode) {
        case PdfImportMode.professional:
          // 使用MinerU API进行专业处理
          content = await MinerUApiProcessor.processPdfFile(
            _selectedFile!,
            mode: MinerUMode.professional,
            language: null, // 自动检测语言
            enableOcr: false,
            enableTable: false,
            enableFormula: false,
            cancellationToken: _cancellationToken,
          );
          break;
        case PdfImportMode.advanced:
          // 使用MinerU API进行高级处理
          content = await MinerUApiProcessor.processPdfFile(
            _selectedFile!,
            mode: MinerUMode.advanced,
            language: null, // 自动检测语言
            enableOcr: false,
            enableTable: true,
            enableFormula: true,
            cancellationToken: _cancellationToken,
          );
          break;
        case PdfImportMode.ocr:
          // 使用MinerU API进行OCR处理
          content = await MinerUApiProcessor.processPdfFile(
            _selectedFile!,
            mode: MinerUMode.ocr,
            language: null, // 自动检测语言
            enableOcr: true,
            enableTable: true,
            enableFormula: false,
            cancellationToken: _cancellationToken,
          );
          break;
        case PdfImportMode.visual:
          // 使用MinerU API进行复杂布局处理
          content = await MinerUApiProcessor.processPdfFile(
            _selectedFile!,
            mode: MinerUMode.complexLayout,
            language: null, // 自动检测语言
            enableOcr: true,
            enableTable: true,
            enableFormula: true,
            cancellationToken: _cancellationToken,
          );
          break;
      }

      // 检查是否已取消
      if (_cancellationToken?.isCancelled ?? false) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _processingError = '处理已取消';
          });
        }
        return;
      }

      // 验证内容是否为空
      if (content.trim().isEmpty) {
        Log.warn('Extracted content is empty');
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _processingError = '提取的内容为空，请检查PDF文件是否包含文本内容';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _extractedContent = content;
          _isProcessing = false;
        });
        Log.info('Content preview updated, length: ${content.length}');
      }

    } catch (e) {
      // 如果是取消操作，不记录错误
      if (e.toString().contains('已取消') || e.toString().contains('取消')) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _processingError = '处理已取消';
          });
        }
        return;
      }
      
      Log.error('Failed to process PDF: $e');
      if (mounted) {
        setState(() {
          _processingError = 'PDF处理失败: $e';
          _isProcessing = false;
        });
      }
    } finally {
      _cancellationToken = null;
    }
  }

  void _showHybridPreview() {
    if (_pdfBytes != null && _extractedContent != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PdfHybridPreviewScreen(
            pdfBytes: _pdfBytes!,
            extractedText: _extractedContent!,
            fileName: p.basenameWithoutExtension(_selectedFile!.path),
          ),
        ),
      );
    }
  }

  Future<void> _importDocument() async {
    if (_extractedContent == null) return;

    try {
      final fileName = p.basenameWithoutExtension(_selectedFile!.path);
      
      // 将Markdown转换为Document格式
      final document = customMarkdownToDocument(_extractedContent!);
      final documentBytes = DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
      
      if (documentBytes != null) {
        final importValues = [
          ImportItemPayloadPB.create()
            ..name = fileName
            ..data = documentBytes
            ..viewLayout = ViewLayoutPB.Document
            ..importType = ImportTypePB.Markdown,
        ];
        
        await ImportBackendService.importPages(widget.parentViewId, importValues);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('成功导入PDF文档: $fileName'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
          widget.onImportSuccess?.call();
        }
      }
    } catch (e) {
      Log.error('Failed to import PDF document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

enum PdfImportMode {
  professional('专业模式', '智能识别文档结构，保持格式和层次'),
  advanced('高级模式', '深度分析内容，优化表格和列表'),
  ocr('OCR模式', '图像文字识别，适用于扫描文档'),
  visual('视觉模式', '保持视觉布局，适用于复杂排版');

  const PdfImportMode(this.displayName, this.description);

  final String displayName;
  final String description;
}

/// PDF混合预览屏幕
class PdfHybridPreviewScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  final String extractedText;
  final String fileName;

  const PdfHybridPreviewScreen({
    super.key,
    required this.pdfBytes,
    required this.extractedText,
    required this.fileName,
  });

  @override
  State<PdfHybridPreviewScreen> createState() => _PdfHybridPreviewScreenState();
}

class _PdfHybridPreviewScreenState extends State<PdfHybridPreviewScreen> {
  late pdfx.PdfController _pdfController;
  bool _isLoading = true;
  String? _error;
  int _currentPage = 1;
  int _totalPages = 0;
  double _zoom = 1.0;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _initializePdf();
  }

  Future<void> _initializePdf() async {
    try {
      // 初始化PDF控制器
      _pdfController = pdfx.PdfController(
        document: pdfx.PdfDocument.openData(widget.pdfBytes),
      );
      
      // 获取文档信息
      final document = await pdfx.PdfDocument.openData(widget.pdfBytes);
      _totalPages = document.pagesCount;
      
      setState(() {
        _isLoading = false;
      });
      
      Log.info('PDF混合预览初始化成功: ${widget.fileName}, $_totalPages 页');
      
    } catch (e) {
      Log.error('PDF混合预览初始化失败: $e');
      setState(() {
        _error = 'PDF加载失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('混合预览: ${widget.fileName}'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _showControls = !_showControls;
              });
            },
            icon: Icon(_showControls ? Icons.visibility_off : Icons.visibility),
            tooltip: _showControls ? '隐藏控制栏' : '显示控制栏',
          ),
          IconButton(
            onPressed: () {
              // TODO: 实现保存功能
            },
            icon: const Icon(Icons.save),
            tooltip: '保存',
          ),
        ],
      ),
      body: Row(
        children: [
          // PDF原文显示
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[100],
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf, color: Colors.red),
                      const SizedBox(width: 8),
                      const Text('原文档', style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_showControls && !_isLoading && _error == null) ...[
                        IconButton(
                          onPressed: _currentPage > 1 ? () => _pdfController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          ) : null,
                          icon: const Icon(Icons.chevron_left),
                          tooltip: '上一页',
                        ),
                        Text('$_currentPage / $_totalPages'),
                        IconButton(
                          onPressed: _currentPage < _totalPages ? () => _pdfController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          ) : null,
                          icon: const Icon(Icons.chevron_right),
                          tooltip: '下一页',
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _zoom > 0.5 ? () => setState(() => _zoom -= 0.1) : null,
                          icon: const Icon(Icons.zoom_out),
                          tooltip: '缩小',
                        ),
                        Text('${(_zoom * 100).toInt()}%'),
                        IconButton(
                          onPressed: _zoom < 3.0 ? () => setState(() => _zoom += 0.1) : null,
                          icon: const Icon(Icons.zoom_in),
                          tooltip: '放大',
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Colors.grey[50],
                    child: _buildPdfViewer(),
                  ),
                ),
                if (_showControls && !_isLoading && _error == null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: Colors.grey[200],
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16),
                        const SizedBox(width: 4),
                        Text('PDF文档: ${widget.fileName}'),
                        const Spacer(),
                        Text('总页数: $_totalPages'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 1,
            color: Colors.grey[300],
          ),
          // 提取文本显示
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[100],
                  child: const Row(
                    children: [
                      Icon(Icons.text_fields, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('解析结果 (Markdown)', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: _buildMarkdownViewer(),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: Colors.blue[50],
                  child: Row(
                    children: [
                      const Icon(Icons.text_fields, size: 16, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text('Markdown解析结果'),
                      const Spacer(),
                      Text('字符数: ${widget.extractedText.length}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载PDF...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.red.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _initializePdf(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Transform.scale(
      scale: _zoom,
      child: pdfx.PdfView(
        controller: _pdfController,
        scrollDirection: Axis.vertical,
        onDocumentLoaded: (document) {
          Log.debug('PDF文档在混合预览中加载: ${document.pagesCount} 页');
        },
        onPageChanged: (page) {
          setState(() {
            _currentPage = page;
          });
        },
        backgroundDecoration: BoxDecoration(
          color: Colors.grey.shade200,
        ),
      ),
    );
  }

  Widget _buildMarkdownViewer() {
    return MarkdownWidget(
      data: widget.extractedText,
      shrinkWrap: true,
      selectable: true,
    );
  }
}