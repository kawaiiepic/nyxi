import 'dart:async';
// Keep the Flutter SDK import for compatibility with pre-3.47 builds.
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'fluz_gateway.dart';
import 'package:url_launcher/url_launcher.dart';

class FluzController extends ChangeNotifier {
  FluzController({FluzGateway? api}) : api = api ?? FluzGateway() {
    _poller = Timer.periodic(const Duration(seconds: 60), (_) {
      if (signedIn && !loading) refresh();
    });
    _eventsPoller = Timer.periodic(const Duration(seconds: 10), (_) => _syncEvents());
  }

  late final Timer _poller;
  late final Timer _eventsPoller;
  bool _checkingEvents = false;
  final FluzGateway api;
  NyxiUser? user;
  List<FluzCard> cards = const [];
  List<FluzTransaction> transactions = const [];
  FluzMonthlyInsight? monthlyInsight;
  FluzWalletBalance? walletBalance;
  DateTime? lastSynced;
  bool loading = false;
  bool connected = false;
  String? error;
  bool _disposed = false;
  bool get signedIn => user != null && api.signedIn;
  bool get serverManagedFluz => api.connectionMode == 'api_key';
  void _emit() { if (!_disposed) notifyListeners(); }

  /// Immediately discard account access and any visible Fluz data.
  /// Used when /api/auth/me rejects a previously valid session.
  void forgetSession() {
    api.clearSession();
    user = null;
    connected = false;
    cards = const [];
    transactions = const [];
    monthlyInsight = null;
    walletBalance = null;
    lastSynced = null;
    error = null;
    _emit();
  }

  Future<void> _work(Future<void> Function() task) async {
    if (loading) return;
    loading = true; error = null; _emit();
    try {
      await task();
    } catch (failure) {
      error = failure.toString();
      cards = const [];
      transactions = const [];
      monthlyInsight = null;
      walletBalance = null;
      lastSynced = null;
      if (!api.signedIn) {
        user = null;
        connected = false;
        cards = const [];
        transactions = const [];
      }
    } finally {
      loading = false; _emit();
    }
  }

  Future<void> authenticate(String email, String password,
      {required bool register}) => _work(() async {
    user = register
        ? await api.register(email, password)
        : await api.login(email, password);
    await _loadConnection();
  });

  Future<void> _loadConnection() async {
    connected = await api.status();
    if (connected) {
      final results = await Future.wait<Object>([
        api.cards(),
        api.transactions(),
        api.monthlyInsight(),
        api.walletBalance(),
      ]);
      cards = results[0] as List<FluzCard>;
      transactions = results[1] as List<FluzTransaction>;
      monthlyInsight = results[2] as FluzMonthlyInsight;
      walletBalance = results[3] as FluzWalletBalance;
      lastSynced = DateTime.now();
    } else {
      cards = const [];
      transactions = const [];
      monthlyInsight = null;
      walletBalance = null;
      lastSynced = null;
    }
  }

  /// Fluz sends verified transaction webhooks to Nyxi; polling this local
  /// inbox makes activity visible without confusing it with bank notifications.
  Future<void> _syncEvents() async {
    if (!signedIn || !connected || loading || _checkingEvents) return;
    _checkingEvents = true;
    try {
      final incoming = await api.events();
      if (incoming.isNotEmpty) {
        final old = transactions.map((t) => t.id + ':' + t.status).join('|');
        final ids = incoming.map((t) => t.id).toSet();
        transactions = [...incoming, ...transactions.where((t) => !ids.contains(t.id))];
        if (old != transactions.map((t) => t.id + ':' + t.status).join('|')) _emit();
      }
    } catch (_) {
      // Keep last verified transaction history visible on transient Fluz errors.
    } finally { _checkingEvents = false; }
  }

  Future<void> refresh() => _work(_loadConnection);

  Future<Uri> authorizationUrl() => api.authorizationUrl();

  Future<void> disconnect() => _work(() async {
    await api.disconnectFluz();
    connected = false; cards = const []; transactions = const [];
    monthlyInsight = null; walletBalance = null; lastSynced = null;
  });

  Future<void> logout() => _work(() async {
    try { await api.logout(); }
    finally {
      user = null; connected = false; cards = const []; transactions = const [];
    }
  });

  Future<bool> createVirtualCard(String name, double limit, String offerId,
      {String fundingSource = 'FLUZ_BALANCE', String? bankAccountId}) async {
    if (loading || !signedIn || !connected) return false;
    var created = false;
    await _work(() async {
      final card = await api.createVirtualCard(name: name, spendLimit: limit,
        offerId: offerId, fundingSource: fundingSource, bankAccountId: bankAccountId);
      cards = [card, ...cards.where((other) => other.id != card.id)];
      created = true;
    });
    if (!created && error != null) {
      error = error! + ' Check Fluz before retrying an uncertain request.';
      _emit();
    }
    return created;
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.cancel();
    _eventsPoller.cancel();
    api.close();
    super.dispose();
  }
}

