import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'desktop_shell.dart';
import 'fluz_gateway.dart';
import 'fluz_panel.dart';
import 'nyxi_auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  runApp(LiquidGlassWidgets.wrap(
    child: const NyxiApp(),
    adaptiveQuality: true,
    theme: const GlassThemeData.ios27(),
  ));
}

class NyxiApp extends StatelessWidget {
  const NyxiApp({super.key, this.controller});
  final FluzController? controller;

  @override
  Widget build(BuildContext context) => CupertinoApp(
        title: 'nyxi',
        debugShowCheckedModeBanner: false,
        theme: const CupertinoThemeData(
          brightness: Brightness.light,
          primaryColor: NyxiPalette.pink,
          scaffoldBackgroundColor: NyxiPalette.paper,
        ),
        home: NyxiAuthGate(
          controller: controller,
          dashboardBuilder: (account) => NyxiDashboard(controller: account),
        ),
      );
}

abstract final class NyxiPalette {
  static const pink = Color(0xFFEB008E);
  static const berry = Color(0xFFB51B7C);
  static const deepBerry = Color(0xFF8C155F);
  static const paper = Color(0xFFF8F7FB);
  static const ink = Color(0xFF211726);
  static const muted = Color(0xFF928897);
  static const border = Color(0xFFF0EBF1);
}

String money(num amount) =>
    (amount < 0 ? '-' : '') +
    String.fromCharCode(36) +
    amount.abs().toStringAsFixed(2);

class NyxiDashboard extends StatefulWidget {
  const NyxiDashboard({super.key, required this.controller});
  final FluzController controller;

  @override
  State<NyxiDashboard> createState() => _NyxiDashboardState();
}

class _NyxiDashboardState extends State<NyxiDashboard> {
  int _tab = 0;
  FluzController get account => widget.controller;
  static const _tabs = ['Overview', 'Cards', 'Activity', 'Insights'];

