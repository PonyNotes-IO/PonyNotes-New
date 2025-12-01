import 'package:appflowy/generated/flowy_svgs.g.dart';
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
  static const int _pageSize = 20;
  late final List<_RechargeRecord> _records = _generateMockRecords();
  int _visibleCount = _pageSize;
  bool _isLoadingMore = false;

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
                    widget.changeSelectedPage(SettingsPage.accountManagement),
              ),
              Expanded(
                child: Center(
                  child: FlowyText(
                    '充值记录',
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
              child: Column(
                children: [
                  _buildTableHeader(theme),
                  const Divider(height: 1, thickness: 1),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _handleScrollNotification,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _visibleCount + 1,
                          itemBuilder: (context, index) {
                            if (index == _visibleCount) {
                              return _buildLoadMoreFooter(theme);
                            }
                            final record = _records[index];
                            return _buildRecordRow(
                              theme,
                              record,
                              isLast: index == _visibleCount - 1,
                            );
                          },
                        ),
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
          Expanded(flex: 3, child: _HeaderCell('产品名称')),
          Expanded(child: _HeaderCell('价格')),
          Expanded(flex: 2, child: _HeaderCell('开通时间')),
          Expanded(flex: 2, child: _HeaderCell('到期时间')),
          Expanded(flex: 2, child: _HeaderCell('支付方式')),
        ],
      ),
    );
  }

  Widget _buildRecordRow(
    AppFlowyThemeData theme,
    _RechargeRecord record, {
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
                    record.productName,
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
              record.priceLabel,
              fontSize: 14,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    record.payMethod,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textColorScheme.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
                const HSpace(8),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
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

    if (_visibleCount >= _records.length) {
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
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) {
      return;
    }
    setState(() {
      _visibleCount = _pageSize.clamp(0, _records.length);
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 60 &&
        !_isLoadingMore &&
        _visibleCount < _records.length &&
        notification is ScrollUpdateNotification) {
      _loadMore();
    }
    return false;
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _visibleCount >= _records.length) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
    });

    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) {
      return;
    }

    setState(() {
      _visibleCount =
          (_visibleCount + _pageSize).clamp(0, _records.length);
      _isLoadingMore = false;
    });
  }

  Widget _buildStatusChip(
    AppFlowyThemeData theme,
    _RechargeStatus status,
  ) {
    Color backgroundColor;
    Color textColor;
    String label;

    switch (status) {
      case _RechargeStatus.success:
        backgroundColor = const Color(0x1436C761);
        textColor = const Color(0xFF36C761);
        label = '充值成功';
        break;
      case _RechargeStatus.processing:
        backgroundColor = const Color(0x14F5A524);
        textColor = const Color(0xFFF5A524);
        label = '处理中';
        break;
      case _RechargeStatus.failed:
        backgroundColor = const Color(0x14EB5757);
        textColor = const Color(0xFFEB5757);
        label = '充值失败';
        break;
    }

    return Container(
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
    );
  }
}

enum _RechargeStatus {
  success,
  processing,
  failed,
}

class _RechargeRecord {
  const _RechargeRecord({
    required this.orderId,
    required this.productName,
    required this.amount,
    required this.priceLabel,
    required this.startTime,
    required this.endTime,
    required this.payMethod,
    required this.status,
  });

  final String orderId;
  final String productName;
  final double amount;
  final String priceLabel;
  final String startTime;
  final String endTime;
  final String payMethod;
  final _RechargeStatus status;
}

List<_RechargeRecord> _generateMockRecords() {
  const products = [
    '小马笔记学生版1个月',
    '小马笔记标准版12个月/年',
    '小马笔记存储空间扩容方案',
  ];
  const prices = ['3元', '30元', '5元'];
  const amounts = [3.0, 30.0, 5.0];
  const payMethods = ['微信扫码支付', '支付宝扫码支付', '银行卡'];

  return List.generate(40, (index) {
    final productIndex = index % products.length;
    final date = DateTime(2025, 9, 12).subtract(Duration(days: index * 2));
    final endDate = date.add(const Duration(days: 30));
    final status = _RechargeStatus.values[index % _RechargeStatus.values.length];
    return _RechargeRecord(
      orderId: '2025${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-$index',
      productName: products[productIndex],
      amount: amounts[productIndex],
      priceLabel: prices[productIndex],
      startTime:
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} 12:43:43',
      endTime:
          '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}',
      payMethod: payMethods[index % payMethods.length],
      status: status,
    );
  });
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


