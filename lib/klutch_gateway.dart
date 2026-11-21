import 'dart:convert';
import 'dart:io';

/// Klutch's developer credentials belong on the local gateway, never in a
/// Flutter binary. Only the gateway access token is held in memory.
class KlutchGateway {
  KlutchGateway({
    required this.accessToken,
    String? baseUrl,
    HttpClient? client,
  })  : _base = Uri.parse(baseUrl ?? endpoint),
        _client = client ?? HttpClient() {
    if (_base.scheme != 'https' &&
        !(_base.scheme == 'http' &&
          const ['localhost', '127.0.0.1', '10.0.2.2'].contains(_base.host))) {
      throw ArgumentError('Klutch gateway must use HTTPS or local HTTP.');
    }
    _client.connectionTimeout = const Duration(seconds: 10);
  }

  static const endpoint = String.fromEnvironment(
    'NYXI_KLUTCH_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );

  final String accessToken;
  final Uri _base;
  final HttpClient _client;

  void close() => _client.close(force: true);

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? payload,
  }) async {
    final url = _base.resolve(path);
    final request = await _client.openUrl(method, url);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (payload != null) {
      request.write(jsonEncode(payload));
    }
    final response = await request.close();
    final content = await utf8.decoder.bind(response).join();
    Map<String, dynamic> json;
    try {
      final value = jsonDecode(content);
      json = value is Map<String, dynamic> ? value : <String, dynamic>{};
    } on FormatException {
      throw KlutchGatewayException('Unexpected response from Klutch gateway.');
    }
    if (response.statusCode >= 400) {
      final reason = json['error'];
      throw KlutchGatewayException(
        reason is String ? reason : 'Gateway error ${response.statusCode}',
      );
    }
    return json;
  }

  Future<List<KlutchCard>> cards() async {
    final json = await _request('/api/klutch/cards');
    final raw = json['cards'];
    return raw is List
        ? raw.whereType<Map<String, dynamic>>().map(KlutchCard.fromJson).toList()
        : <KlutchCard>[];
  }

  Future<List<KlutchTransaction>> transactions() async {
    final json = await _request('/api/klutch/transactions');
    final raw = json['transactions'];
    return raw is List
        ? raw.whereType<Map<String, dynamic>>()
            .map(KlutchTransaction.fromJson).toList()
        : <KlutchTransaction>[];
  }

  Future<KlutchCard> createVirtualCard(String name) async {
    final json = await _request(
      '/api/klutch/cards',
      method: 'POST',
      payload: {'name': name},
    );
    final card = json['card'];
    if (card is! Map<String, dynamic>) {
      throw KlutchGatewayException('The provider did not return a new card.');
    }
    return KlutchCard.fromJson(card);
  }
}

class KlutchGatewayException implements Exception {
  const KlutchGatewayException(this.message);
  final String message;

  @override
  String toString() => message;
}

class KlutchCard {
  const KlutchCard({
    required this.id,
    required this.name,
    required this.lastFour,
    required this.status,
    required this.media,
    required this.lockState,
    required this.expirationDate,
  });

  factory KlutchCard.fromJson(Map<String, dynamic> json) => KlutchCard(
        id: json['id'] is String ? json['id'] as String : '',
        name: json['name'] is String ? json['name'] as String : 'Klutch card',
        lastFour: json['lastFour'] is String ? json['lastFour'] as String : '',
        status: json['status'] is String ? json['status'] as String : '',
        media: json['media'] is String ? json['media'] as String : '',
        lockState: json['lockState'] is String ? json['lockState'] as String : '',
        expirationDate: json['expirationDate'] is String
            ? json['expirationDate'] as String
            : '',
      );

  final String id;
  final String name;
  final String lastFour;
  final String status;
  final String media;
  final String lockState;
  final String expirationDate;

  bool get isVirtual => media.toUpperCase() == 'VIRTUAL';
  String get maskedNumber => lastFour.isEmpty ? '••••' : '•••• $lastFour';
}

class KlutchTransaction {
  const KlutchTransaction({
    required this.id,
    required this.merchantName,
    required this.date,
    required this.amount,
    required this.status,
    required this.type,
    required this.cardId,
  });

  factory KlutchTransaction.fromJson(Map<String, dynamic> json) =>
      KlutchTransaction(
        id: json['id'] is String ? json['id'] as String : '',
        merchantName: json['merchantName'] is String
            ? json['merchantName'] as String
            : 'Transaction',
        date: json['transactionDate'] is String
            ? json['transactionDate'] as String
            : '',
        amount: json['amount'] is num ? (json['amount'] as num).toDouble() : 0.0,
        status: json['transactionStatus'] is String
            ? json['transactionStatus'] as String
            : '',
        type: json['transactionType'] is String
            ? json['transactionType'] as String
            : '',
        cardId: json['cardId'] is String ? json['cardId'] as String : '',
      );

  final String id;
  final String merchantName;
  final String date;
  final double amount;
  final String status;
  final String type;
  final String cardId;
}
