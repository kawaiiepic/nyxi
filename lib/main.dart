import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'desktop_shell.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  runApp(LiquidGlassWidgets.wrap(
    child: const NyxiApp(),
    adaptiveQuality: true,
    theme: const GlassThemeData.ios27(),
  ));
}

/// Nyxi's prototype contains demo money only. Real financial actions require
/// a separately designed and authenticated backend integration.
class NyxiApp extends StatelessWidget {
  const NyxiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'nyxi',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: NyxiPalette.pink,
        scaffoldBackgroundColor: NyxiPalette.paper,
      ),
      home: const NyxiDashboard(),
    );
  }
}

abstract final class NyxiPalette {
  static const pink = Color(0xFFEB008E);
  static const berry = Color(0xFFB51B7C);
  static const deepBerry = Color(0xFF8C155F);
  static const paper = Color(0xFFF7F6F8);
  static const ink = Color(0xFF171219);
  static const muted = Color(0xFF9D97A1);
  static const lavender = Color(0xFFD9CAFF);
  static const mint = Color(0xFFCEFFE3);
  static const border = Color(0xFFEFEAF0);
}

String money(double value) => '\$' + value.toStringAsFixed(2);

class MoneyActivity {
  const MoneyActivity({
    required this.name,
    required this.note,
    required this.amount,
    required this.symbol,
    required this.tint,
  });

  final String name;
  final String note;
  final double amount;
  final IconData symbol;
  final Color tint;
}

class NyxiDashboard extends StatefulWidget {
  const NyxiDashboard({super.key});

  @override
  State<NyxiDashboard> createState() => _NyxiDashboardState();
}

class _NyxiDashboardState extends State<NyxiDashboard> {
  int _tab = 0;
  double _cash = 91.50;
  double _savings = 50;
  bool _cardFrozen = false;

  final List<MoneyActivity> _activities = [
    const MoneyActivity(
      name: 'Taco Bell',
      note: 'Today · Food & drink',
      amount: -14.56,
      symbol: CupertinoIcons.flame_fill,
      tint: Color(0xFF77319D),
    ),
    const MoneyActivity(
      name: 'Starbucks',
      note: 'Yesterday · Coffee',
      amount: -24.33,
      symbol: CupertinoIcons.cart_fill,
      tint: Color(0xFF027651),
    ),
    const MoneyActivity(
      name: 'Mom',
      note: 'Yesterday · Transfer',
      amount: 15,
      symbol: CupertinoIcons.heart_fill,
      tint: Color(0xFFEFA4C4),
    ),
  ];

