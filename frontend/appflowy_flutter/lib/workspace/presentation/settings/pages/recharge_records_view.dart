import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/application/payment/payment_api.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/primary_rounded_button.dart';
import 'package:flutter/material.dart';

class RechargeRecordsView extends StatefulWidget {
  const RechargeRecordsView({
    super.key,
    required this.changeSelectedPage,
  });

  final void Function(SettingsPage page) changeSelectedPage;

  @override
  State<RechargeRecordsView> createState() => _RechargeRecordsViewState();
}

class _RechargeRecordsViewState extends State<RechargeRecordsView> {
  static const int _pageSize = 10;
  final List<PaymentRecordItem> _records = [];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isInitialLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchRecords(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedRoundedButton(
                    text: '返回',
                    onTap: () =>
                        widget.changeSelectedPage(SettingsPage.accountManagement),
                  ),
                ),
                const Center(
                  child: FlowyText(
                    '充值记录',
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 980;
                final tableWidth = constraints.maxWidth;
                return SizedBox(
                  width: tableWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.borderColorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildTableHeader(theme, isCompact: isCompact),
                        const Divider(height: 1, thickness: 1),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _onRefresh,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _handleScrollNotification,
                              child: _buildRecordList(theme, isCompact: isCompact),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordList(
    AppFlowyThemeData theme, {
    required bool isCompact,
  }) {
    if (_isInitialLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_errorMessage != null && _records.isEmpty) {
      return Center(
        child: FlowyText(
          _errorMessage!,
          fontSize: 14,
          color: theme.textColorScheme.secondary,
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_records.isEmpty) {
      return const Center(
        child: FlowyText(
          '暂无充值记录',
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _records.length + 1,
      itemBuilder: (context, index) {
        if (index == _records.length) {
          return _buildLoadMoreFooter(theme);
        }
        final record = _records[index];
        return _buildRecordRow(
          theme,
          record,
          isCompact: isCompact,
          isLast: index == _records.length - 1,
        );
      },
    );
  }

  Widget _buildTableHeader(
    AppFlowyThemeData theme, {
    required bool isCompact,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: isCompact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: const [
          Expanded(flex: 2,child: _HeaderCell('产品名称')),
          Expanded(child: _HeaderCell('价格')),
          Expanded(flex: 2, child: _HeaderCell('支付时间')),
          Expanded(flex: 2, child: _HeaderCell('创建时间')),
          Expanded(child: _HeaderCell('计费类型')),
          Expanded(child: _HeaderCell('支付方式')),
          Expanded(child: _HeaderCell('状态')),
        ],
      ),
    );
  }

  Widget _buildRecordRow(
    AppFlowyThemeData theme,
    PaymentRecordItem record, {
    required bool isCompact,
    bool isLast = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: isCompact ? 12 : 18,
      ),
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
            flex: 2,
            child: Row(
              children: [
                if (!isCompact) ...[
                  FlowySvg(
                    FlowySvgs.pony_notes_logo_xl,
                    size: const Size(20, 20),
                  ),
                  const HSpace(8),
                ],
                Expanded(
                  child: Text(
                    record.productName.isEmpty ? '--' : record.productName,
                    style: TextStyle(
                      fontSize: isCompact ? 13 : 14,
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
              _formatAmount(record.amount),
              fontSize: isCompact ? 13 : 14,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: FlowyText(
              _formatDateTime(record.payTime),
              fontSize: isCompact ? 13 : 14,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: FlowyText(
              _formatDateTime(record.createTime),
              fontSize: isCompact ? 13 : 14,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: FlowyText(
              _formatBillingType(record.billingType),
              fontSize: isCompact ? 13 : 14,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: FlowyText(
              _formatPayMethod(record.paymentType),
              fontSize: isCompact ? 13 : 14,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatusChip(theme, record.status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreFooter(AppFlowyThemeData theme) {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            FlowyText('加载中...'),
          ],
        ),
      );
    }

    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: FlowyText(
          '没有更多了',
          textAlign: TextAlign.center,
          color: theme.textColorScheme.secondary,
        ),
      );
    }

    return SizedBox(
      height: 72,
      child: Center(
        child: PrimaryRoundedButton(
          text: '点击加载更多',
          onTap: _loadMore,
        ),
      ),
    );
  }

  Future<void> _onRefresh() async {
    await _fetchRecords(reset: true);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 60 &&
        !_isLoadingMore &&
        _hasMore &&
        notification is ScrollUpdateNotification) {
      _loadMore();
    }
    return false;
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isInitialLoading) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
    });
    await _fetchRecords(reset: false);
  }

  Widget _buildStatusChip(
    AppFlowyThemeData theme,
    String status,
  ) {
    Color backgroundColor;
    Color textColor;
    String label;
    final normalized = status.toLowerCase();

    if (normalized == 'success' ||
        normalized == 'paid' ||
        normalized == '充值成功' ||
        normalized == '支付成功') {
      backgroundColor = const Color(0x1436C761);
      textColor = const Color(0xFF36C761);
      label = '支付成功';
    } else if (normalized == 'processing' ||
        normalized == 'pending' ||
        normalized == '处理中' ||
        normalized == '待支付') {
      backgroundColor = const Color(0x14F5A524);
      textColor = const Color(0xFFF5A524);
      label = '支付中';
    } else {
      backgroundColor = const Color(0x14EB5757);
      textColor = const Color(0xFFEB5757);
      label = '支付失败';
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: FlowyText(
          label,
          fontSize: 12,
          color: textColor,
        ),
      ),
    );
  }

  Future<void> _fetchRecords({required bool reset}) async {
    final targetPage = reset ? 1 : _currentPage + 1;
    if (reset) {
      setState(() {
        _isInitialLoading = true;
        _errorMessage = null;
      });
    }

    final result = await PaymentApi.getMyPaymentList(
      pageNum: targetPage,
      pageSize: _pageSize,
    );

    if (!mounted) {
      return;
    }

    result.fold(
      (page) {
        setState(() {
          if (reset) {
            _records
              ..clear()
              ..addAll(page.list);
          } else {
            _records.addAll(page.list);
          }
          _currentPage = page.pageNum;
          _hasMore = _records.length < page.total && page.list.isNotEmpty;
          _isInitialLoading = false;
          _isLoadingMore = false;
          _errorMessage = null;
        });
      },
      (error) {
        setState(() {
          _isInitialLoading = false;
          _isLoadingMore = false;
          if (reset) {
            _records.clear();
          }
          _hasMore = false;
          _errorMessage = error.msg.isEmpty ? '加载充值记录失败，请稍后重试' : error.msg;
        });
      },
    );
  }

  String _formatPayMethod(String payMethod) {
    final normalized = payMethod.toLowerCase();
    if (normalized.contains('wechat') || normalized.contains('微信')) {
      return '微信支付';
    }
    if (normalized.contains('alipay') || normalized.contains('支付宝')) {
      return '支付宝';
    }
    if (normalized.contains('apple')) {
      return 'Apple Pay';
    }
    return payMethod.isEmpty ? '--' : payMethod;
  }

  String _formatBillingType(String billingType) {
    final normalized = billingType.toLowerCase();
    if (normalized == 'monthly' || normalized.contains('month')) {
      return '月付';
    }
    if (normalized == 'yearly' || normalized.contains('year')) {
      return '年付';
    }
    return billingType.isEmpty ? '--' : billingType;
  }

  String _formatDateTime(String value) {
    if (value.isEmpty) {
      return '--';
    }
    var formatted = value.replaceFirst('T', ' ');
    formatted = formatted.replaceAll(
      RegExp(r'\.\d{3}(Z|[+-]\d{2}:\d{2})$'),
      '',
    );
    formatted = formatted.replaceAll(RegExp(r'(Z|[+-]\d{2}:\d{2})$'), '');
    return formatted;
  }

  String _formatAmount(double amount) {
    if (amount == amount.truncateToDouble()) {
      return '${amount.toInt()}元';
    }
    return '${amount.toStringAsFixed(2)}元';
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return FlowyText(
      label,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: theme.textColorScheme.secondary,
    );
  }
}
