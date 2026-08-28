class DouYinResp {
  final dynamic code;
  final dynamic permission;
  final dynamic authCode;

  const DouYinResp({
    required this.code,
    required this.permission,
    required this.authCode,
  });

  factory DouYinResp.fromJson(Map<String, dynamic> json) {
    return DouYinResp(
      code: json['code'],
      permission: json['permission'],
      authCode: json['authCode'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'permission': permission,
      'authCode': authCode,
    };
  }
}
