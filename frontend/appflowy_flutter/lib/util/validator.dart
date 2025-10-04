class Validator {
  // 邮箱验证
  static bool isValidEmail(String email) {
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }

  // 手机号验证（支持多种格式）
  static bool isValidPhone(String phone) {
    final cleanPhone = cleanPhoneNumber(phone);
    
    // 中国大陆手机号：1开头，11位数字
    final chinaMobileRegex = RegExp(r'^1[3-9]\d{9}$');
    if (chinaMobileRegex.hasMatch(cleanPhone)) {
      return true;
    }
    
    // 国际手机号：+ 开头，8-15位数字
    if (phone.startsWith('+')) {
      final internationalRegex = RegExp(r'^\+\d{8,15}$');
      return internationalRegex.hasMatch(phone);
    }
    
    return false;
  }

  // 清理手机号（去除空格、横线等）
  static String cleanPhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'[\s\-()]'), '');
  }

  // 验证验证码格式（6位数字）
  static bool isValidVerificationCode(String code) {
    final codeRegex = RegExp(r'^\d{6}$');
    return codeRegex.hasMatch(code);
  }
}

