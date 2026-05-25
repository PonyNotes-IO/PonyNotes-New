import 'package:appflowy/user/application/reminder/notification_service.dart';
import 'package:appflowy/user/application/reminder/notification_settings_service.dart';
import 'package:flutter/material.dart';

class NotificationPermissionBanner extends StatefulWidget {
  const NotificationPermissionBanner({Key? key}) : super(key: key);
  
  @override
  State<NotificationPermissionBanner> createState() => _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState extends State<NotificationPermissionBanner> {
  bool _shouldShow = false;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _checkPermission();
  }
  
  Future<void> _checkPermission() async {
    try {
      // 检查是否已经显示过并且用户点击了取消
      final notificationSettingsService = const NotificationSettingsService();
      final dismissed = await notificationSettingsService.isNotificationPermissionDismissed();
      
      if (!dismissed) {
        final notificationService = NotificationService();
        final hasPermission = await notificationService.checkAndRequestPermission();
        
        if (!hasPermission) {
          setState(() {
            _shouldShow = true;
          });
        }
      }
    } catch (e) {
      // 出错时不显示
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _handleGoToSettings() async {
    final notificationService = NotificationService();
    await notificationService.openNotificationSettings();
    setState(() {
      _shouldShow = false;
    });
  }
  
  Future<void> _handleDismiss() async {
    // 标记为已取消，不再显示
    final notificationSettingsService = const NotificationSettingsService();
    await notificationSettingsService.markNotificationPermissionAsDismissed();
    setState(() {
      _shouldShow = false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();
    if (!_shouldShow) return const SizedBox.shrink();
    
    return Container(
      height: 50,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.blue.shade200),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),
          const Expanded(
            child: Text(
              '开启通知权限以接收日程提醒',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 20),
          Row(
            children: [
              TextButton(
                onPressed: _handleDismiss,
                child: const Text('暂不'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(60, 36),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _handleGoToSettings,
                child: const Text('去设置'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(80, 36),
                ),
              ),
              const SizedBox(width: 20),
            ],
          ),
        ],
      ),
    );
  }
}
