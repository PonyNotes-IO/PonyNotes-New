import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import '../services/baidu_cloud_service.dart';

/// 百度网盘文件选择对话框
class BaiduCloudFilePickerDialog extends StatefulWidget {
  final Function(List<BaiduCloudFile>) onFilesSelected;

  const BaiduCloudFilePickerDialog({
    Key? key,
    required this.onFilesSelected,
  }) : super(key: key);

  @override
  State<BaiduCloudFilePickerDialog> createState() => _BaiduCloudFilePickerDialogState();
}

class _BaiduCloudFilePickerDialogState extends State<BaiduCloudFilePickerDialog> {
  final BaiduCloudService _baiduService = BaiduCloudService();
  List<BaiduCloudFile> _files = [];
  List<BaiduCloudFile> _selectedFiles = [];
  String _currentPath = '/';
  bool _isLoading = false;
  bool _isAuthorized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkAuthorization();
  }

  Future<void> _checkAuthorization() async {
    final authorized = await _baiduService.isAuthorized();
    setState(() {
      _isAuthorized = authorized;
    });
    
    if (authorized) {
      _loadFiles();
    }
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final files = await _baiduService.getFileList(dir: _currentPath);
      setState(() {
        _files = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载文件列表失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _authorize() async {
    try {
      final authUrl = _baiduService.getAuthorizationUrl();
      if (await canLaunchUrl(Uri.parse(authUrl))) {
        await launchUrl(Uri.parse(authUrl));
        
        // 显示输入授权码的对话框
        _showAuthCodeDialog();
      }
    } catch (e) {
      setState(() {
        _errorMessage = '启动授权失败: $e';
      });
    }
  }

  void _showAuthCodeDialog() {
    final codeController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入授权码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请在浏览器中完成授权，然后将获得的授权码粘贴到下方：'),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: '授权码',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.isNotEmpty) {
                Navigator.of(context).pop();
                await _exchangeCodeForToken(code);
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  Future<void> _exchangeCodeForToken(String code) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await _baiduService.exchangeCodeForToken(code);
      if (success) {
        setState(() {
          _isAuthorized = true;
          _isLoading = false;
        });
        _loadFiles();
      } else {
        setState(() {
          _errorMessage = '授权失败，请重试';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '授权失败: $e';
        _isLoading = false;
      });
    }
  }

  void _toggleFileSelection(BaiduCloudFile file) {
    setState(() {
      if (_selectedFiles.contains(file)) {
        _selectedFiles.remove(file);
      } else {
        _selectedFiles.add(file);
      }
    });
  }

  void _navigateToDirectory(BaiduCloudFile dir) {
    setState(() {
      _currentPath = dir.path;
      _selectedFiles.clear();
    });
    _loadFiles();
  }

  void _navigateUp() {
    if (_currentPath != '/') {
      final parentPath = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
      setState(() {
        _currentPath = parentPath.isEmpty ? '/' : parentPath;
        _selectedFiles.clear();
      });
      _loadFiles();
    }
  }

  void _confirmSelection() {
    widget.onFilesSelected(_selectedFiles);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 标题栏
            Row(
              children: [
                const Icon(Icons.cloud, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '百度网盘文件选择',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                FlowyIconButton(
                  width: 32,
                  height: 32,
                  hoverColor: Theme.of(context).colorScheme.surface.withOpacity(0.1),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const FlowySvg(
                    FlowySvgs.toast_close_s,
                    size: Size.square(20),
                  ),
                ),
              ],
            ),
            const Divider(),
            
            // 路径导航
            if (_isAuthorized) ...[
              Row(
                children: [
                  IconButton(
                    onPressed: _currentPath != '/' ? _navigateUp : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  Expanded(
                    child: Text(
                      _currentPath,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Divider(),
            ],
            
            // 内容区域
            Expanded(
              child: _buildContent(),
            ),
            
            // 底部按钮
            if (_isAuthorized) ...[
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('已选择 ${_selectedFiles.length} 个文件'),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _selectedFiles.isNotEmpty ? _confirmSelection : null,
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (!_isAuthorized) {
      return _buildAuthorizationView();
    }
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFiles,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    
    if (_files.isEmpty) {
      return const Center(
        child: Text('当前目录为空'),
      );
    }
    
    return ListView.builder(
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final isSelected = _selectedFiles.contains(file);
        
        return ListTile(
          leading: Icon(
            file.isDir == 1 ? Icons.folder : Icons.insert_drive_file,
            color: file.isDir == 1 ? Colors.orange : Colors.blue,
          ),
          title: Text(file.serverFilename),
          subtitle: file.isDir == 1 
              ? const Text('文件夹')
              : Text('${_formatFileSize(file.size)} • ${_getFileExtension(file.serverFilename)}'),
          trailing: file.isDir == 1 
              ? const Icon(Icons.chevron_right)
              : Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleFileSelection(file),
                ),
          onTap: () {
            if (file.isDir == 1) {
              _navigateToDirectory(file);
            } else {
              _toggleFileSelection(file);
            }
          },
        );
      },
    );
  }

  /// 格式化文件大小
  String _formatFileSize(int size) {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// 获取文件扩展名
  String _getFileExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return '';
    return fileName.substring(lastDot);
  }

  Widget _buildAuthorizationView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud, size: 64, color: Colors.blue),
          const SizedBox(height: 16),
          const Text(
            '需要授权访问百度网盘',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击下方按钮进行授权，授权后即可选择网盘中的文件',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _authorize,
            icon: const Icon(Icons.login),
            label: const Text('授权登录'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
