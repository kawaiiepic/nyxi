import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyxi/klutch_panel.dart';
import 'package:nyxi/main.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'fake_nyxi_gateway.dart';

Future<FakeNyxiGateway> launchNyxi(
  WidgetTester tester, {
  bool signIn = true,
  bool online = true,
  Size? windowSize,
}) async {
  if (windowSize != null) {
    tester.view.physicalSize = windowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final api = FakeNyxiGateway()..online = online;
  final controller = KlutchController(api: api);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(child: NyxiApp(controller: controller)),
  );
  await tester.pumpAndSettle();

  if (signIn && online) {
    expect(find.text('Cash balance'), findsNothing);
    expect(find.text('Sign in to Nyxi'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('nyxi-email')),
      'test@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('nyxi-password')),
      'a-long-test-password',
    );
    await tester.tap(find.byKey(const ValueKey('nyxi-auth-submit')));
    await tester.pumpAndSettle();
  }
  return api;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LiquidGlassWidgets.initialize(
      warmUpMode: GlassWarmUpMode.never,
      enablePerformanceMonitor: false,
    );
  });

  testWidgets('no dashboard is mounted until account login succeeds',
      (tester) async {
    await launchNyxi(tester, signIn: false);
    expect(find.text('Sign in to Nyxi'), findsOneWidget);
    expect(find.text('Cash balance'), findsNothing);
    expect(find.text('Your money, at a glance'), findsNothing);
  });

  testWidgets('home displays balance and activity after sign-in',
      (tester) async {
    await launchNyxi(tester);
    expect(find.text('Cash balance'), findsOneWidget);
    expect(find.text('\$91.50'), findsOneWidget);
    expect(find.text('Add money'), findsOneWidget);
    expect(find.text('Taco Bell'), findsOneWidget);
  });

  testWidgets('add money changes demo balance only after sign-in',
      (tester) async {
    await launchNyxi(tester);
    await tester.tap(find.text('Add money'));
    await tester.pumpAndSettle();
    expect(find.text('Add demo money'), findsOneWidget);
    await tester.tap(find.text('\$25.00').last);
    await tester.pumpAndSettle();
    expect(find.text('\$116.50'), findsOneWidget);
  });

  testWidgets('card navigation requires verified session', (tester) async {
    await launchNyxi(tester);
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.text('my cards'), findsOneWidget);
    expect(find.text('Freeze card'), findsOneWidget);
  });

  testWidgets('wide windows use desktop dashboard only after login',
      (tester) async {
    await launchNyxi(tester, windowSize: const Size(1280, 900));
    expect(find.text('Your money, at a glance'), findsOneWidget);
    expect(find.text('DEMO MODE'), findsOneWidget);
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.text('Card controls'), findsOneWidget);
  });

  testWidgets('phone-sized windows keep mobile look after login',
      (tester) async {
    await launchNyxi(tester, windowSize: const Size(390, 844));
    expect(find.text('my money'), findsOneWidget);
    expect(find.text('Cash balance'), findsOneWidget);
    expect(find.text('Your money, at a glance'), findsNothing);
  });

  testWidgets('unreachable server displays a lock screen, not demo data',
      (tester) async {
    final api = await launchNyxi(tester, signIn: false, online: false);
    expect(find.text('Nyxi is locked'), findsOneWidget);
    expect(find.text('Cash balance'), findsNothing);

    api.online = true;
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Nyxi'), findsOneWidget);
    expect(find.text('Cash balance'), findsNothing);
  });

  testWidgets('backend outage locks out a previously signed-in user',
      (tester) async {
    final api = await launchNyxi(tester);
    expect(find.text('Cash balance'), findsOneWidget);
    api.online = false;
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.text('Nyxi is locked'), findsOneWidget);
    expect(find.text('Cash balance'), findsNothing);
  });

  testWidgets('revoked server session removes access after heartbeat',
      (tester) async {
    final api = await launchNyxi(tester);
    api.validSession = false;
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Nyxi'), findsOneWidget);
    expect(find.text('Cash balance'), findsNothing);
  });

  testWidgets('unresponsive backend eventually locks the app',
      (tester) async {
    final api = await launchNyxi(tester);
    api.hangHealth = true;
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Nyxi is locked'), findsOneWidget);
    expect(find.text('Cash balance'), findsNothing);
  });
}