  bool get _desktopPlatform =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: account,
        builder: (context, _) {
          final screenWidth = MediaQuery.sizeOf(context).width;
          if (screenWidth >= (_desktopPlatform ? 600 : 900)) {
            return NyxiDesktopShell(
              selectedTab: _tab,
              title: _tabs[_tab],
              statusLabel: account.connected
                  ? 'KLUTCH CONNECTED'
                  : 'NO FLUZ CONNECTION',
              onTabSelected: (index) => setState(() => _tab = index),
              onOpenSettings: _openSettings,
              onRefresh: account.loading ? () {} : account.refresh,
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _desktopContent(constraints.maxWidth),
              ),
            );
          }
          return _mobileLayout();
        },
      );

  void _openSettings() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Nyxi account'),
        message: Text(account.user?.email ?? 'Signed in'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              account.refresh();
            },
            child: const Text('Refresh financial data'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              account.logout();
            },
            child: const Text('Sign out'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _desktopContent(double width) {
    switch (_tab) {
      case 1:
        return _cardsView();
      case 2:
        return _activityView();
      case 3:
        return _insightsView();
      default:
        return _overviewView(wide: width >= 930);
    }
  }

  Widget _mobileLayout() => GlassPage(
        background: const ColoredBox(color: NyxiPalette.paper),
        enableBackgroundSampling: true,
        child: CupertinoPageScaffold(
          backgroundColor: CupertinoColors.transparent,
          child: Stack(
            children: [
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 255,
                child: ColoredBox(color: NyxiPalette.berry),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 15, 22, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('nyxi ✦',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: CupertinoColors.white,
                                    fontWeight: FontWeight.w800,
                                  )),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: account.loading ? null : account.refresh,
                              child: const Icon(CupertinoIcons.refresh,
                                  color: CupertinoColors.white, size: 23),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: _openSettings,
                              child: const Icon(CupertinoIcons.person_crop_circle,
                                  color: CupertinoColors.white, size: 24),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          height: 91,
                          padding: const EdgeInsets.all(16),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              NyxiPalette.pink,
                              Color(0xFFB51B7C),
                            ]),
                            borderRadius: BorderRadius.circular(19),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Your linked finances',
                                  style: TextStyle(
                                    color: CupertinoColors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  )),
                              const SizedBox(height: 10),
                              Text(
                                account.connected
                                    ? 'Fluz connected · live account data'
                                    : 'Connect Fluz to load your cards and activity',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFFFDDEB),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                top: 208,
                child: Container(
                  decoration: const BoxDecoration(
                    color: NyxiPalette.paper,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(34)),
                  ),
                  child: SingleChildScrollView(
                    key: ValueKey<int>(_tab),
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 23, 18, 120),
                    child: switch (_tab) {
                      1 => _cardsView(),
                      2 => _activityView(),
                      3 => _insightsView(),
                      _ => _overviewView(wide: false),
                    },
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
                    padding: const EdgeInsets.fromLTRB(25, 7, 25, 12),
                    child: GlassTabBar.bottom(
                      tabs: const [
                        GlassTab(
                          icon: Icon(CupertinoIcons.house_fill), label: 'Home',
                        ),
                        GlassTab(
                          icon: Icon(CupertinoIcons.creditcard), label: 'Cards',
                        ),
                        GlassTab(
                          icon: Icon(CupertinoIcons.chart_bar_fill),
                          label: 'Activity',
                        ),
                        GlassTab(
                          icon: Icon(CupertinoIcons.chart_bar_fill),
                          label: 'Insights',
                        ),
                      ],
                      selectedIndex: _tab,
                      onTabSelected: (index) => setState(() => _tab = index),
                      barHeight: 64,
                      iconSize: 22,
                      horizontalPadding: 0,
                      verticalPadding: 0,
                      selectedIconColor: NyxiPalette.berry,
                      selectedLabelColor: NyxiPalette.berry,
                      unselectedIconColor: NyxiPalette.muted,
                      unselectedLabelColor: NyxiPalette.muted,
                      indicatorColor: const Color(0x36F078BE),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _heading(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                fontSize: 29,
                letterSpacing: -0.9,
                fontWeight: FontWeight.w800,
                color: NyxiPalette.ink,
              )),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: NyxiPalette.muted,
              )),
        ],
      );

  Widget _panel({required Widget child}) => GlassContainer.card(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(19, 19, 19, 19),
        surfaceStyle: GlassSurfaceStyle.solid,
        child: child,
      );

  Widget _overviewView({required bool wide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'your money, in focus',
          account.connected
              ? 'Activity from your connected Fluz account'
              : 'Connect a financial provider to see your accounts',
        ),
        const SizedBox(height: 22),
        if (account.error != null) ...[
          _errorBanner(),
          const SizedBox(height: 17),
        ],
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _spendingPanel()),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: _cardPreviewPanel()),
            ],
          )
        else
          Column(
            children: [
              _spendingPanel(),
              const SizedBox(height: 15),
              _cardPreviewPanel(),
            ],
          ),
        const SizedBox(height: 18),
        _walletBalancePanel(),
        const SizedBox(height: 18),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _transactionsPanel(limit: 5)),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: _connectionPanel()),
            ],
          )
        else
          Column(
            children: [
              _transactionsPanel(limit: 5),
              const SizedBox(height: 15),
              _connectionPanel(),
            ],
          ),
      ],
    );
  }

  Widget _spendingPanel() {
    final insight = account.monthlyInsight;
    final amount = account.connected ? insight?.settledCharges : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF30172F),
            NyxiPalette.deepBerry,
            Color(0xFFCA398D),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(CupertinoIcons.chart_bar_fill,
                  size: 18, color: Color(0xFFFFC4E4)),
              SizedBox(width: 9),
              Text('SETTLED CARD SPENDING',
                  style: TextStyle(
                    color: Color(0xFFFFD7EE),
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          const SizedBox(height: 25),
          Text(
            amount == null ? 'Not available' : money(amount),
            style: TextStyle(
              color: CupertinoColors.white,
              fontSize: amount == null ? 29 : 42,
              letterSpacing: -1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            insight?.period.isNotEmpty == true
                ? 'Month to date · ${insight!.period} · USD'
                : 'Month to date · Fluz',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFFFCEE8),
            ),
          ),
          const SizedBox(height: 23),
          Text(
            account.connected
                ? amount == null
                    ? 'Fluz has not returned a verified spending total.'
                    : 'Calculated from settled Fluz virtual-card purchases.'
                : 'Connect Fluz to load your actual spending.',
            style: const TextStyle(
              color: Color(0xFFFFE0F0),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 15),
          CupertinoButton(
            color: CupertinoColors.white,
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
            onPressed: account.loading ? null : account.refresh,
            child: const Text('Refresh data',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: NyxiPalette.deepBerry,
                  fontSize: 12,
                )),
          ),
        ],
      ),
    );
  }

  Widget _walletBalancePanel() {
    final balance = account.walletBalance;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fluz wallet balance',
              style: TextStyle(
                color: NyxiPalette.ink,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              )),
          const SizedBox(height: 9),
          const Text('Verified wallet funds held with Fluz',
            style: TextStyle(fontSize: 11, color: NyxiPalette.muted)),
          const SizedBox(height: 19),
          _metricRow('Available wallet funds',
            balance?.walletAvailable == null
              ? 'Not available' : money(balance!.walletAvailable!)),
          const SizedBox(height: 11),
          const Text(
            'Fluz wallet funds are not your Chase checking balance. '
            'Nyxi does not infer checking funds or credit limits.',
            style: TextStyle(fontSize: 11, height: 1.4, color: NyxiPalette.muted),
          ),
        ],
      ),
    );
  }

  Widget _cardPreviewPanel() {
    final cards = account.cards;
    final first = cards.isEmpty ? null : cards.first;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLink('Your virtual cards', () => setState(() => _tab = 1)),
          const SizedBox(height: 17),
          if (first == null) ...[
            const Icon(CupertinoIcons.creditcard,
                color: NyxiPalette.berry, size: 37),
            const SizedBox(height: 19),
            Text(
              account.connected
                  ? 'No cards on this account'
                  : 'No account connected',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: NyxiPalette.ink,
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'Only cards created in Nyxi using Fluz appear here.',
              style: TextStyle(fontSize: 12, color: NyxiPalette.muted),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(21),
                gradient: const LinearGradient(
                  colors: [NyxiPalette.pink, NyxiPalette.deepBerry],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('nyxi ✦',
                      style: TextStyle(
                          color: CupertinoColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 19)),
                  const SizedBox(height: 29),
                  Text(first.maskedNumber,
                      style: const TextStyle(
                          color: CupertinoColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 21,
                          letterSpacing: 1.4)),
                  const SizedBox(height: 9),
                  Text(first.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFDCEC),
                        fontSize: 12,
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${cards.length} card${cards.length == 1 ? '' : 's'} · ${first.status}',
              style: const TextStyle(
                color: NyxiPalette.muted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _transactionsPanel({int? limit}) {
    final rows = limit == null
        ? account.transactions
        : account.transactions.take(limit).toList(growable: false);
    return _panel(
      child: Column(
        children: [
          _sectionLink('Recent transactions', () => setState(() => _tab = 2)),
          const SizedBox(height: 12),
          if (!account.connected)
            _emptyText('Connect Fluz to load transaction history.')
          else if (rows.isEmpty)
            _emptyText('No transactions returned by Fluz.')
          else
            for (final transaction in rows)
              _transactionRow(transaction),
        ],
      ),
    );
  }

  Widget _transactionRow(FluzTransaction transaction) {
    final type = transaction.type.toLowerCase();
    final isCharge = type.contains('purchase') || type.contains('charge');
    final isRefund = type.contains('refund') || type.contains('reversal');
    final signedAmount = isCharge
        ? -transaction.amount.abs()
        : isRefund
            ? transaction.amount.abs()
            : transaction.amount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFFFE4F2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCharge ? CupertinoIcons.cart_fill
                  : CupertinoIcons.arrow_down_circle,
              size: 19,
              color: NyxiPalette.berry,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(transaction.merchantName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: NyxiPalette.ink,
                        fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  '${transaction.date} · ${transaction.status}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: NyxiPalette.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(money(signedAmount),
              style: TextStyle(
                color: signedAmount > 0
                    ? const Color(0xFF1A886B)
                    : NyxiPalette.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }

  Widget _connectionPanel() => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Account connection',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: NyxiPalette.ink)),
            const SizedBox(height: 17),
            Row(
              children: [
                Icon(account.connected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.exclamationmark_circle,
                    color: account.connected
                        ? const Color(0xFF1B997C)
                        : NyxiPalette.berry),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    account.connected ? 'Fluz connected' : 'Fluz not connected',
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              account.connected
                  ? 'Data belongs to your signed-in Nyxi account.'
                  : 'Connect your Fluz account through secure browser consent to access activity.',
              style: const TextStyle(
                color: NyxiPalette.muted, fontSize: 11, height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            if (account.lastSynced != null)
              Text('Last refreshed: ${account.lastSynced!.toLocal()}',
                  style: const TextStyle(
                    color: NyxiPalette.muted, fontSize: 10,
                  )),
            const SizedBox(height: 12),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _tab = 1),
              child: Text(account.connected
                  ? 'Manage Fluz cards'
                  : 'Connect Fluz'),
            ),
          ],
        ),
      );

  Widget _cardsView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('my cards', 'Only Fluz cards issued via Nyxi are listed.'),
          const SizedBox(height: 21),
          FluzCardsPanel(controller: account),
        ],
      );

  Widget _activityView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('activity', 'Transactions retrieved from Fluz.'),
          const SizedBox(height: 21),
          if (account.error != null) ...[
            _errorBanner(),
            const SizedBox(height: 14),
          ],
          _transactionsPanel(),
          const SizedBox(height: 13),
          _panel(
            child: const Text(
              'Showing up to 30 recent Fluz transactions. '
              'This list is not a complete account statement.',
              style: TextStyle(fontSize: 12, color: NyxiPalette.muted),
            ),
          ),
        ],
      );

  Widget _insightsView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('insights', 'Actual card activity, never estimated balances.'),
          const SizedBox(height: 22),
          _spendingPanel(),
          const SizedBox(height: 16),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Connected financial accounts',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: NyxiPalette.ink,
                    )),
                const SizedBox(height: 20),
                _metricRow(
                  'Fluz wallet funds',
                  account.walletBalance?.walletAvailable == null
                      ? 'Not available'
                      : money(account.walletBalance!.walletAvailable!),
                ),
                const SizedBox(height: 14),
                _metricRow('Fluz cards', account.connected
                    ? account.cards.length.toString() : 'Not connected'),
                const SizedBox(height: 14),
                _metricRow('Transactions loaded', account.connected
                    ? account.transactions.length.toString() : 'Not connected'),
                const SizedBox(height: 14),
                _metricRow('Bank cash balance', 'Not available'),
                const SizedBox(height: 14),
                _metricRow('Savings account balance', 'Not connected'),
                const SizedBox(height: 16),
                const Text(
                  'Fluz wallet funds and virtual cards do not reveal your Chase '
                  'checking or savings balance. Nyxi does not invent balances.',
                  style: TextStyle(
                    fontSize: 11, height: 1.5, color: NyxiPalette.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _sectionLink(String title, VoidCallback onTap) => Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: NyxiPalette.ink,
                )),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onTap,
            child: const Icon(CupertinoIcons.chevron_right, size: 16),
          ),
        ],
      );

  Widget _metricRow(String label, String value) => Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(
              color: NyxiPalette.muted, fontSize: 12,
            )),
          ),
          Text(value, style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: NyxiPalette.ink,
          )),
        ],
      );

  Widget _emptyText(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(message,
            style: const TextStyle(
              color: NyxiPalette.muted,
              fontSize: 12,
            )),
      );

  Widget _errorBanner() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE9F3),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            const Icon(CupertinoIcons.exclamationmark_circle,
                color: NyxiPalette.deepBerry),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Unable to refresh account data: ${account.error}',
                style: const TextStyle(
                  color: NyxiPalette.deepBerry, fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
}
