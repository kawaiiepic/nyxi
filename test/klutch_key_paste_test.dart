import 'package:flutter_test/flutter_test.dart';
import 'package:nyxi/klutch_panel.dart';

void main() {
  test('single paste field accepts colon-separated Klutch credentials', () {
    expect(parseKlutchKey('client-123:secret-value-123'), {
      'clientId': 'client-123',
      'secretKey': 'secret-value-123',
    });
  });

  test('single paste field accepts JSON with both Klutch credentials', () {
    expect(parseKlutchKey('{"clientId":"client-123","secretKey":"secret-value"}'), {
      'clientId': 'client-123',
      'secretKey': 'secret-value',
    });
  });

  test('single paste field accepts credentials on two lines', () {
    expect(parseKlutchKey('client-123\nsecret-value'), {
      'clientId': 'client-123',
      'secretKey': 'secret-value',
    });
  });

  test('a lone API secret cannot authenticate with Klutch', () {
    expect(() => parseKlutchKey('a-secret-key-only'), throwsFormatException);
  });
}
