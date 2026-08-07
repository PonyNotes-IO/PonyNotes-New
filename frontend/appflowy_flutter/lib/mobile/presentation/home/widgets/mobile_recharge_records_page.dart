import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/workspace/application/payment/payment_api.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class MobileRechargeRecordsPage extends StatefulWidget {
  const MobileRechargeRecordsPage({super.key});

  static const routeName = '/mobile-recharge-records';

  @override
  State<MobileRechargeRecordsPage> createState() =>
      _MobileRechargeRecordsPageState();
}

class _MobileRechargeRecordsPageState extends State<MobileRechargeRecordsPage> {
  static const int _pageSize = 20;
  final List<PaymentRecordItem> _records = [];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchRecords(reset: true);
  }

  Future<void> _fetchRecords({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final result = await PaymentApi.getMyPaymentList(
      pageNum: reset ? 1 : _currentPage,
      pageSize: _pageSize,
    );

    if (!mounted) return;

    result.fold(
      (page) {
        setState(() {
          _isLoading = false;
          if (reset) {
            _records.clear();
            _currentPage = 1;
          }
          _records.addAll(page.list);
          _hasMore = _records.length < page.total;
          if (_hasMore) _currentPage++;
        });
      },
      (error) {
        setState(() {
          _isLoading = false;
          _errorMessage = error.msg;
        });
      },
    );
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _fetchRecords(reset: false);
    if (mounted) setState(() => _isLoadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const MobileAppBar(
        title: '充值记录',
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(AppFlowyThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null && _records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.secondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _fetchRecords(reset: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_records.isEmpty) {
      return Center(
        child: Text(
          '暂无充值记录',
          style: theme.textStyle.body.standard(
            color: theme.textColorScheme.secondary,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchRecords(reset: true),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _records.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _records.length) {
            if (_isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return const SizedBox.shrink();
          }

          final record = _records[index];
          final isLast = index == _records.length - 1;
          return _buildRecordCard(theme, record, isLast);
        },
      ),
    );
  }

  Widget _buildRecordCard(
    AppFlowyThemeData theme,
    PaymentRecordItem record,
    bool isLast,
  ) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF2A2A2A)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.borderColorScheme.primary.withOpacity(isDarkMode ? 0.3 : 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FlowySvg(
                FlowySvgs.pony_notes_logo_xl,
                blendMode: null,
                size: const Size(20, 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  record.productName.isEmpty ? '--' : record.productName,
                  style: theme.textStyle.body.standard(
                    color: theme.textColorScheme.primary,
                  ).copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '¥${record.amount.toStringAsFixed(2)}',
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.primary,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabelValue(theme, '支付时间', record.payTime),
                    const SizedBox(height: 4),
                    _buildLabelValue(theme, '创建时间', record.createTime),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildStatusChip(theme, record.status),
                  const SizedBox(height: 4),
                  Text(
                    _buildPaymentTypeText(record.paymentType),
                    style: theme.textStyle.body.standard(
                      color: theme.textColorScheme.secondary,
                    ).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLabelValue(AppFlowyThemeData theme, String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: theme.textStyle.body.standard(
            color: theme.textColorScheme.secondary,
          ).copyWith(fontSize: 12),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '--' : value,
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.secondary,
            ).copyWith(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(AppFlowyThemeData theme, String status) {
    final isSuccess = status.contains('成功') || status.contains('SUCCESS') || status == '1';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSuccess
            ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
            : const Color(0xFFFF9800).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.isEmpty ? '--' : status,
        style: theme.textStyle.body.standard(
          color: isSuccess ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
        ).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  String _buildPaymentTypeText(String paymentType) {
    switch (paymentType.toUpperCase()) {
      case 'APPLE_PAY':
        return 'Apple Pay';
      case 'WECHAT_PAY':
        return '微信支付';
      case 'ALIPAY':
        return '支付宝';
      default:
        return paymentType.isEmpty ? '--' : paymentType;
    }
  }
}
