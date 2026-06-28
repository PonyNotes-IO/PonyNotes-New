import 'package:appflowy/workspace/presentation/home/stable_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HomeStackStableVisibility keeps child state while hidden',
      (tester) async {
    var initCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStackStableVisibility(
          visible: true,
          child: _StateProbe(onInit: () => initCount++),
        ),
      ),
    );

    expect(initCount, 1);
    expect(find.byType(_StateProbe, skipOffstage: false), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStackStableVisibility(
          visible: false,
          child: _StateProbe(onInit: () => initCount++),
        ),
      ),
    );

    expect(initCount, 1);
    expect(find.byType(_StateProbe, skipOffstage: false), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStackStableVisibility(
          visible: true,
          child: _StateProbe(onInit: () => initCount++),
        ),
      ),
    );

    expect(initCount, 1);
    expect(find.byType(_StateProbe, skipOffstage: false), findsOneWidget);
  });
}

class _StateProbe extends StatefulWidget {
  const _StateProbe({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 8, height: 8);
  }
}
