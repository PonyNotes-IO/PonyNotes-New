// 快速开始按钮组件
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class QuickStartButton extends StatelessWidget {
  const QuickStartButton({required this.onTap, this.checkTermsAgreement});

  final VoidCallback onTap;
  final bool Function()? checkTermsAgreement;

  // 检查用户是否同意了协议
  bool _checkTermsAgreement(BuildContext context) {
    if (checkTermsAgreement != null) {
      return checkTermsAgreement!();
    }

    // 默认返回true，因为现在都通过回调传递状态
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final materialTheme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        // 检查协议同意
        if (_checkTermsAgreement(context)) {
          onTap();
        }
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.surfaceColorScheme.layer01,
          border: Border.all(color: theme.borderColorScheme.primary),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          "快速开始",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.textColorScheme.primary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}