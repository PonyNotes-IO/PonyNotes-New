import 'package:flutter/material.dart';
import '../services/template_service.dart';

class TemplateSyncStatusWidget extends StatefulWidget {
  const TemplateSyncStatusWidget({Key? key}) : super(key: key);

  @override
  State<TemplateSyncStatusWidget> createState() => _TemplateSyncStatusWidgetState();
}

class _TemplateSyncStatusWidgetState extends State<TemplateSyncStatusWidget> {
  Map<String, dynamic>? _syncStatus;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
  }

  Future<void> _loadSyncStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final status = await TemplateService.getSyncStatus();
      setState(() {
        _syncStatus = status;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _syncToCloud() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await TemplateService.syncFromCloud();
      await _loadSyncStatus();
    } catch (e) {
      // 处理错误
    }
  }

  Future<void> _syncFromCloud() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await TemplateService.syncFromCloud();
      await _loadSyncStatus();
    } catch (e) {
      // 处理错误
    }
  }

  Future<void> _bidirectionalSync() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await TemplateService.bidirectionalSync();
      await _loadSyncStatus();
    } catch (e) {
      // 处理错误
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_sync, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '模板云同步',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_syncStatus != null) ...[
              _buildStatusItem(
                '最后同步时间',
                _formatTimestamp(_syncStatus!['last_sync_timestamp']),
              ),
              const SizedBox(height: 8),
              _buildStatusItem(
                '待同步更改',
                _syncStatus!['pending_changes'] ? '是' : '否',
                _syncStatus!['pending_changes'] ? Colors.orange : Colors.green,
              ),
              const SizedBox(height: 8),
              _buildStatusItem(
                '同步进行中',
                _syncStatus!['sync_in_progress'] ? '是' : '否',
                _syncStatus!['sync_in_progress'] ? Colors.blue : Colors.grey,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _syncToCloud,
                    icon: const Icon(Icons.cloud_upload, size: 16),
                    label: const Text('同步到云端'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _syncFromCloud,
                    icon: const Icon(Icons.cloud_download, size: 16),
                    label: const Text('从云端同步'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _bidirectionalSync,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('双向同步'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, [Color? valueColor]) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null || timestamp == 0) {
      return '从未同步';
    }
    
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
             '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '格式错误';
    }
  }
}
