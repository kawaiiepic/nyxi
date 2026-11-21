import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'klutch_gateway.dart';

/// Klutch requires both values, but Nyxi provides one paste field.
Map<String, String> parseKlutchKey(String pasted) {
  final value = pasted.trim();
  if (value.startsWith('{')) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        final id = decoded['clientId'];
        final secret = decoded['secretKey'];
        if (id is String && secret is String &&
            id.trim().isNotEmpty && secret.trim().isNotEmpty) {
          return {'clientId': id.trim(), 'secretKey': secret.trim()};
        }
      }
    } on FormatException {
      // No credential data is logged or displayed on failure.
    }
  }
  final lines = value.split(RegExp(r'\r?\n'));
  if (lines.length == 2 && lines.every((part) => part.trim().isNotEmpty)) {
    return {'clientId': lines[0].trim(), 'secretKey': lines[1].trim()};
  }
  final separator = value.indexOf(':');
  if (separator > 0 && !value.contains('\n')) {
    final id = value.substring(0, separator).trim();
    final secret = value.substring(separator + 1).trim();
    if (id.isNotEmpty && secret.isNotEmpty) {
      return {'clientId': id, 'secretKey': secret};
    }
  }
  throw const FormatException(
    'Klutch needs both a Client ID and Secret Key. Paste '
    'clientId:secretKey or a JSON pair into this field.',
  );
}

class KlutchController extends ChangeNotifier {
  KlutchController({KlutchGateway? api}) : api = api ?? KlutchGateway();

  final KlutchGateway api;
  NyxiUser? user;
  List<KlutchCard> cards = const [];
  List<KlutchTransaction> transactions = const [];
  KlutchMonthlyInsight? monthlyInsight;
  DateTime? lastSynced;
  bool loading = false;
  bool connected = false;
  String? error;
  bool _disposed = false;
  bool get signedIn => user != null && api.signedIn;
  void _emit() { if (!_disposed) notifyListeners(); }

  /// Immediately discard account access and any visible Klutch data.
  /// Used when /api/auth/me rejects a previously valid session.
  void forgetSession() {
    api.clearSession();
    user = null;
    connected = false;
    cards = const [];
    transactions = const [];
    monthlyInsight = null;
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
      ]);
      cards = results[0] as List<KlutchCard>;
      transactions = results[1] as List<KlutchTransaction>;
      monthlyInsight = results[2] as KlutchMonthlyInsight;
      lastSynced = DateTime.now();
    } else {
      cards = const [];
      transactions = const [];
      monthlyInsight = null;
      lastSynced = null;
    }
  }

  Future<void> refresh() => _work(_loadConnection);

  Future<void> connectPastedKey(String pasted) async {
    Map<String, String> pair;
    try {
      pair = parseKlutchKey(pasted);
    } on FormatException catch (failure) {
      error = failure.message; _emit(); return;
    }
    await _work(() async {
      await api.connectKlutch(
        clientId: pair['clientId']!,
        secretKey: pair['secretKey']!,
      );
      await _loadConnection();
    });
  }

  Future<void> disconnect() => _work(() async {
    await api.disconnectKlutch();
    connected = false; cards = const []; transactions = const [];
    monthlyInsight = null; lastSynced = null;
  });

  Future<void> logout() => _work(() async {
    try { await api.logout(); }
    finally {
      user = null; connected = false; cards = const []; transactions = const [];
    }
  });

  Future<bool> createVirtualCard(String name) async {
    if (loading || !signedIn || !connected) return false;
    var created = false;
    await _work(() async {
      final card = await api.createVirtualCard(name);
      cards = [card, ...cards.where((other) => other.id != card.id)];
      created = true;
    });
    if (!created && error != null) {
      error = error! + ' Check Klutch before retrying an uncertain request.';
      _emit();
    }
    return created;
  }

  @override
  void dispose() {
    _disposed = true;
    api.close();
    super.dispose();
  }
}

class KlutchCardsPanel extends StatelessWidget {
  const KlutchCardsPanel({super.key, required this.controller});
  final KlutchController controller;

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

  Future<void> _pasteKey(BuildContext context) async {
    var pasted = '';
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: const Text('Connect Klutch'),
        content: Column(children: [
          const SizedBox(height: 10),
          const Text('Paste your Klutch API credentials in one field. '
              'Klutch requires both Client ID and Secret Key, '
              'formatted as clientId:secretKey or JSON.'),
          const SizedBox(height: 12),
          CupertinoTextField(
            onChanged: (value) => pasted = value,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            placeholder: 'Paste Klutch API credentials',
          ),
          const SizedBox(height: 10),
          const Text('Nyxi encrypts these credentials on your server. '
              'Only connect to a server you trust.'),
        ]),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (confirmed == true && pasted.trim().isNotEmpty) {
      await controller.connectPastedKey(pasted);
    }
  }

  Future<void> _createCard(BuildContext context) async {
    var name = '';
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: const Text('Issue a real virtual card?'),
        content: Column(children: [
          const SizedBox(height: 10),
          const Text('This requests a REAL Klutch card, not a demo card.'),
          const SizedBox(height: 12),
          CupertinoTextField(
            onChanged: (value) => name = value.trim(),
            maxLength: 60,
            placeholder: 'Card name',
          ),
        ]),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Issue real card'),
          ),
        ],
      ),
    );
    if (confirmed == true && name.length >= 2) {
      await controller.createVirtualCard(name);
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
            const Expanded(child: Text('Klutch virtual cards',
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
                  : 'Sign in to Nyxi to connect your Klutch account',
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
            const Text('Paste the Klutch API key pair once, then access '
                'cards and transactions from your Nyxi account.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B606D))),
            Wrap(spacing: 14, children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null : () => _pasteKey(context),
                child: const Text('Paste Klutch key'),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null : controller.logout,
                child: const Text('Sign out'),
              ),
            ]),
          ] else ...[
            const SizedBox(height: 14),
            const Text('LIVE · Your Klutch account',
                style: TextStyle(fontSize: 11, color: Color(0xFFB51B7C))),
            if (controller.cards.isEmpty)
              const Text('No cards returned.'),
            for (final card in controller.cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _KlutchCardRow(card: card),
              ),
            Wrap(spacing: 12, children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null : () => _createCard(context),
                child: const Text('Create virtual card'),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null : controller.disconnect,
                child: const Text('Unlink Klutch'),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: controller.loading ? null : controller.logout,
                child: const Text('Sign out'),
              ),
            ]),
            const Text('Card freeze and sensitive card details are unavailable.',
                style: TextStyle(fontSize: 11, color: Color(0xFF9D97A1))),
          ],
        ],
      ),
    ),
  );
}

class _KlutchCardRow extends StatelessWidget {
  const _KlutchCardRow({required this.card});
  final KlutchCard card;

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

class KlutchActivityPanel extends StatelessWidget {
  const KlutchActivityPanel({super.key, required this.controller});
  final KlutchController controller;

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
                      'Klutch transactions · Live',
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
                  'Sign in and connect Klutch in the Cards tab to see real transactions.',
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
                          (transaction.type == 'CHARGE' ? '-' : '+') +
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
