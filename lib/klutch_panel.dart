import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'klutch_gateway.dart';

/// A single connection for the lifetime of the Nyxi dashboard.
/// Credentials are held only in memory, not shared preferences or source code.
class KlutchController extends ChangeNotifier {
  KlutchGateway? _gateway;
  List<KlutchCard> cards = const [];
  List<KlutchTransaction> transactions = const [];
  bool loading = false;
  bool connected = false;
  String? error;

  Future<void> connect(String gatewayToken) async {
    _gateway?.close();
    _gateway = KlutchGateway(accessToken: gatewayToken);
    connected = false;
    cards = const [];
    transactions = const [];
    await refresh();
  }

  Future<void> refresh() async {
    final gateway = _gateway;
    if (gateway == null || loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final loaded = await Future.wait<Object>([
        gateway.cards(),
        gateway.transactions(),
      ]);
      cards = loaded[0] as List<KlutchCard>;
      transactions = loaded[1] as List<KlutchTransaction>;
      connected = true;
    } catch (failure) {
      error = failure.toString();
      connected = false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> createVirtualCard(String name) async {
    final gateway = _gateway;
    if (gateway == null || loading || !connected) return false;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final created = await gateway.createVirtualCard(name);
      cards = [created, ...cards.where((card) => card.id != created.id)];
      return true;
    } catch (failure) {
      error = 'Card creation could not be confirmed: ' + failure.toString() +
          '. Check Klutch before retrying.';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void disconnect() {
    _gateway?.close();
    _gateway = null;
    cards = const [];
    transactions = const [];
    loading = false;
    connected = false;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _gateway?.close();
    super.dispose();
  }
}

class KlutchCardsPanel extends StatelessWidget {
  const KlutchCardsPanel({super.key, required this.controller});

  final KlutchController controller;

  Future<void> _connect(BuildContext context) async {
    final input = TextEditingController();
    try {
      final key = await showCupertinoDialog<String>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Connect Klutch'),
          content: Column(
            children: [
              const SizedBox(height: 10),
              const Text(
                'Enter your local Nyxi gateway access token. '
                'Klutch developer credentials stay on the gateway.',
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: input,
                obscureText: true,
                placeholder: 'Gateway access token',
                autocorrect: false,
                enableSuggestions: false,
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(input.text.trim()),
              child: const Text('Connect'),
            ),
          ],
        ),
      );
      if (key != null && key.isNotEmpty) await controller.connect(key);
    } finally {
      input.dispose();
    }
  }

  Future<void> _createCard(BuildContext context) async {
    final input = TextEditingController();
    try {
      final name = await showCupertinoDialog<String>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Create a real Klutch card?'),
          content: Column(
            children: [
              const SizedBox(height: 10),
              const Text(
                'This sends a real virtual-card issuance request to Klutch. '
                'It is NOT a demo action. Create cards only for your own account.',
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: input,
                placeholder: 'Card name (e.g. Subscriptions)',
                maxLength: 60,
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(input.text.trim()),
              child: const Text('Issue virtual card'),
            ),
          ],
        ),
      );
      if (name != null && name.length >= 2) {
        await controller.createVirtualCard(name);
      }
    } finally {
      input.dispose();
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
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.creditcard_fill,
                    color: Color(0xFFB51B7C),
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Klutch virtual cards',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFF171219),
                      ),
                    ),
                  ),
                  if (controller.connected)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: controller.loading ? null : controller.refresh,
                      child: const Icon(CupertinoIcons.refresh, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                controller.connected
                    ? 'LIVE · Your real Klutch account'
                    : 'Optional integration · Demo cards stay separate',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9D97A1),
                ),
              ),
              if (controller.loading) ...[
                const SizedBox(height: 16),
                const CupertinoActivityIndicator(),
              ],
              if (controller.error != null) ...[
                const SizedBox(height: 14),
                Text(
                  controller.error!,
                  style: const TextStyle(color: Color(0xFFA82562), fontSize: 12),
                ),
              ],
              if (!controller.connected) ...[
                const SizedBox(height: 18),
                const Text(
                  'Connect your locally configured Klutch gateway to view '
                  'masked card details and recent transactions.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B606D)),
                ),
                const SizedBox(height: 10),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: controller.loading ? null : () => _connect(context),
                  child: const Text('Connect Klutch'),
                ),
              ] else ...[
                const SizedBox(height: 17),
                if (controller.cards.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No Klutch cards were returned for this account.',
                      style: TextStyle(color: Color(0xFF6B606D), fontSize: 12),
                    ),
                  ),
                for (final card in controller.cards)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _KlutchCardRow(card: card),
                  ),
                Row(
                  children: [
                    Flexible(
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: controller.loading ? null : () => _createCard(context),
                        child: const Text('Create virtual card'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: controller.disconnect,
                      child: const Text(
                        'Disconnect',
                        style: TextStyle(color: Color(0xFF8B7E8D), fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                const Text(
                  'Card locking and sensitive card details are not available '
                  'in this first integration.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9D97A1)),
                ),
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
                  'Connect Klutch in the Cards tab to see real transactions here.',
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
