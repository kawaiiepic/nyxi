import 'package:flutter_test/flutter_test.dart';
import 'package:nyxi/klutch_gateway.dart';

void main() {
  test('Klutch cards are masked metadata only', () {
    final card = KlutchCard.fromJson({
      'id': 'card-id',
      'name': 'Subscriptions',
      'lastFour': '1234',
      'status': 'ACTIVE',
      'media': 'VIRTUAL',
      'lockState': 'UNLOCKED',
      'expirationDate': '2028-12',
    });

    expect(card.name, 'Subscriptions');
    expect(card.maskedNumber, '•••• 1234');
    expect(card.isVirtual, isTrue);
  });

  test('Klutch transaction amount is parsed without changing demo balances', () {
    final transaction = KlutchTransaction.fromJson({
      'id': 'transaction-id',
      'merchantName': 'Coffee',
      'transactionDate': '2026-11-20T12:00:00Z',
      'amount': 7.5,
      'transactionStatus': 'SETTLED',
      'transactionType': 'CHARGE',
      'cardId': 'card-id',
    });
    expect(transaction.merchantName, 'Coffee');
    expect(transaction.amount, 7.5);
    expect(transaction.type, 'CHARGE');
  });

  test('gateway only allows HTTPS and private local HTTP', () {
    expect(
      () => KlutchGateway(
        accessToken: 'test-only',
        baseUrl: 'http://example.com:8787',
      ),
      throwsArgumentError,
    );
    final gateway = KlutchGateway(
      accessToken: 'test-only',
      baseUrl: 'http://127.0.0.1:8787',
    );
    gateway.close();
  });
}
