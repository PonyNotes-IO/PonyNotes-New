import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/settings/settings_dialog_bloc.dart';
import '../../../application/payment/payment_api.dart';
import '../../../application/payment/payment_util.dart';
import '../../../../features/workspace/logic/workspace_bloc.dart';
import '../shared/settings_body.dart';
import '../widgets/email_binding_dialog.dart';
import '../widgets/identity_verification_dialog.dart';
import '../widgets/phone_change_dialog.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({
    super.key,
    required this.userProfile,
  });

  final UserProfilePB userProfile;

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  int _selectedPlanIndex = 0;
  late UserProfilePB _currentUserProfile = widget.userProfile;

  final List<_StoragePlan> _plans = const [
    _StoragePlan(
      name: 'A扩充方案',
      storage: '存储空间 5G',
      tokens: 'AI token 100次/天',
      price: 5,
    ),
    _StoragePlan(
      name: 'B扩充方案',
      storage: '存储空间 20G',
      tokens: 'AI token 500次/天',
      price: 15,
    ),
    _StoragePlan(
      name: 'C扩充方案',
      storage: '存储空间 50G',
      tokens: 'AI token 1000次/天',
      price: 35,
    ),
  ];

  @override
  void didUpdateWidget(covariant BillingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile) {
      _currentUserProfile = widget.userProfile;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final selectedPlan = _plans[_selectedPlanIndex];

    return SettingsBody(
      title: '空间补充包',
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FlowyText(
              '个人云存储空间',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.textColorScheme.primary,
            ),
            const VSpace(16),
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = theme.spacing.l;
                final maxWidth =
                    constraints.maxWidth.isFinite ? constraints.maxWidth : 960.0;
                const double minCardWidth = 220;
                int crossAxisCount =
                    (maxWidth / (minCardWidth + spacing)).floor();
                crossAxisCount = crossAxisCount.clamp(1, _plans.length);

                final cardWidth = (maxWidth -
                        spacing * (crossAxisCount - 1)) /
                    crossAxisCount;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: List.generate(_plans.length, (index) {
                    final plan = _plans[index];
                    final isSelected = index == _selectedPlanIndex;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedPlanIndex = index;
                        });
                      },
                      child: Container(
                        width: cardWidth,
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 24,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFF7F2)
                              : theme.surfaceColorScheme.layer01,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFFF6B47)
                                : const Color(0xFFE9E9E9),
                            width: isSelected ? 1.6 : 1.0,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            FlowyText(
                              plan.name,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: theme.textColorScheme.primary,
                            ),
                            const VSpace(12),
                            FlowyText(
                              plan.storage,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: theme.textColorScheme.primary,
                            ),
                            const VSpace(4),
                            FlowyText(
                              plan.tokens,
                              fontSize: 14,
                              color: theme.textColorScheme.secondary,
                            ),
                            const VSpace(12),
                            FlowyText(
                              '${plan.price}元/月',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFF6B47),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const VSpace(24),
            Center(
              child: GestureDetector(
                onTap: () => _handleBillingPay(context, selectedPlan),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3EC),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: FlowyText(
                    '¥${selectedPlan.price}元确认协议并扩充',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFF6B47),
                  ),
                ),
              ),
            ),
            const VSpace(32),
            _buildFeatureSection(context),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureSection(BuildContext context) {
    final settingsBloc = context.read<SettingsDialogBloc>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VSpace(16),
        _buildFeatureItem(
          context,
          '文档光标颜色',
          '购买',
          showArrow: true,
        ),
        _buildFeatureItem(
          context,
          'AI使用次数',
          '今日剩余20次升级',
          showArrow: true,
        ),
        _buildFeatureItem(
          context,
          '个人资料',
          '',
          showArrow: true,
          onTap: () {
            settingsBloc.add(
              const SettingsDialogEvent.setSelectedPage(SettingsPage.userProfile),
            );
          },
        ),
        _buildFeatureItem(
          context,
          '绑定手机',
          '修改',
          showButton: true,
          buttonText: '修改',
          onTap: () => _showPhoneVerificationDialog(context),
        ),
        _buildFeatureItem(
          context,
          '邮箱',
          '修改',
          showButton: true,
          buttonText: '修改',
          onTap: () => _showEmailVerificationDialog(context),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(
    BuildContext context,
    String title,
    String subtitle, {
    bool showArrow = false,
    bool showButton = false,
    String buttonText = '',
    VoidCallback? onTap,
  }) {
    final theme = AppFlowyTheme.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
        child: Row(
          children: [
            Expanded(
              child: FlowyText(
                title,
                fontSize: 16,
                color: theme.textColorScheme.primary,
              ),
            ),
            if (subtitle.isNotEmpty && !showButton)
              FlowyText(
                subtitle,
                fontSize: 14,
                color: theme.textColorScheme.secondary,
              ),
            if (showButton)
              FlowyText(
                buttonText,
                fontSize: 14,
                color: theme.textColorScheme.secondary,
              ),
            if (showArrow)
              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey,
              ),
          ],
        ),
      ),
    );
  }

  void _showPhoneVerificationDialog(BuildContext context) {
    Log.info(
      '用户资料 - email: ${_currentUserProfile.email}, name: ${_currentUserProfile.name}',
    );

    String phoneNumber = '';

    if (_currentUserProfile.hasPhone() && _currentUserProfile.phone.isNotEmpty) {
      phoneNumber = _currentUserProfile.phone;
      Log.info('从用户资料的 phone 字段获取到手机号: $phoneNumber');
    } else if (_currentUserProfile.email.isNotEmpty &&
        !_currentUserProfile.email.contains('@') &&
        Validator.isValidPhone(_currentUserProfile.email)) {
      phoneNumber = _currentUserProfile.email;
      Log.info('从用户资料的 email 字段获取到手机号: $phoneNumber');
    } else {
      Log.info('用户资料中没有有效的手机号，显示输入对话框');
      _showPhoneInputDialog(context);
      return;
    }

    final outerContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => IdentityVerificationDialog(
        phoneNumber: phoneNumber,
        onVerificationComplete: () {
          _showPhoneChangeDialog(outerContext);
        },
      ),
    );
  }

  void _showPhoneInputDialog(BuildContext context) {
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入手机号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请输入您要绑定的手机号码'),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                hintText: '请输入手机号',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final phone = phoneController.text.trim();
              if (phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请输入手机号'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }

              if (!Validator.isValidPhone(phone)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请输入正确的手机号格式'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }

              Navigator.of(context).pop();
              showDialog(
                context: context,
                builder: (context) => IdentityVerificationDialog(
                  phoneNumber: phone,
                  onVerificationComplete: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('手机验证完成'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showPhoneChangeDialog(BuildContext context) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final settingsBloc = context.read<SettingsDialogBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => PhoneChangeDialog(
        onChangeComplete: () async {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('手机号更改成功'),
              duration: Duration(seconds: 2),
            ),
          );

          Log.info('📱 开始刷新用户资料...');
          final result = await UserBackendService.getCurrentUserProfile();
          result.fold(
            (newProfile) {
              Log.info(
                '✅ 刷新后的用户资料: name=${newProfile.name}, email=${newProfile.email}',
              );
              if (!mounted) {
                return;
              }
              setState(() {
                _currentUserProfile = newProfile;
              });
              settingsBloc.add(
                SettingsDialogEvent.didReceiveUserProfile(newProfile),
              );
            },
            (error) {
              Log.error('❌ 刷新用户资料失败: ${error.msg}');
            },
          );
        },
      ),
    );
  }

  void _showEmailVerificationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EmailBindingDialog(
        onBindingComplete: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('邮箱绑定完成'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  /// 处理补充包支付
  Future<void> _handleBillingPay(
    BuildContext context,
    _StoragePlan selectedPlan,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // 1. 获取 workspaceId
    final workspaceBloc = context.read<UserWorkspaceBloc>();
    final workspaceId = workspaceBloc.state.currentWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('无法获取工作空间信息'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 2. 根据平台选择支付方式（macOS: Apple Pay; Windows: 微信/支付宝）
    final methods = PaymentPlatformSupport.getAvailableMethods();
    if (methods.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('当前平台暂不支持支付功能'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 暂时默认选择第一个可用支付方式，后续可增加 UI 让用户选择
    final method = methods.first;

    // 3. 先调用后端创建支付订单接口
    final paymentType = switch (method) {
      PaymentMethod.applePay => PaymentType.applePay,
      PaymentMethod.wechatPay => PaymentType.wechatPay,
      PaymentMethod.alipay => PaymentType.alipay,
    };

    // 补充包价格（单位：元）
    final amount = selectedPlan.price.toDouble();

    final createRequest = PaymentCreateRequest(
      amount: amount,
      paymentType: paymentType,
      productName: selectedPlan.name,
      // 这里暂时使用 workspaceId 作为 openId，后续如果有专门的 openId 可替换
      openId: workspaceId,
      // 回调地址先占位，后端可按需要使用
      url: '',
      userInfo: <String, dynamic>{
        'userId': _currentUserProfile.id.toString(),
        'name': _currentUserProfile.name,
        'email': _currentUserProfile.email,
        'planName': selectedPlan.name,
        'storage': selectedPlan.storage,
        'tokens': selectedPlan.tokens,
      },
    );

    final orderResult = await PaymentApi.createPaymentOrder(createRequest);

    if (orderResult.isFailure) {
      final error = orderResult.fold((_) => null, (e) => e);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(error?.msg ?? '创建支付订单失败'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final order = orderResult.fold(
      (order) => order,
      (_) => null,
    );
    if (order == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('创建支付订单失败'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 4. 调用统一支付工具类（传递真实订单号和金额）
    final result = await PaymentUtil.pay(
      method: method,
      amount: (order.amount * 100).round(), // 转为整型，例如单位分
      currency: 'CNY',
      orderId: order.orderId,
      extra: <String, dynamic>{
        'planName': selectedPlan.name,
        'storage': selectedPlan.storage,
        'tokens': selectedPlan.tokens,
        'displayPrice': amount,
        'order': order.raw,
      },
    );

    // 5. 根据支付结果提示用户
    if (result.success) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(result.message.isNotEmpty ? result.message : '支付成功'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(result.message.isNotEmpty ? result.message : '支付失败'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _StoragePlan {
  final String name;
  final String storage;
  final String tokens;
  final int price;

  const _StoragePlan({
    required this.name,
    required this.storage,
    required this.tokens,
    required this.price,
  });
}


