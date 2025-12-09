import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/primary_rounded_button.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AddonPurchaseRecordsView extends StatefulWidget {
  const AddonPurchaseRecordsView({
    super.key,
    required this.changeSelectedPage,
  });

  final void Function(SettingsPage page) changeSelectedPage;

  @override
  State<AddonPurchaseRecordsView> createState() =>
      _AddonPurchaseRecordsViewState();
}

class _AddonPurchaseRecordsViewState extends State<AddonPurchaseRecordsView> {
  bool _isLoading = true;
  List<_AddonRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Row(
            children: [
              OutlinedRoundedButton(
                text: '返回',
                onTap: () =>
                    widget.changeSelectedPage(SettingsPage.billingPage),
              ),
              Expanded(
                child: Center(
                  child: FlowyText(
                    '空间购买记录',
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 120),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.borderColorScheme.primary.withOpacity(0.2),
                ),
              ),
              child: _isLoading
                  ? const Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child:
                            CircularProgressIndicator.adaptive(strokeWidth: 3),
                      ),
                    )
                  : _records.isEmpty
                      ? const Center(
                          child: FlowyText(
                            '暂无购买记录',
                            fontSize: 14,
                          ),
                        )
                      : Column(
                          children: [
                            _buildTableHeader(theme),
                            const Divider(height: 1, thickness: 1),
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: _onRefresh,
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: _records.length,
                                  itemBuilder: (context, index) {
                                    final record = _records[index];
                                    return _buildRecordRow(
                                      theme,
                                      record,
                                      isLast: index == _records.length - 1,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader(AppFlowyThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: const [
          Expanded(flex: 3, child: _HeaderCell('补充包名称')),
          Expanded(child: _HeaderCell('类型')),
          Expanded(child: _HeaderCell('数量')),
          Expanded(flex: 2, child: _HeaderCell('开始时间')),
          Expanded(flex: 2, child: _HeaderCell('结束时间')),
          Expanded(child: _HeaderCell('状态')),
        ],
      ),
    );
  }

  Widget _buildRecordRow(
    AppFlowyThemeData theme,
    _AddonRecord record, {
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast
                ? Colors.transparent
                : theme.borderColorScheme.primary.withOpacity(0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                FlowySvg(
                  FlowySvgs.pony_notes_logo_xl,
                  size: const Size(20, 20),
                ),
                const HSpace(8),
                Expanded(
                  child: Text(
                    record.name,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textColorScheme.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FlowyText(
              record.typeLabel,
              fontSize: 14,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: FlowyText(
              '${record.quantity}',
              fontSize: 14,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: FlowyText(
              record.startTime,
              fontSize: 14,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: FlowyText(
              record.endTime,
              fontSize: 14,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: FlowyText(
              record.statusLabel,
              fontSize: 14,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        setState(() {
          _records = const [];
          _isLoading = false;
        });
        return;
      }

      final profileResult = await UserBackendService.getCurrentUserProfile();
      String? rawToken;
      profileResult.fold(
        (p) => rawToken = p.token,
        (e) => rawToken = null,
      );

      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) {
        setState(() {
          _records = const [];
          _isLoading = false;
        });
        return;
      }

      final uri = Uri.parse(baseUrl).replace(
        path: '/api/subscription/addons/my',
      );
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        setState(() {
          _records = const [];
          _isLoading = false;
        });
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      if (code != 0) {
        setState(() {
          _records = const [];
          _isLoading = false;
        });
        return;
      }

      final data = decoded['data'];
      if (data is! List) {
        setState(() {
          _records = const [];
          _isLoading = false;
        });
        return;
      }

      final List<_AddonRecord> records = [];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        records.add(_AddonRecord.fromJson(item));
      }

      setState(() {
        _records = records;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _records = const [];
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _loadRecords();
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
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return FlowyText(
      title,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      textAlign: TextAlign.center,
    );
  }
}

class _AddonRecord {
  final String name;
  final String type;
  final int quantity;
  final String startTime;
  final String endTime;
  final String status;

  _AddonRecord({
    required this.name,
    required this.type,
    required this.quantity,
    required this.startTime,
    required this.endTime,
    required this.status,
  });

  String get typeLabel {
    switch (type) {
      case 'storage':
        return '存储空间';
      case 'ai_token':
        return 'AI Token';
      default:
        return type;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'active':
        return '生效中';
      case 'expired':
        return '已过期';
      case 'used':
        return '已使用';
      default:
        return status;
    }
  }

  factory _AddonRecord.fromJson(Map<String, dynamic> json) {
    String _fmtTime(String? v) {
      if (v == null || v.isEmpty) return '--';
      try {
        final dt = DateTime.parse(v).toLocal();
        return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return v;
      }
    }

    int _parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return _AddonRecord(
      name: (json['addon_name_cn'] as String?) ??
          (json['addon_code'] as String?) ??
          '补充包',
      type: (json['addon_type'] as String?) ?? '',
      quantity: _parseInt(json['quantity']),
      startTime: _fmtTime(json['start_date'] as String?),
      endTime: _fmtTime(json['end_date'] as String?),
      status: (json['status'] as String?) ?? '',
    );
  }
}