  void _showInfo(String title, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _changeCash({required bool deposit}) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(deposit ? 'Add demo money' : 'Withdraw demo money'),
        message: const Text(
          'Preview mode · These actions only change the amounts shown in Nyxi.',
        ),
        actions: [
          for (final amount in [10.0, 25.0, 50.0, 100.0])
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop();
                if (!deposit && amount > _cash) {
                  _showInfo('Not enough demo funds',
                      'Choose a smaller amount or add demo money first.');
                  return;
                }
                setState(() {
                  _cash += deposit ? amount : -amount;
                  _activities.insert(
                    0,
                    MoneyActivity(
                      name: deposit ? 'Demo top-up' : 'Demo withdrawal',
                      note: 'Just now · Preview mode',
                      amount: deposit ? amount : -amount,
                      symbol: deposit
                          ? CupertinoIcons.plus_circle_fill
                          : CupertinoIcons.arrow_up_circle_fill,
                      tint: deposit
                          ? const Color(0xFF3C9B82)
                          : NyxiPalette.berry,
                    ),
                  );
                });
              },
              child: Text(money(amount)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _moveSavings({required bool save}) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(save ? 'Move to savings' : 'Move to cash'),
        message: const Text('Preview mode · No real transfers are made.'),
        actions: [
          for (final amount in [5.0, 10.0, 25.0])
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop();
                if (amount > (save ? _cash : _savings)) {
                  _showInfo('Not enough demo funds',
                      'Choose a smaller amount to move.');
                  return;
                }
                setState(() {
                  _cash += save ? -amount : amount;
                  _savings += save ? amount : -amount;
                  _activities.insert(
                    0,
                    MoneyActivity(
                      name: save ? 'Moved into savings' : 'Moved into cash',
                      note: 'Just now · Internal demo transfer',
                      amount: 0,
                      symbol: CupertinoIcons.arrow_right_arrow_left_circle_fill,
                      tint: NyxiPalette.berry,
                    ),
                  );
                });
              },
              child: Text(money(amount)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showActivity(MoneyActivity activity) {
    _showInfo(
      activity.name,
      (activity.amount >= 0 ? '+' : '') +
          money(activity.amount) +
          '\n' +
          activity.note +
          '\n\nThis transaction is sample data.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final desktop = screenWidth > 520;
    final isDesktopPlatform = defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS;

    // Desktop windows get a native, full-width dashboard. On phones, preserve
    // the original reference-inspired mobile experience.
    if (screenWidth >= (isDesktopPlatform ? 600 : 900)) {
      return NyxiDesktopShell(
        selectedTab: _tab,
        title: const ['Overview', 'My cards', 'Activity', 'Savings'][_tab], 
        onTabSelected: (index) => setState(() => _tab = index),
        onOpenSettings: () => _showInfo(
          'Settings',
          'Nyxi is in preview mode. Account settings will be available when a secure data provider is connected.',
        ),
        onScan: () => _showInfo(
          'Scan & pay',
          'QR payments are not connected in preview mode.',
        ),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _desktopContent(constraints.maxWidth),
        ),
      );
    }

    // GlassPage owns the sampled pastel background, while the content keeps
    // the reference's clear white surfaces and bright magenta header.
    return GlassPage(
      background: const _DreamyBackdrop(),
      enableBackgroundSampling: true,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.transparent,
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: desktop ? 24 : 0,
                  vertical: desktop ? 26 : 0,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440, maxHeight: 880),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(desktop ? 35 : 0),
                      boxShadow: desktop
                          ? const [
                              BoxShadow(
                                color: Color(0x3F68204E),
                                blurRadius: 55,
                                offset: Offset(0, 22),
                              ),
                            ]
                          : const [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(desktop ? 35 : 0),
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: ColoredBox(color: NyxiPalette.paper),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 265,
                            child: const ColoredBox(color: NyxiPalette.berry),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _topHeader(context),
                          ),
                          Positioned.fill(
                            top: 205,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: NyxiPalette.paper,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(36),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      key: ValueKey<int>(_tab),
                                      physics: const BouncingScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                          18, 21, 18, 116),
                                      child: _tabContent(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(40, 8, 40, 15),
                                child: _bottomNavigation(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }


  Widget _desktopContent(double width) {
    switch (_tab) {
      case 1:
        return _desktopCards(width);
      case 2:
        return _desktopActivity();
      case 3:
        return _desktopSavings(width);
      default:
        return _desktopHome(width);
    }
  }

  Widget _desktopIntro(String heading, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(
            color: NyxiPalette.ink,
            fontSize: 31,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.3,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          description,
          style: const TextStyle(
            color: NyxiPalette.muted,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _desktopHome(double width) {
    final wide = width >= 950;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _desktopIntro(
          'Your money, at a glance',
          'Everything in one place, with a little extra sparkle.',
        ),
        const SizedBox(height: 24),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _desktopBalancePanel()),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: _desktopCardPreview()),
            ],
          )
        else
          Column(
            children: [
              _desktopBalancePanel(),
              const SizedBox(height: 18),
              _desktopCardPreview(),
            ],
          ),
        const SizedBox(height: 18),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _desktopActivityPanel(full: false)),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: _desktopSavingsPanel()),
            ],
          )
        else
          Column(
            children: [
              _desktopActivityPanel(full: false),
              const SizedBox(height: 18),
              _desktopSavingsPanel(),
            ],
          ),
        const SizedBox(height: 22),
        const _PreviewNotice(),
      ],
    );
  }

  Widget _desktopBalancePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(27),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF30172F),
            Color(0xFF8C155F),
            Color(0xFFCF398F),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                CupertinoIcons.money_dollar_circle,
                color: Color(0xFFFFB7E3),
                size: 20,
              ),
              SizedBox(width: 9),
              Text(
                'AVAILABLE TO SPEND',
                style: TextStyle(
                  color: Color(0xFFF8DCEC),
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            money(_cash),
            style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 46,
              letterSpacing: -2.0,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Demo cash balance',
            style: TextStyle(
              color: Color(0xFFF5CDE5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 29),
          Row(
            children: [
              Expanded(
                child: _PillButton(
                  text: 'Add money',
                  onTap: () => _changeCash(deposit: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PillButton(
                  text: 'Withdraw',
                  onTap: () => _changeCash(deposit: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _desktopCardPreview() {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Your virtual card',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: NyxiPalette.ink,
                  ),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _tab = 1),
                child: const Text(
                  'Manage',
                  style: TextStyle(
                    color: NyxiPalette.berry,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tab = 1),
            child: _FullCard(frozen: _cardFrozen),
          ),
          const SizedBox(height: 10),
          Text(
            _cardFrozen ? 'Card frozen · Demo' : 'Card active · Demo',
            style: const TextStyle(
              fontSize: 11,
              color: NyxiPalette.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopActivityPanel({required bool full}) {
    final activities = full ? _activities : _activities.take(4);
    return _WhiteCard(
      child: Column(
        children: [
          _SectionHeader(
            name: full ? 'All transactions' : 'Recent activity',
            onTap: full ? null : () => setState(() => _tab = 2),
          ),
          const SizedBox(height: 13),
          for (final item in activities)
            _ActivityRow(
              activity: item,
              onTap: () => _showActivity(item),
            ),
        ],
      ),
    );
  }

  Widget _desktopSavingsPanel() {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            name: 'Rainy day fund',
            onTap: () => setState(() => _tab = 3),
          ),
          const SizedBox(height: 25),
          Text(
            money(_savings),
            style: const TextStyle(
              fontSize: 39,
              fontWeight: FontWeight.w800,
              color: NyxiPalette.ink,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'of your \\$200.00 savings goal',
            style: TextStyle(
              color: NyxiPalette.muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 19),
          LinearProgressIndicatorLike(
            value: (_savings / 200).clamp(0.0, 1.0),
          ),
          const SizedBox(height: 9),
          const Text(
            'A little future-you fund ✧',
            style: TextStyle(
              color: NyxiPalette.muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 23),
          Row(
            children: [
              Expanded(
                child: _PillButton(
                  text: 'Save money',
                  onTap: () => _moveSavings(save: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PillButton(
                  text: 'Move to cash',
                  onTap: () => _moveSavings(save: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _desktopCards(double width) {
    final wide = width >= 900;
    final card = _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nyxi virtual card',
            style: TextStyle(
              color: NyxiPalette.ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),
          _FullCard(frozen: _cardFrozen),
          const SizedBox(height: 13),
          const Text(
            'Preview card · Not connected to an issuer',
            style: TextStyle(color: NyxiPalette.muted, fontSize: 11),
          ),
        ],
      ),
    );

    final controls = _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Card controls',
            style: TextStyle(
              fontSize: 15,
              color: NyxiPalette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Freeze card',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Pause this demo card',
                      style: TextStyle(
                        fontSize: 11,
                        color: NyxiPalette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              GlassSwitch(
                activeColor: NyxiPalette.pink,
                value: _cardFrozen,
                onChanged: (value) => setState(() => _cardFrozen = value),
              ),
            ],
          ),
          const SizedBox(height: 23),
          _FeatureRow(
            icon: CupertinoIcons.slider_horizontal_3,
            label: 'Spending limits',
            onTap: () => _showInfo(
              'Spending limits',
              'Connect a supported card issuer to control real card spending.',
            ),
          ),
          const SizedBox(height: 20),
          _FeatureRow(
            icon: CupertinoIcons.add_circled,
            label: 'Create virtual card',
            onTap: () => _showInfo(
              'Create a card',
              'No real card can be issued in demo mode.',
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _desktopIntro(
          'my cards',
          'Keep your virtual cards close and their controls even closer.',
        ),
        const SizedBox(height: 24),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: card),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: controls),
            ],
          )
        else
          Column(
            children: [
              card,
              const SizedBox(height: 18),
              controls,
            ],
          ),
        const SizedBox(height: 18),
        const _PreviewNotice(),
      ],
    );
  }

  Widget _desktopActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _desktopIntro(
          'your activity',
          'Every little transaction, all in one place.',
        ),
        const SizedBox(height: 24),
        _desktopActivityPanel(full: true),
        const SizedBox(height: 18),
        const _PreviewNotice(),
      ],
    );
  }

  Widget _desktopSavings(double width) {
    final wide = width >= 950;
    final summary = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(27),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFE0F0),
            Color(0xFFE6DCFF),
            Color(0xFFD9FFEB),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '✦  rainy day fund',
            style: TextStyle(
              color: NyxiPalette.deepBerry,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 45),
          Text(
            money(_savings),
            style: const TextStyle(
              fontSize: 49,
              color: NyxiPalette.ink,
              fontWeight: FontWeight.w800,
              letterSpacing: -2,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'of your \\$200.00 goal',
            style: TextStyle(color: NyxiPalette.deepBerry, fontSize: 12),
          ),
          const SizedBox(height: 24),
          LinearProgressIndicatorLike(
            value: (_savings / 200).clamp(0.0, 1.0),
            background: const Color(0x66FFFFFF),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _desktopIntro(
          'make room to grow',
          'Your savings, at your own pace.',
        ),
        const SizedBox(height: 24),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: summary),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: _desktopSavingsPanel()),
            ],
          )
        else
          Column(
            children: [
              summary,
              const SizedBox(height: 18),
              _desktopSavingsPanel(),
            ],
          ),
        const SizedBox(height: 18),
        const _PreviewNotice(),
      ],
    );
  }

  Widget _topHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(23, 14, 23, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _tab = 0),
                  child: const Icon(CupertinoIcons.chevron_left,
                      size: 23, color: CupertinoColors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('my money',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      )),
                ),
                GestureDetector(
                  onTap: () => _showInfo(
                    'Scan & pay',
                    'A QR payment flow can be connected after a banking provider is configured. This preview does not move money.',
                  ),
                  child: const Icon(CupertinoIcons.qrcode,
                      size: 23, color: CupertinoColors.white),
                ),
              ],
            ),
            const SizedBox(height: 31),
            SizedBox(
              height: 89,
              child: Container(
                decoration: BoxDecoration(
                  color: NyxiPalette.pink,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _CardSquigglePainter()),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFAEDB),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: const Text('▰  •• 1286',
                                style: TextStyle(
                                  color: NyxiPalette.ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                          const Spacer(),
                          const Text('nyxi  ✦',
                              style: TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              )),
                        ],
                      ),
                    ),
                    const Positioned(
                      left: 16,
                      bottom: 13,
                      child: Text('your world, your money.',
                          style: TextStyle(
                            color: CupertinoColors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabContent() {
    switch (_tab) {
      case 1:
        return _cardsContent();
      case 2:
        return _activityContent();
      case 3:
        return _savingsContent();
      default:
        return _homeContent();
    }
  }

  Widget _homeContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _showInfo('Cash balance',
              'This is a demo balance. Connect a supported banking data provider to see your real account balance.'),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cash balance',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: NyxiPalette.ink)),
              SizedBox(width: 6),
              Icon(CupertinoIcons.chevron_right, size: 12),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Text(money(_cash),
            style: const TextStyle(
              fontSize: 47,
              height: 1.12,
              letterSpacing: -2.8,
              fontWeight: FontWeight.w800,
              color: NyxiPalette.ink,
            )),
        const SizedBox(height: 5),
        const Text('Available to spend · Demo',
            style: TextStyle(fontSize: 11, color: NyxiPalette.muted)),
        const SizedBox(height: 48),
        Row(
          children: [
            Expanded(
              child: _PillButton(
                text: 'Add money',
                onTap: () => _changeCash(deposit: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PillButton(
                text: 'Withdraw',
                onTap: () => _changeCash(deposit: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        _WhiteCard(
          child: Column(
            children: [
              _SectionHeader(
                name: 'Activity',
                onTap: () => setState(() => _tab = 2),
              ),
              const SizedBox(height: 13),
              for (final item in _activities.take(3))
                _ActivityRow(
                  activity: item,
                  onTap: () => _showActivity(item),
                ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        GestureDetector(
          onTap: () => setState(() => _tab = 3),
          child: _WhiteCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(name: 'Savings'),
                const SizedBox(height: 15),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(money(_savings),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: NyxiPalette.ink,
                                fontSize: 29,
                                letterSpacing: -1.3,
                              )),
                          const SizedBox(height: 3),
                          const Text('A little future-you fund ✧',
                              style: TextStyle(
                                color: NyxiPalette.muted,
                                fontSize: 11,
                              )),
                        ],
                      ),
                    ),
                    const _SavingsOrb(),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicatorLike(
                    value: (_savings / 200).clamp(0.0, 1.0),
                  ),
                ),
                const SizedBox(height: 5),
                const Text('Goal: \$200.00',
                    style:
                        TextStyle(fontSize: 10, color: NyxiPalette.muted)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text('✦  made for your money era  ✦',
              style: TextStyle(
                fontSize: 11,
                color: NyxiPalette.muted,
                letterSpacing: 0.3,
              )),
        ),
      ],
    );
  }

  Widget _cardsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageIntro(
          kicker: 'YOUR DIGITAL WALLET',
          title: 'my cards',
          subtitle: 'Manage your Nyxi demo cards.',
        ),
        const SizedBox(height: 22),
        _FullCard(frozen: _cardFrozen),
        const SizedBox(height: 16),
        _WhiteCard(
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.lock_shield,
                      size: 22, color: NyxiPalette.berry),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Freeze card',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        SizedBox(height: 4),
                        Text('Pause this demo card anytime',
                            style: TextStyle(
                                color: NyxiPalette.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  GlassSwitch(
                    activeColor: NyxiPalette.pink,
                    value: _cardFrozen,
                    onChanged: (value) =>
                        setState(() => _cardFrozen = value),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _FeatureRow(
                icon: CupertinoIcons.slider_horizontal_3,
                label: 'Spending limits',
                onTap: () => _showInfo('Spending limits',
                    'Card controls will become available once a card provider is connected.'),
              ),
              const SizedBox(height: 14),
              _FeatureRow(
                icon: CupertinoIcons.add_circled,
                label: 'Create a card',
                onTap: () => _showInfo('Create a card',
                    'This will require an approved card issuing provider. No card is created in demo mode.'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _PreviewNotice(),
      ],
    );
  }

  Widget _activityContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageIntro(
          kicker: 'THE LITTLE DETAILS',
          title: 'activity',
          subtitle: 'All your money moments in one place.',
        ),
        const SizedBox(height: 23),
        _WhiteCard(
          child: Column(
            children: [
              _SectionHeader(
                name: 'Latest transactions',
                onTap: () {},
              ),
              const SizedBox(height: 12),
              for (final item in _activities)
                _ActivityRow(
                  activity: item,
                  onTap: () => _showActivity(item),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _PreviewNotice(),
      ],
    );
  }

  Widget _savingsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageIntro(
          kicker: 'GROW AT YOUR OWN PACE',
          title: 'savings',
          subtitle: 'A soft place for your future plans.',
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFE4F3),
                Color(0xFFE6DDFF),
                Color(0xFFD6FFEF),
              ],
            ),
            borderRadius: BorderRadius.circular(29),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text('✦  rainy day fund',
                      style: TextStyle(
                        color: NyxiPalette.deepBerry,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      )),
                  Spacer(),
                  Icon(CupertinoIcons.sparkles,
                      color: NyxiPalette.berry, size: 22),
                ],
              ),
              const SizedBox(height: 38),
              Text(money(_savings),
                  style: const TextStyle(
                    fontSize: 45,
                    letterSpacing: -2.2,
                    fontWeight: FontWeight.w800,
                    color: NyxiPalette.ink,
                  )),
              const SizedBox(height: 6),
              const Text('of your \$200.00 goal',
                  style: TextStyle(
                    fontSize: 12,
                    color: NyxiPalette.deepBerry,
                  )),
              const SizedBox(height: 21),
              LinearProgressIndicatorLike(
                value: (_savings / 200).clamp(0.0, 1.0),
                background: const Color(0x66FFFFFF),
              ),
              const SizedBox(height: 14),
              const Text('Every little bit counts ♡',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: NyxiPalette.deepBerry,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: _PillButton(
                text: 'Save money',
                onTap: () => _moveSavings(save: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PillButton(
                text: 'Move to cash',
                onTap: () => _moveSavings(save: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _PreviewNotice(),
      ],
    );
  }

  Widget _bottomNavigation() {
    // A real liquid glass navigation pill with an animated selected lens.
    // The content cards stay opaque so text and financial amounts remain clear.
    return GlassTabBar.bottom(
      tabs: const [
        GlassTab(icon: Icon(CupertinoIcons.house_fill), label: 'Home'),
        GlassTab(icon: Icon(CupertinoIcons.creditcard), label: 'Cards'),
        GlassTab(icon: Icon(CupertinoIcons.chart_bar_fill), label: 'Activity'),
        GlassTab(icon: Icon(CupertinoIcons.heart_fill), label: 'Savings'),
      ],
      selectedIndex: _tab,
      onTabSelected: (index) => setState(() => _tab = index),
      horizontalPadding: 0,
      verticalPadding: 0,
      barHeight: 64,
      iconSize: 22,
      selectedIconColor: NyxiPalette.berry,
      selectedLabelColor: NyxiPalette.berry,
      unselectedIconColor: NyxiPalette.muted,
      unselectedLabelColor: NyxiPalette.muted,
      indicatorColor: const Color(0x36F078BE),
    );
  }

}

class _PageIntro extends StatelessWidget {
  const _PageIntro({
    required this.kicker,
    required this.title,
    required this.subtitle,
  });

  final String kicker;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kicker,
              style: const TextStyle(
                fontSize: 10,
                color: NyxiPalette.berry,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              )),
          const SizedBox(height: 6),
          Text(title,
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                color: NyxiPalette.ink,
                letterSpacing: -1.8,
              )),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: NyxiPalette.muted,
              )),
        ],
      );
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GlassContainer.card(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 17, 16, 15),
        surfaceStyle: GlassSurfaceStyle.solid,
        child: child,
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.name, this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: NyxiPalette.ink)),
            ),
            if (onTap != null)
              const Icon(CupertinoIcons.chevron_right,
                  size: 13, color: NyxiPalette.muted),
          ],
        ),
      );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity, required this.onTap});

  final MoneyActivity activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: activity.tint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  activity.symbol,
                  color: CupertinoColors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(activity.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: NyxiPalette.ink,
                        )),
                    const SizedBox(height: 3),
                    Text(activity.note,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: NyxiPalette.muted,
                        )),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                activity.amount > 0
                    ? '+' + money(activity.amount)
                    : activity.amount == 0
                        ? '↔'
                        : money(activity.amount),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: activity.amount > 0
                      ? NyxiPalette.deepBerry
                      : NyxiPalette.ink,
                ),
              ),
            ],
          ),
        ),
      );
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlassButton.custom(
        onTap: onTap,
        height: 46,
        shape: const LiquidRoundedSuperellipse(borderRadius: 30),
        surfaceStyle: GlassSurfaceStyle.solid,
        color: CupertinoColors.white,
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: NyxiPalette.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 20, color: NyxiPalette.berry),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const Icon(CupertinoIcons.chevron_right,
                color: NyxiPalette.muted, size: 14),
          ],
        ),
      );
}

