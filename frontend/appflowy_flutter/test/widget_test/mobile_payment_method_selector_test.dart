import 'package:appflowy/mobile/presentation/home/widgets/mobile_upgrade_plan_page.dart';
import 'package:appflowy/workspace/application/payment/payment_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('payment method switches both ways and stays fixed while paying',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var selected = PaymentMethod.alipay;
    var paying = false;
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: MobilePaymentMethodSelector(
                  value: selected,
                  onChanged: paying
                      ? null
                      : (method) => setState(() => selected = method),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('微信支付'));
    await tester.pumpAndSettle();
    expect(selected, PaymentMethod.wechatPay);

    await tester.tap(find.text('支付宝支付'));
    await tester.pumpAndSettle();
    expect(selected, PaymentMethod.alipay);

    update(() => paying = true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('微信支付'));
    await tester.pumpAndSettle();
    expect(selected, PaymentMethod.alipay);
    expect(tester.takeException(), isNull);
  });
}
