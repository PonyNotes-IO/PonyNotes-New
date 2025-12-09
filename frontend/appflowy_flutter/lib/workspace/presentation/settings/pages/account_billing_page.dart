import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../../application/settings/settings_dialog_bloc.dart';
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
  bool _isLoading = true;
  List<_AddonPlan> _addons = const [];

  @override
  void didUpdateWidget(covariant BillingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile) {
      _currentUserProfile = widget.userProfile;
      _loadAddons();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAddons();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final hasPlans = _addons.isNotEmpty;
    final selectedPlan =
        hasPlans ? _addons[_selectedPlanIndex.clamp(0, _addons.length - 1)] : null;

    return SettingsBody(
      title: '空间补充包',
      headerTrailingBuilder: (_) => OutlinedRoundedButton(
        text: '购买记录',
        onTap: () => context.read<SettingsDialogBloc>().add(
              const SettingsDialogEvent.setSelectedPage(
                SettingsPage.addonPurchaseRecords,
              ),
            ),
      ),
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
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (!hasPlans) ...[
              const SizedBox(height: 12),
              const Center(child: Text('暂无可用的补充包')),
              const SizedBox(height: 12),
            ] else
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = theme.spacing.l;
                final maxWidth =
                    constraints.maxWidth.isFinite ? constraints.maxWidth : 960.0;
                const double minCardWidth = 220;
                int crossAxisCount =
                    (maxWidth / (minCardWidth + spacing)).floor();
                crossAxisCount = crossAxisCount.clamp(1, _addons.length);

                final cardWidth = (maxWidth -
                        spacing * (crossAxisCount - 1)) /
                    crossAxisCount;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: List.generate(_addons.length, (index) {
                    final plan = _addons[index];
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
                            if (plan.isStorage) ...[
                              FlowyText(
                                plan.storageLabel,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: theme.textColorScheme.primary,
                              ),
                            ] else ...[
                              FlowyText(
                                plan.tokensLabel,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: theme.textColorScheme.primary,
                              ),
                            ],
                            const VSpace(12),
                            FlowyText(
                              '${plan.priceYuanStr}',
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
            if (hasPlans && selectedPlan != null)
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
                      '¥${selectedPlan.priceYuanStr} 确认协议并扩充',
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
          _buildAiUsageSubtitle(context),
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

  String _buildAiUsageSubtitle(BuildContext context) {
    final state = context.read<SettingsDialogBloc>().state;
    final usage = state.currentSubscription?.usage;
    final remaining = usage?.aiChatRemaining;
    if (remaining == null) {
      return '';
    }
    return '本月剩余$remaining次';
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

  Future<void> _loadAddons() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn('补充包接口 baseUrl 为空');
        setState(() {
          _addons = const [];
          _isLoading = false;
        });
        return;
      }

      final accessToken = _extractAccessToken(_currentUserProfile.token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.warn('补充包接口缺少 access_token');
        setState(() {
          _addons = const [];
          _isLoading = false;
        });
        return;
      }

      final uri = Uri.parse(baseUrl).replace(path: '/api/subscription/addons');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        Log.warn(
          '补充包接口返回非 200: ${response.statusCode}, body: ${response.body}',
        );
        setState(() {
          _addons = const [];
          _isLoading = false;
        });
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      if (code != 0) {
        Log.warn('补充包接口 code!=0: code=$code, message=${decoded['message']}');
        setState(() {
          _addons = const [];
          _isLoading = false;
        });
        return;
      }

      final data = decoded['data'];
      if (data is! List) {
        Log.warn('补充包接口 data 不是数组');
        setState(() {
          _addons = const [];
          _isLoading = false;
        });
        return;
      }

      final List<_AddonPlan> addons = [];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final plan = _AddonPlan.fromJson(item);
        if (plan.isActive == true) {
          addons.add(plan);
        }
      }

      setState(() {
        _addons = addons;
        _isLoading = false;
        _selectedPlanIndex = 0;
      });
    } catch (e, stackTrace) {
      Log.error('补充包接口请求异常: $e', e, stackTrace);
      setState(() {
        _addons = const [];
        _isLoading = false;
      });
    }
  }

  String? _extractAccessToken(String? rawToken) {
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        final accessToken = decoded['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          return accessToken;
        }
      }
    } catch (_) {
      return rawToken;
    }
    return null;
  }

  /// 处理补充包支付
  Future<void> _handleBillingPay(
    BuildContext context,
    _AddonPlan selectedPlan,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final addonId = selectedPlan.id;
    if (addonId == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('无法获取补充包信息'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final accessToken = _extractAccessToken(_currentUserProfile.token);
    if (accessToken == null || accessToken.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('缺少访问凭证，无法购买补充包'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
    final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
    if (baseUrl.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('服务地址未配置，无法购买补充包'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final uri = Uri.parse(baseUrl).replace(
      path: '/api/subscription/addons/purchase',
    );

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'addon_id': addonId,
          'quantity': 1,
        }),
      );

      if (response.statusCode != 200) {
        Log.warn(
          '购买补充包接口返回非 200: ${response.statusCode}, body: ${response.body}',
        );
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('购买失败：${response.statusCode}'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      final message = decoded['message']?.toString() ?? '';
      if (code != 0) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message.isNotEmpty ? message : '购买失败'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      // 购买成功后刷新设置页订阅信息（含存储用量）
      if (context.mounted) {
        context.read<SettingsDialogBloc>().add(const SettingsDialogEvent.initial());
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(message.isNotEmpty ? message : '补充包购买成功'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e, stackTrace) {
      Log.error('购买补充包接口异常: $e', e, stackTrace);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('购买失败：$e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _AddonPlan {
  final int? id;
  final String addonCode;
  final String addonType;
  final String name;
  final double? priceYuan;
  final int? storageGb;
  final int? aiChatCount;
  final int? aiImageCount;
  final bool? isActive;

  const _AddonPlan({
    required this.id,
    required this.addonCode,
    required this.addonType,
    required this.name,
    required this.priceYuan,
    required this.storageGb,
    required this.aiChatCount,
    required this.aiImageCount,
    required this.isActive,
  });

  String get priceYuanStr =>
      priceYuan == null ? '0' : priceYuan!.toStringAsFixed(2);
  bool get isStorage => addonType == 'storage';
  bool get isAiToken => addonType == 'ai_token';

  String get storageLabel =>
      storageGb == null ? '存储空间 --' : '存储空间 ${storageGb}G';

  String get tokensLabel {
    if (aiChatCount == null && aiImageCount == null) return 'AI Token --';
    final chatStr = aiChatCount == null ? '' : '对话${aiChatCount}次';
    final imageStr = aiImageCount == null ? '' : ' 图片${aiImageCount}张';
    final merged = [chatStr, imageStr].where((e) => e.isNotEmpty).join(' ');
    return merged.isEmpty ? 'AI Token --' : 'AI Token $merged';
  }

  factory _AddonPlan.fromJson(Map<String, dynamic> json) {
    double? _parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? _parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return _AddonPlan(
      id: _parseInt(json['id']),
      addonCode: (json['addon_code'] as String?) ?? '',
      addonType: (json['addon_type'] as String?) ?? '',
      name: (json['addon_name_cn'] as String?) ??
          (json['addon_name'] as String?) ??
          '补充包',
      priceYuan: _parseDouble(json['price_yuan']),
      storageGb: _parseInt(json['storage_gb']),
      aiChatCount: _parseInt(json['ai_chat_count']),
      aiImageCount: _parseInt(json['ai_image_count']),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}


