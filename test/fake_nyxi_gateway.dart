import 'dart:async';

import 'package:nyxi/klutch_gateway.dart';

/// In-memory network substitute for the Nyxi gate widget tests.
class FakeNyxiGateway extends KlutchGateway {
  FakeNyxiGateway() : super(baseUrl: 'http://127.0.0.1:8787');

  bool online = true;
  bool validSession = false;
  bool hangHealth = false;
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
  Future<bool> status() async => false;

  @override
  Future<List<KlutchCard>> cards() async => const <KlutchCard>[];

  @override
  Future<List<KlutchTransaction>> transactions() async =>
      const <KlutchTransaction>[];

  @override
  Future<void> logout() async => validSession = false;
}
