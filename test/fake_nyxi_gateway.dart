import 'dart:async';

import 'package:nyxi/fluz_gateway.dart';

/// In-memory network substitute for the Nyxi gate widget tests.
class FakeNyxiGateway extends FluzGateway {
  FakeNyxiGateway() : super(baseUrl: 'http://127.0.0.1:8787');

  bool online = true;
  bool validSession = false;
  bool hangHealth = false;
  bool linked = false;
  final NyxiUser account = const NyxiUser(
    id: 'test-user-id',
    email: 'test@example.com',
  );

  @override
  bool get signedIn => validSession;

  @override
  void clearSession() => validSession = false;

  @override
  Future<bool> health() {
    if (hangHealth) return Completer<bool>().future;
    return Future<bool>.value(online);
  }

  @override
  Future<NyxiUser> login(String email, String password) async {
    if (!online) throw const FluzGatewayException('Backend unreachable.');
    if (email != account.email || password.isEmpty) {
      throw const FluzGatewayException(
        'Invalid email or password.',
        statusCode: 401,
      );
    }
    validSession = true;
    return account;
  }

  @override
  Future<NyxiUser> register(String email, String password) async =>
      login(email, password);

  @override
  Future<NyxiUser> me() async {
    if (!online) throw const FluzGatewayException('Backend unreachable.');
    if (!validSession) {
      throw const FluzGatewayException('Unauthorized.', statusCode: 401);
    }
    return account;
  }

  @override
  Future<bool> status() async => linked;

  @override
  Future<List<FluzCard>> cards() async => linked
      ? const [
          FluzCard(
            id: 'card-real-test',
            name: 'Subscriptions',
            lastFour: '6532',
            status: 'ACTIVE',
            media: 'VIRTUAL',
            lockState: '',
            expirationDate: '2028-12',
          ),
        ]
      : const <FluzCard>[];

  @override
  Future<List<FluzTransaction>> transactions() async => linked
      ? const [
          FluzTransaction(
            id: 'transaction-real-test',
            merchantName: 'Verified Merchant',
            date: '2026-11-20',
            amount: -13.75,
            status: 'SETTLED',
            type: 'Virtual Card Purchase',
            cardId: 'card-real-test',
          ),
        ]
      : const <FluzTransaction>[];

  @override
  Future<FluzWalletBalance> walletBalance() async =>
      linked ? const FluzWalletBalance(walletAvailable: 77.25)
          : const FluzWalletBalance();

  @override
  Future<FluzMonthlyInsight> monthlyInsight() async =>
      const FluzMonthlyInsight(
        period: '2026-11',
        currency: 'USD',
        settledCharges: 41.75,
      );

  @override
  Future<List<FluzTransaction>> events() async => const [];

  @override
  Future<void> logout() async => validSession = false;
}
