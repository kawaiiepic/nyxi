import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyxi/main.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';


void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LiquidGlassWidgets.initialize(
      warmUpMode: GlassWarmUpMode.never,
      enablePerformanceMonitor: false,
    );
  });
  testWidgets('home displays the reference-inspired balance and activity', (tester) async {
    await tester.pumpWidget(LiquidGlassWidgets.wrap(child: const NyxiApp()));
    expect(find.text('Cash balance'), findsOneWidget);
    expect(find.text('\$91.50'), findsOneWidget);
    expect(find.text('Add money'), findsOneWidget);
    expect(find.text('Taco Bell'), findsOneWidget);
  });

  testWidgets('add money changes demo balance but not a real account', (tester) async {
    await tester.pumpWidget(LiquidGlassWidgets.wrap(child: const NyxiApp()));
    await tester.tap(find.text('Add money'));
    await tester.pumpAndSettle();
    expect(find.text('Add demo money'), findsOneWidget);
    await tester.tap(find.text('\$25.00').last);
    await tester.pumpAndSettle();
    expect(find.text('\$116.50'), findsOneWidget);
    expect(find.text('Demo top-up'), findsOneWidget);
  });

  testWidgets('navigation opens the card screen', (tester) async {
    await tester.pumpWidget(LiquidGlassWidgets.wrap(child: const NyxiApp()));
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.text('my cards'), findsOneWidget);
    expect(find.text('Freeze card'), findsOneWidget);
  });
}
