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
  bool linked = false,
  Size? windowSize,
}) async {
  if (windowSize != null) {
    tester.view.physicalSize = windowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final api = FakeNyxiGateway()
    ..online = online
    ..linked = linked;
  final controller = KlutchController(api: api);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(child: NyxiApp(controller: controller)),
  );
  await tester.pumpAndSettle();

  if (signIn && online) {
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

  testWidgets('dashboard requires authenticated Nyxi backend', (tester) async {
    await launchNyxi(tester, signIn: false);
    expect(find.text('Sign in to Nyxi'), findsOneWidget);
    expect(find.text('your money, in focus'), findsNothing);
  });

  testWidgets('unlinked Nyxi account does not invent balances or cards',
      (tester) async {
    await launchNyxi(tester, windowSize: const Size(390, 844));
    expect(find.text('your money, in focus'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('No account connected'), findsOneWidget);
    expect(find.text('Verified Merchant'), findsNothing);
    expect(find.textContaining('91.50'), findsNothing);
    expect(find.textContaining('50.00'), findsNothing);
    expect(find.text('Add money'), findsNothing);
    expect(find.text('Withdraw'), findsNothing);
  });

  testWidgets('linked account displays only provider-backed card and spending',
      (tester) async {
    await launchNyxi(
      tester, linked: true, windowSize: const Size(390, 844),
    );
    expect(find.textContaining('41.75'), findsOneWidget);
    expect(find.text('Verified Merchant'), findsOneWidget);
    expect(find.textContaining('6532'), findsOneWidget);
    expect(find.text('Add money'), findsNothing);
    expect(find.text('Withdraw'), findsNothing);
    expect(find.textContaining('91.50'), findsNothing);
  });

  testWidgets('desktop uses provider cards and account status',
      (tester) async {
    await launchNyxi(
      tester, linked: true, windowSize: const Size(1280, 900),
    );
    expect(find.text('your money, in focus'), findsOneWidget);
    expect(find.text('KLUTCH CONNECTED'), findsOneWidget);
    expect(find.textContaining('6532'), findsOneWidget);
    expect(find.text('DEMO MODE'), findsNothing);

    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.text('Klutch virtual cards'), findsOneWidget);
    expect(find.text('Subscriptions'), findsOneWidget);
  });

  testWidgets('desktop insights do not pretend banking or savings support',
      (tester) async {
    await launchNyxi(
      tester, linked: true, windowSize: const Size(1280, 900),
    );
    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();
    expect(find.text('Bank cash balance'), findsOneWidget);
    expect(find.text('Savings account balance'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('phone-sized windows retain mobile layout', (tester) async {
    await launchNyxi(tester, windowSize: const Size(390, 844));
    expect(find.text('nyxi ✦'), findsOneWidget);
    expect(find.text('your money, in focus'), findsOneWidget);
  });

  testWidgets('unreachable backend always displays lock screen',
      (tester) async {
    final api = await launchNyxi(tester, signIn: false, online: false);
    expect(find.text('Nyxi is locked'), findsOneWidget);
    expect(find.text('your money, in focus'), findsNothing);

    api.online = true;
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Nyxi'), findsOneWidget);
  });

  testWidgets('an outage removes the live dashboard',
      (tester) async {
    final api = await launchNyxi(tester);
    api.online = false;
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.text('Nyxi is locked'), findsOneWidget);
    expect(find.text('your money, in focus'), findsNothing);
  });

  testWidgets('revoked sessions return users to sign-in',
      (tester) async {
    final api = await launchNyxi(tester);
    api.validSession = false;
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Nyxi'), findsOneWidget);
    expect(find.text('your money, in focus'), findsNothing);
  });

  testWidgets('unresponsive server locks the app after timeout',
      (tester) async {
    final api = await launchNyxi(tester);
    api.hangHealth = true;
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Nyxi is locked'), findsOneWidget);
    expect(find.text('your money, in focus'), findsNothing);
  });
}