class _FullCard extends StatelessWidget {
  const _FullCard({required this.frozen});

  final bool frozen;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1.65,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: frozen
                  ? [const Color(0xFFB7A8B8), const Color(0xFF746C77)]
                  : [
                      const Color(0xFFEB008E),
                      const Color(0xFFB51B7C),
                      const Color(0xFF743CBA),
                    ],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _CardSquigglePainter()),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('nyxi ✦',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      )),
                  const Spacer(),
                  Text(
                    frozen ? 'FROZEN · DEMO CARD' : 'VIRTUAL · DEMO CARD',
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('••••  ••••  ••••  1286',
                      style: TextStyle(
                        fontSize: 20,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: CupertinoColors.white,
                      )),
                  const SizedBox(height: 8),
                  const Text('YOUR MONEY, YOUR UNIVERSE',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.5,
                        color: CupertinoColors.white,
                      )),
                ],
              ),
            ],
          ),
        ),
      );
}

class _SavingsOrb extends StatelessWidget {
  const _SavingsOrb();

  @override
  Widget build(BuildContext context) => Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [
            Color(0xFFFFF7FF),
            Color(0xFFEADEFF),
            Color(0xFFCBB6FF),
          ]),
          border: Border.all(color: CupertinoColors.white, width: 3),
        ),
        child: const Center(
          child: Text('✦',
              style: TextStyle(
                color: NyxiPalette.berry,
                fontSize: 30,
              )),
        ),
      );
}