class FluzCardsPanel extends StatelessWidget {
  const FluzCardsPanel({super.key, required this.controller});
  final FluzController controller;

  Future<void> _signIn(BuildContext context, {required bool register}) async {
    var email = '';
    var password = '';
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: Text(register ? 'Create Nyxi account' : 'Sign in to Nyxi'),
        content: Column(children: [
          const SizedBox(height: 12),
          CupertinoTextField(
            onChanged: (value) => email = value.trim(),
            placeholder: 'Email',
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          const SizedBox(height: 10),
          CupertinoTextField(
            onChanged: (value) => password = value,
            placeholder: 'Password',
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          if (register) const Text('At least 12 characters'),
        ]),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(register ? 'Register' : 'Sign in'),
          ),
        ],
      ),
    );
    if (confirmed == true && email.isNotEmpty && password.isNotEmpty) {
      await controller.authenticate(email, password, register: register);
    }
  }

  Future<void> _connectFluz(BuildContext context) async {
    try {
      final uri = await controller.authorizationUrl();
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Unable to open the Fluz login page.');
      }
    } catch (error) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialog) => CupertinoAlertDialog(
          title: const Text('Fluz connection unavailable'),
          content: Text(error.toString()),
          actions: [CupertinoDialogAction(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('OK'))],
        ),
      );
    }
  }

  Future<void> _addToWallet(BuildContext context, FluzCard card) async {
    try {
      final platform = defaultTargetPlatform == TargetPlatform.android ? 'ANDROID' : 'IOS';
      final uri = await controller.api.provisioningUrl(card.id, platform: platform);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Unable to launch Fluz wallet provisioning.');
      }
    } catch (error) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(context: context,
        builder: (dialog) => CupertinoAlertDialog(
          title: const Text('Wallet unavailable'),
          content: Text(error.toString()),
          actions: [CupertinoDialogAction(
            onPressed: () => Navigator.of(dialog).pop(), child: const Text('OK'))]));
    }
  }

  Future<void> _createCard(BuildContext context) async {
    List<FluzOffer> offers;
    List<FluzBankAccount> banks;
    try {
      offers = await controller.api.offers();
      banks = await controller.api.bankAccounts();
    } catch (error) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(context: context,
        builder: (dialog) => CupertinoAlertDialog(
          title: const Text('Funding and card programs unavailable'),
          content: Text(error.toString()),
          actions: [CupertinoDialogAction(
            onPressed: () => Navigator.of(dialog).pop(), child: const Text('OK'))]));
      return;
    }
    if (!context.mounted) return;
    if (offers.isEmpty) {
      await showCupertinoDialog<void>(context: context,
        builder: (dialog) => CupertinoAlertDialog(
          title: const Text('No eligible card programs'),
          content: const Text('Fluz has not enabled virtual-card offers for this account.'),
          actions: [CupertinoDialogAction(
            onPressed: () => Navigator.of(dialog).pop(), child: const Text('OK'))]));
      return;
    }
    var name = '';
    var amount = '';
    var selected = 0;
    var selectedFunding = 0;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: const Text('Issue a real Fluz virtual card?'),
        content: Column(children: [
          const SizedBox(height: 10),
          const Text('Card creation may reserve or charge real money. '
              'Bank funding can trigger an ACH debit and a backup-card hold. '
              'Confirm the funding source, card program and limit.'),
          const SizedBox(height: 10),
          CupertinoTextField(onChanged: (v) => name = v.trim(),
            maxLength: 60, placeholder: 'Card name'),
          const SizedBox(height: 10),
          CupertinoTextField(onChanged: (v) => amount = v.trim(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            placeholder: 'Spending limit (USD)'),
          const SizedBox(height: 10),
          const Text('Card program', style: TextStyle(fontSize: 11)),
          SizedBox(height: 95, child: CupertinoPicker(
            itemExtent: 34,
            onSelectedItemChanged: (index) => selected = index,
            children: [for (final offer in offers) Text(offer.programName,
              overflow: TextOverflow.ellipsis)],
          )),
          const Text('Funding source', style: TextStyle(fontSize: 11)),
          SizedBox(height: 95, child: CupertinoPicker(
            itemExtent: 34,
            onSelectedItemChanged: (index) => selectedFunding = index,
            children: [
              const Text('Fluz wallet', overflow: TextOverflow.ellipsis),
              for (final bank in banks)
                Text(bank.description, overflow: TextOverflow.ellipsis),
            ],
          )),
          const Text('To link a new bank account, use Fluz or its Plaid flow first.',
            style: TextStyle(fontSize: 10)),
        ]),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel')),
          CupertinoDialogAction(isDefaultAction: true,
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Issue real card')),
        ],
      ),
    );
    if (confirmed == true && name.length >= 2) {
      final limit = double.tryParse(amount);
      if (limit != null && limit.isFinite && limit > 0) {
        final bank = selectedFunding == 0 ? null : banks[selectedFunding - 1];
        await controller.createVirtualCard(name, limit, offers[selected].offerId,
          fundingSource: bank == null ? 'FLUZ_BALANCE' : 'BANK_ACCOUNT',
          bankAccountId: bank?.id,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => GlassContainer.card(
      width: double.infinity,
      surfaceStyle: GlassSurfaceStyle.solid,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(CupertinoIcons.creditcard_fill,
                size: 21, color: Color(0xFFB51B7C)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Fluz virtual cards',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            if (controller.signedIn)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null : controller.refresh,
                child: const Icon(CupertinoIcons.refresh, size: 20),
              ),
          ]),
          const SizedBox(height: 8),
          Text(controller.signedIn
                  ? 'Nyxi account · ' + controller.user!.email
                  : 'Sign in to Nyxi to connect your Fluz account',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9D97A1))),
          if (controller.loading) ...[
            const SizedBox(height: 15),
            const CupertinoActivityIndicator(),
          ],
          if (controller.error != null) ...[
            const SizedBox(height: 12),
            Text(controller.error!,
                style: const TextStyle(color: Color(0xFFA82562), fontSize: 12)),
          ],
          if (!controller.signedIn) ...[
            const SizedBox(height: 14),
            const Text('Create a Nyxi account. No local scripts are needed.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B606D))),
            Wrap(spacing: 14, children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null
                    : () => _signIn(context, register: false),
                child: const Text('Sign in'),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null
                    : () => _signIn(context, register: true),
                child: const Text('Create account'),
              ),
            ]),
          ] else if (!controller.connected) ...[
            const SizedBox(height: 14),
            const Text('Connect your Fluz account securely through browser consent. '
                'Nyxi never receives your Fluz password.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B606D))),
            Wrap(spacing: 14, children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null : () => _connectFluz(context),
                child: const Text('Connect Fluz'),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null : controller.logout,
                child: const Text('Sign out'),
              ),
            ]),
          ] else ...[
            const SizedBox(height: 14),
            Text(controller.serverManagedFluz
                ? 'API KEY CONNECTED · Managed by your Nyxi server'
                : 'CONNECTED · Fluz cards issued through Nyxi',
                style: const TextStyle(fontSize: 11, color: Color(0xFFB51B7C))),
            if (controller.cards.isEmpty)
              const Text('No cards issued through Nyxi yet.'),
            for (final card in controller.cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _FluzCardRow(card: card,
                  onAddToWallet: card.status == 'ACTIVE' ? () => _addToWallet(context, card) : null),
              ),
            Wrap(spacing: 12, children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null : () => _createCard(context),
                child: const Text('Create virtual card'),
              ),
              if (!controller.serverManagedFluz)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: controller.loading ? null : controller.disconnect,
                  child: const Text('Unlink Fluz'),
                ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null : controller.logout,
                child: const Text('Sign out'),
              ),
            ]),
            const Text('Card status is last known at issuance, not live-verified. Full card numbers are unavailable.',
                style: TextStyle(fontSize: 11, color: Color(0xFF9D97A1))),
          ],
        ],
      ),
    ),
  );
}

