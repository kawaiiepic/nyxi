import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Central Nyxi API client. The account session is stored in memory only.
/// Remote servers must use HTTPS; local development may use loopback HTTP.
class KlutchGateway {
  KlutchGateway({
    String? baseUrl,
    HttpClient? client,
  }) : _base = Uri.parse(baseUrl ?? endpoint),
       _client = client ?? HttpClient() {
    if (_base.scheme != 'https' &&
        !(_base.scheme == 'http' &&
          const ['localhost', '127.0.0.1', '10.0.2.2'].contains(_base.host))) {
      throw ArgumentError('Nyxi backend requires HTTPS or local HTTP.');
    }
    _client.connectionTimeout = const Duration(seconds: 10);
  }

  static const endpoint = String.fromEnvironment(
    'NYXI_API_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );

  final Uri _base;
  final HttpClient _client;
  String? _token;

  bool get signedIn => _token != null;
  void clearSession() => _token = null;
  void close() => _client.close(force: true);

  static const _timeout = Duration(seconds: 5);

  /// A backend-specific health check. A random HTTP 200 or captive portal
  /// must not be mistaken for a responsive Nyxi API.
  Future<bool> health() async {
    try {
      final result = await _request('/health', authenticated: false)
          .timeout(_timeout);
      return result['service'] == 'nyxi-api' && result['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? payload,
    bool authenticated = true,
    String? idempotencyKey,
  }) async {
    final request = await _client.openUrl(method, _base.resolve(path))
        .timeout(_timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (authenticated) {
      if (_token == null) throw const KlutchGatewayException('Sign in to Nyxi first.');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    }
    if (idempotencyKey != null) {
      request.headers.set('Idempotency-Key', idempotencyKey);
    }
    if (payload != null) request.write(jsonEncode(payload));
    final response = await request.close().timeout(
      _timeout,
      onTimeout: () {
        request.abort();
        throw const KlutchGatewayException('Nyxi backend timed out.');
      },
    );
    final content = await utf8.decoder.bind(response).join().timeout(_timeout);
    Map<String, dynamic> json;
    try {
      final value = jsonDecode(content);
      json = value is Map<String, dynamic> ? value : <String, dynamic>{};
    } on FormatException {
      throw const KlutchGatewayException('Unexpected response from Nyxi backend.');
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && authenticated) _token = null;
      final reason = json['error'];
      throw KlutchGatewayException(
        reason is String ? reason : 'Backend error ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return json;
  }

  Future<NyxiUser> register(String email, String password) async {
    final result = await _request(
      '/api/auth/register',
      method: 'POST',
      authenticated: false,
      payload: {'email': email, 'password': password},
    );
    return _acceptSession(result);
  }

  Future<NyxiUser> login(String email, String password) async {
    final result = await _request(
      '/api/auth/login',
      method: 'POST',
      authenticated: false,
      payload: {'email': email, 'password': password},
    );
    return _acceptSession(result);
  }

  NyxiUser _acceptSession(Map<String, dynamic> json) {
    final token = json['token'];
    final user = json['user'];
    if (token is! String || token.isEmpty || user is! Map<String, dynamic>) {
      throw const KlutchGatewayException('Invalid authentication response.');
    }
    _token = token;
    return NyxiUser.fromJson(user);
  }

  Future<NyxiUser> me() async {
    final json = await _request('/api/auth/me');
    return NyxiUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      if (_token != null) await _request('/api/auth/logout', method: 'POST');
    } finally {
      _token = null;
    }
  }

  Future<bool> status() async {
    final json = await _request('/api/klutch/status');
    return json['connected'] == true;
  }

  Future<void> connectKlutch({
    required String clientId,
    required String secretKey,
    String environment = 'production',
  }) async {
    await _request(
      '/api/klutch/connect',
      method: 'POST',
      payload: {
        'clientId': clientId,
        'secretKey': secretKey,
        'environment': environment,
      },
    );
  }

  Future<void> disconnectKlutch() async {
    await _request('/api/klutch/connect', method: 'DELETE');
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
    // One random request identifier per issuance. The server tracks uncertain
    // requests so a lost response cannot silently duplicate a card.
    final random = Random.secure();
    final id = List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final json = await _request(
      '/api/klutch/cards',
      method: 'POST',
      payload: {'name': name, 'confirm': true},
      idempotencyKey: id,
    );
    final card = json['card'];
    if (card is! Map<String, dynamic>) {
      throw const KlutchGatewayException('Card creation could not be confirmed.');
    }
    return KlutchCard.fromJson(card);
  }
}

class NyxiUser {
  const NyxiUser({required this.id, required this.email});
  factory NyxiUser.fromJson(Map<String, dynamic> json) => NyxiUser(
    id: json['id'] is String ? json['id'] as String : '',
    email: json['email'] is String ? json['email'] as String : '',
  );
  final String id;
  final String email;
}

class KlutchGatewayException implements Exception {
  const KlutchGatewayException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
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
