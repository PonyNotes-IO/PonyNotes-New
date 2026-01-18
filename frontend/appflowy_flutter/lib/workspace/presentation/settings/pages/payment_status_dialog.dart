import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/workspace/application/settings/account/account_management_bloc.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart'
    show UserWorkspaceBloc, UserWorkspaceEvent;

/// 显示支付结果查询弹框
/// 
/// [orderNo] 订单号
/// [onPaymentSuccess] 支付成功回调
/// [onClose] 用户关闭弹框回调
Future<void> showPaymentStatusDialog(
  BuildContext context, {
  required String orderNo,
  VoidCallback? onPaymentSuccess,
  VoidCallback? onClose,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false, // 不允许点击外部关闭
    builder: (dialogContext) => BlocProvider.value(
      value: context.read<AccountManagementBloc>(),
      child: _PaymentStatusDialog(
        orderNo: orderNo,
        onPaymentSuccess: onPaymentSuccess,
        onClose: onClose,
      ),
    ),
  );
}

class _PaymentStatusDialog extends StatefulWidget {
  const _PaymentStatusDialog({
    required this.orderNo,
    this.onPaymentSuccess,
    this.onClose,
  });

  final String orderNo;
  final VoidCallback? onPaymentSuccess;
  final VoidCallback? onClose;

  @override
  State<_PaymentStatusDialog> createState() => _PaymentStatusDialogState();
}

class _PaymentStatusDialogState extends State<_PaymentStatusDialog> {
  bool _isClosed = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return BlocListener<AccountManagementBloc, AccountManagementState>(
      listener: (context, state) {
        state.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            addons,
            selectedPlan,
            selectedDuration,
            selectedTab,
            selectedAddonIndex,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isLoadingAddons,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            // 检查错误信息
            if (error != null && error.isNotEmpty) {
              // 有错误信息，显示错误状态，不自动关闭
              // 特别处理验签错误
              if (error.contains('invalid-signature') || error.contains('验签出错')) {
                // 验签错误，提示用户联系客服或稍后重试
              }
            }
            
            // 检查支付结果
            if (paymentResult != null && paymentResult.contains('支付成功')) {
              if (!_isClosed && mounted) {
                _isClosed = true;
                // 刷新订阅信息
                _refreshSubscriptionInfo(context);
                // 调用成功回调
                widget.onPaymentSuccess?.call();
                // 关闭弹框
                Navigator.of(context).pop();
              }
            } else if (paymentResult != null && 
                       (paymentResult.contains('支付失败') || 
                        paymentResult.contains('订单已过期') ||
                        paymentResult.contains('invalid-signature') ||
                        paymentResult.contains('验签出错'))) {
              // 支付失败、过期或验签错误，不自动关闭，让用户手动关闭
            }
          },
        );
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '支付结果查询',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: theme.textColorScheme.secondary,
                      size: 20,
                    ),
                    onPressed: () {
                      if (!_isClosed && mounted) {
                        _isClosed = true;
                        widget.onClose?.call();
                        Navigator.of(context).pop();
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 订单号
              Text(
                '订单号：${widget.orderNo}',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textColorScheme.secondary,
                ),
              ),
              const SizedBox(height: 16),
              // 查询状态
              BlocBuilder<AccountManagementBloc, AccountManagementState>(
                builder: (context, state) {
                  return state.maybeWhen(
                    orElse: () => _buildQueryingStatus(theme),
                    ready: (
                      subscriptionInfo,
                      planConfigs,
                      addons,
                      selectedPlan,
                      selectedDuration,
                      selectedTab,
                      selectedAddonIndex,
                      agreedProtocols,
                      isLoadingSubscription,
                      isLoadingPlans,
                      isLoadingAddons,
                      isProcessingPayment,
                      error,
                      paymentResult,
                    ) {
                      // 检查是否有错误信息
                      if (error != null && error.isNotEmpty) {
                        return _buildErrorStatus(theme, error);
                      }
                      
                      if (paymentResult != null && paymentResult.contains('支付成功')) {
                        return _buildSuccessStatus(theme);
                      } else if (paymentResult != null && 
                                 (paymentResult.contains('支付失败') || 
                                  paymentResult.contains('订单已过期') ||
                                  paymentResult.contains('invalid-signature') ||
                                  paymentResult.contains('验签出错'))) {
                        return _buildFailedStatus(theme, paymentResult);
                      } else {
                        return _buildQueryingStatus(theme);
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              // 关闭按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (!_isClosed && mounted) {
                      _isClosed = true;
                      widget.onClose?.call();
                      Navigator.of(context).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueryingStatus(AppFlowyThemeData theme) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '正在查询支付结果...',
            style: TextStyle(
              fontSize: 14,
              color: theme.textColorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStatus(AppFlowyThemeData theme) {
    return Row(
      children: [
        Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '支付成功',
            style: TextStyle(
              fontSize: 14,
              color: Colors.green,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFailedStatus(AppFlowyThemeData theme, String message) {
    String displayMessage = '支付失败';
    
    if (message.contains('过期')) {
      displayMessage = '订单已过期';
    } else if (message.contains('invalid-signature') || message.contains('验签出错')) {
      displayMessage = '支付验证失败，请稍后重试或联系客服';
    } else if (message.contains('支付失败')) {
      displayMessage = '支付失败';
    }
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayMessage,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (message.contains('invalid-signature') || message.contains('验签出错')) ...[
                const SizedBox(height: 8),
                Text(
                  '如问题持续，请联系客服处理',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorScheme.tertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorStatus(AppFlowyThemeData theme, String error) {
    String displayMessage = '支付异常';
    String detailMessage = '';
    
    if (error.contains('invalid-signature') || error.contains('验签出错')) {
      displayMessage = '支付验证失败';
      detailMessage = '系统配置异常，请联系客服或稍后重试';
    } else if (error.contains('订单') || error.contains('支付')) {
      displayMessage = error;
    } else {
      displayMessage = '支付异常：$error';
    }
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline,
          color: Colors.orange,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayMessage,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (detailMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  detailMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorScheme.tertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _refreshSubscriptionInfo(BuildContext context) {
    try {
      // 刷新 SettingsDialogBloc
      context.read<SettingsDialogBloc>().add(
            const SettingsDialogEvent.initial(),
          );
      
      // 刷新 UserWorkspaceBloc
      final workspaceBloc = context.read<UserWorkspaceBloc?>();
      if (workspaceBloc != null) {
        workspaceBloc.add(
          UserWorkspaceEvent.updateCloudSyncEnabled(enabled: true),
        );
        workspaceBloc.add(
          UserWorkspaceEvent.fetchCurrentSubscription(),
        );
      }
    } catch (e) {
      Log.warn('刷新订阅信息失败: $e');
    }
  }
}
