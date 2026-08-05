import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class BackToLoginButton extends StatelessWidget {
  const BackToLoginButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Color(0xFFF2F2F2),
          border: Border.all(
            color: const Color(0xFFF2F2F2),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          LocaleKeys.signIn_backToLogin.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