class LinearProgressIndicatorLike extends StatelessWidget {
  const LinearProgressIndicatorLike({
    super.key,
    required this.value,
    this.background = const Color(0xFFF3EDF3),
  });

  final double value;
  final Color background;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Container(
          width: double.infinity,
          height: 8,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(99),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  NyxiPalette.berry,
                  NyxiPalette.pink,
                  Color(0xFFFF9AD6),
                ]),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      );
}

class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBF5),
          borderRadius: BorderRadius.circular(19),
        ),
        child: const Text(
          '✧  Nyxi is in preview mode. Balances, card details and transactions are examples, not real banking data.',
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: NyxiPalette.deepBerry,
          ),
        ),
      );
}

class _CardSquigglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = const Color(0xDFFFFFFF)
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.19, size.height * 0.9)
      ..cubicTo(
          size.width * 0.28,
          size.height * 0.6,
          size.width * 0.23,
          size.height * 0.2,
          size.width * 0.41,
          size.height * 0.19)
      ..cubicTo(
          size.width * 0.62,
          size.height * 0.11,
          size.width * 0.58,
          size.height * 0.65,
          size.width * 0.7,
          size.height * 0.48)
      ..cubicTo(
          size.width * 0.79,
          size.height * 0.38,
          size.width * 0.83,
          size.height * 0.98,
          size.width * 1.05,
          size.height * 0.66);
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DreamyBackdrop extends StatelessWidget {
  const _DreamyBackdrop();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          return Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFA8F49A),
                        Color(0xFFFEE1EF),
                        Color(0xFFFFD8CB),
                        Color(0xFFE8F3AE),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -width * 0.27,
                top: -height * 0.19,
                width: width * 0.85,
                height: height * 0.56,
                child: _BlurCircle(
                  color: const Color(0xFF80EF6F),
                  blur: math.max(50.0, width * 0.14),
                ),
              ),
              Positioned(
                right: -width * 0.3,
                top: height * 0.18,
                width: width * 0.8,
                height: height * 0.5,
                child: _BlurCircle(
                  color: const Color(0xFFFFAEDA),
                  blur: math.max(60.0, width * 0.19),
                ),
              ),
              Positioned(
                left: width * 0.17,
                bottom: -height * 0.22,
                width: width * 0.7,
                height: height * 0.52,
                child: _BlurCircle(
                  color: const Color(0xFFFFC9E6),
                  blur: math.max(70.0, width * 0.2),
                ),
              ),
            ],
          );
        },
      );
}

class _BlurCircle extends StatelessWidget {
  const _BlurCircle({required this.color, required this.blur});

  final Color color;
  final double blur;

  @override
  Widget build(BuildContext context) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      );
}
