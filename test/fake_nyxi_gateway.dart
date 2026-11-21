import 'dart:async';

import 'package:nyxi/klutch_gateway.dart';

/// In-memory network substitute for the Nyxi gate widget tests.
class FakeNyxiGateway extends KlutchGateway {
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
    if (!online) throw const KlutchGatewayException('Backend unreachable.');
    if (email != account.email || password.isEmpty) {
      throw const KlutchGatewayException(
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
    if (!online) throw const KlutchGatewayException('Backend unreachable.');
    if (!validSession) {
      throw const KlutchGatewayException('Unauthorized.', statusCode: 401);
    }
    return account;
  }

  @override
  Future<bool> status() async => linked;

  @override
  Future<List<KlutchCard>> cards() async => linked
      ? const [
          KlutchCard(
            id: 'card-real-test',
            name: 'Subscriptions',
            lastFour: '6532',
            status: 'ACTIVE',
            media: 'VIRTUAL',
            lockState: '',
            expirationDate: '2028-12',
          ),
        ]
      : const <KlutchCard>[];

  @override
  Future<List<KlutchTransaction>> transactions() async => linked
      ? const [
          KlutchTransaction(
            id: 'transaction-real-test',
            merchantName: 'Verified Merchant',
            date: '2026-11-20',
            amount: 13.75,
            status: 'SETTLED',
            type: 'CHARGE',
            cardId: 'card-real-test',
          ),
        ]
      : const <KlutchTransaction>[];

  @override
  Future<KlutchCreditBalance> creditBalance() async =>
      linked
          ? const KlutchCreditBalance(
              outstandingBalance: 77.25,
              creditLimit: 1200.00,
            )
          : const KlutchCreditBalance();

  @override
  Future<KlutchMonthlyInsight> monthlyInsight() async =>
      const KlutchMonthlyInsight(
        period: '2026-11',
        currency: 'USD',
        settledCharges: 41.75,
      );

  @override
  Future<void> logout() async => validSession = false;
}