class _FluzCardRow extends StatelessWidget {
  const _FluzCardRow({required this.card, this.onAddToWallet});
  final FluzCard card;
  final VoidCallback? onAddToWallet;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3F8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.creditcard,
              color: Color(0xFFB51B7C),
              size: 25,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    card.maskedNumber + ' · ' + (card.media.isEmpty ? 'Card' : card.media),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9D97A1)),
                  ),
                ],
              ),
            ),
            if (onAddToWallet != null)
              CupertinoButton(padding: const EdgeInsets.symmetric(horizontal: 5),
                onPressed: onAddToWallet,
                child: const Text('Wallet', style: TextStyle(fontSize: 12))),
            Text(
              card.lockState.isNotEmpty ? card.lockState : card.status,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF9D97A1),
              ),
            ),
          ],
        ),
      );
}

class FluzActivityPanel extends StatelessWidget {
  const FluzActivityPanel({super.key, required this.controller});
  final FluzController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => GlassContainer.card(
          width: double.infinity,
          surfaceStyle: GlassSurfaceStyle.solid,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Fluz transactions · Live',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (controller.connected)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: controller.loading ? null : controller.refresh,
                      child: const Icon(CupertinoIcons.refresh, size: 19),
                    ),
                ],
              ),
              const SizedBox(height: 11),
              if (!controller.connected)
                const Text(
                  'Sign in and connect Fluz in the Cards tab to see real transactions.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9D97A1),
                  ),
                )
              else if (controller.transactions.isEmpty)
                const Text(
                  'No transactions returned.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9D97A1)),
                )
              else
                for (final transaction in controller.transactions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.arrow_right_arrow_left_circle,
                          size: 23,
                          color: Color(0xFFB51B7C),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                transaction.merchantName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                transaction.date + ' · ' + transaction.status,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF9D97A1),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          (transaction.amount < 0 ? '-' : '+') +
                              '\$' + transaction.amount.abs().toStringAsFixed(2),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      );
}
