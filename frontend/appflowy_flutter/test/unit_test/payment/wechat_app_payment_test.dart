import 'dart:convert';

import 'package:appflowy/workspace/application/payment/payment_api.dart';
import 'package:appflowy/workspace/application/payment/wechat_app_payment.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final params = <String, dynamic>{
    'appid': WeChatAppPayment.appId,
    'partnerid': 'merchant',
    'prepayid': 'prepay',
    'package': 'Sign=WXPay',
    'noncestr': 'nonce',
    'timestamp': 1234567890,
    'sign': 'server-signature',
  };
  var sdkCode = 0;
  var nativeCalls = 0;

  setUp(() {
    sdkCode = 0;
    nativeCalls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      WeChatAppPayment.channel,
      (call) async {
        nativeCalls++;
        expect(call.method, 'pay');
        expect(call.arguments['appid'], WeChatAppPayment.appId);
        expect(call.arguments['timestamp'], '1234567890');
        return {'errCode': sdkCode};
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(WeChatAppPayment.channel, null);
  });

  test('App billing uses backend codes; legacy WeChat billing stays unchanged',
      () {
    for (final type in [PaymentType.wechatApp, PaymentType.alipayApp]) {
      for (final period in {'monthly': '0', 'yearly': '1'}.entries) {
        final request = PaymentCreateRequest(
          amount: '9.90',
          paymentType: type,
          userInfo: 'uuid',
          billingType: period.key,
        );
        expect(request.toJson()['billingType'], period.value);
      }
    }
    expect(
      const PaymentCreateRequest(
        amount: '9.90',
        paymentType: 'wechat_jsapi',
        userInfo: 'uuid',
        billingType: 'monthly',
        openid: 'web-openid',
      ).toJson(),
      containsPair('billingType', 'monthly'),
    );
  });

  test('status uses query parameter and supports string or object responses',
      () {
    final uri = PaymentApi.paymentStatusUri(
      'https://example.com',
      'order&1',
      // Always check the gateway, even in a build with a local override.
      // ignore: avoid_redundant_argument_values
      apiBaseUrl: '',
    );
    expect(uri.path, '/prod-api/api/payment/status');
    expect(uri.queryParameters, {'orderNo': 'order&1'});
    expect(PaymentApi.parsePaymentStatus('success'), 'success');
    expect(PaymentApi.parsePaymentStatus({'status': 'PAID'}), 'paid');
    expect(
      PaymentApi.parsePaymentStatus({'orderStatus': 'pending'}),
      'pending',
    );
    for (final data in [
      null,
      {},
      true,
      {'status': 'unknown'},
    ]) {
      expect(() => PaymentApi.parsePaymentStatus(data), throwsFormatException);
    }
  });

  test('payment endpoints use the gateway by default and Java directly locally',
      () {
    for (final path in [
      '/api/payment/create',
      '/api/payment/status',
      '/api/payment/myPaymentList',
      '/api/payment/apple/verify',
      '/api/payment/apple/restore',
      '/api/ponynotes/order/subscription',
    ]) {
      expect(
        PaymentApi.paymentApiUri(
          'https://example.com/',
          path,
          // ignore: avoid_redundant_argument_values
          apiBaseUrl: '',
        ),
        Uri.parse('https://example.com/prod-api$path'),
      );
      expect(
        PaymentApi.paymentApiUri(
          '',
          path,
          apiBaseUrl: ' http://192.168.1.96:9081/ ',
        ),
        Uri.parse('http://192.168.1.96:9081$path'),
      );
      expect(
        PaymentApi.paymentApiUri(
          'https://example.com',
          path,
          apiBaseUrl: 'https://proxy.example.com/prod-api/',
        ),
        Uri.parse('https://proxy.example.com/prod-api$path'),
      );
    }
    expect(
      PaymentApi.paymentStatusUri(
        '',
        'order&1',
        apiBaseUrl: 'http://192.168.1.96:9081',
      ).queryParameters,
      {'orderNo': 'order&1'},
    );
  });

  test('payment routing reads the compile-time override', () {
    const configured = String.fromEnvironment('PAYMENT_API_BASE_URL');
    final expected = configured.isEmpty
        ? 'https://example.com/prod-api/api/payment/create'
        : '$configured/api/payment/create';
    expect(
      PaymentApi.paymentApiUri('https://example.com', '/api/payment/create'),
      Uri.parse(expected),
    );
  });

  test('rejects invalid payment server addresses', () {
    for (final address in [
      'localhost:9081',
      'file:///api',
      'http://user:secret@localhost:9081',
      'http://localhost:9081?redirect=remote',
      'http://localhost:9081#fragment',
    ]) {
      expect(
        () => PaymentApi.paymentApiUri(
          'https://example.com',
          '/api/payment/create',
          apiBaseUrl: address,
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects web/QR payloads and another AppID before invoking native SDK',
      () async {
    for (final invalid in [
      'https://example.com/pay',
      jsonEncode({'code_url': 'weixin://qr'}),
      jsonEncode({...params, 'appid': 'web-app-id'}),
      jsonEncode({...params}..remove('sign')),
    ]) {
      final result = await WeChatAppPayment.pay(
        payInfo: invalid,
        orderNo: 'order',
        queryStatus: (_) async => throw StateError('must not query'),
      );
      expect(result.success, isFalse);
    }
    expect(nativeCalls, 0);
  });

  test(
      'SDK success alone never grants success; confirmation retries are bounded',
      () async {
    var queries = 0;
    final result = await WeChatAppPayment.pay(
      payInfo: jsonEncode(params),
      orderNo: 'order',
      pollInterval: Duration.zero,
      queryStatus: (_) async {
        queries++;
        return 'pending';
      },
    );
    expect(result.success, isFalse);
    expect(result.message, contains('勿重复付款'));
    expect(queries, 10);
  });

  test('backend confirmation succeeds after notification delay', () async {
    var queries = 0;
    final result = await WeChatAppPayment.pay(
      payInfo: jsonEncode(params),
      orderNo: 'order',
      pollInterval: Duration.zero,
      queryStatus: (order) async {
        expect(order, 'order');
        return ++queries == 2 ? 'success' : 'pending';
      },
    );
    expect(result.success, isTrue);
    expect(queries, 2);
  });

  test(
      'cancel and failure do not grant success; missed SDK callback can recover',
      () async {
    for (final code in [-2, -1, -3]) {
      sdkCode = code;
      final result = await WeChatAppPayment.pay(
        payInfo: jsonEncode(params),
        orderNo: 'order',
        pollInterval: Duration.zero,
        queryStatus: (_) async => code == -3 ? 'success' : 'pending',
      );
      expect(result.success, code == -3);
      if (code == -2) expect(result.message, '已取消支付');
    }
  });
}
