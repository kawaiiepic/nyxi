import 'package:flutter_test/flutter_test.dart';
import 'package:nyxi/fluz_gateway.dart';

void main() {
  test('Fluz cards expose only masked data', () {
    final card = FluzCard.fromJson({
      'id': 'issued-card',
      'name': 'Subscriptions',
      'lastFour': '1234',
      'status': 'ACTIVE',
      'media': 'VIRTUAL',
      'offerId': 'some-offer',
      'expirationDate': '',
    });
    expect(card.name, 'Subscriptions');
    expect(card.maskedNumber, '•••• 1234');
    expect(card.isVirtual, isTrue);
    expect(card.offerId, 'some-offer');
  });

  test('Fluz purchases retain ledger signed amounts', () {
    final transaction = FluzTransaction.fromJson({
      'id': 'purchase-id',
      'merchantName': 'Coffee',
      'transactionDate': '2026-11-20T12:00:00Z',
      'amount': -7.50,
      'transactionStatus': 'PENDING',
      'transactionType': 'PURCHASE',
      'cardId': 'issued-card',
    });
    expect(transaction.merchantName, 'Coffee');
    expect(transaction.amount, -7.5);
    expect(transaction.status, 'PENDING');
  });

  test('Unavailable spending is null, not a made-up zero', () {
    final unavailable = FluzMonthlyInsight.fromJson({
      'period': '2026-11', 'currency': 'USD',
      'available': false, 'settledCharges': null,
    });
    expect(unavailable.settledCharges, isNull);
    final actual = FluzMonthlyInsight.fromJson({
      'period': '2026-11', 'currency': 'USD', 'settledCharges': 41.75,
    });
    expect(actual.settledCharges, 41.75);
  });

  test('Fluz wallet balance is distinct from linked Chase funds', () {
    expect(FluzWalletBalance.fromJson({'walletAvailable': 77.25}).walletAvailable, 77.25);
    expect(FluzWalletBalance.fromJson({'walletAvailable': null}).walletAvailable, isNull);
  });

  test('Nyxi API only allows HTTPS and private local HTTP', () {
    expect(() => FluzGateway(baseUrl: 'http://example.com:8787'), throwsArgumentError);
    final gateway = FluzGateway(baseUrl: 'http://127.0.0.1:8787');
    gateway.close();
  });
}
