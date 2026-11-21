import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Central Nyxi API client. The account session is stored in memory only.
/// Remote servers must use HTTPS; local development may use loopback HTTP.
class FluzGateway {
  FluzGateway({
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

  /// Production backend for Nyxi on all supported platforms.
  /// Tests may inject a local baseUrl through the constructor.
  static const endpoint = 'https://nyxi.blossomvale.dev';

  final Uri _base;
  final HttpClient _client;
  String? _token;

  bool get signedIn => _token != null;
  String? connectionMode;
  void clearSession() {
    _token = null;
    connectionMode = null;
  }
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
      if (_token == null) throw const FluzGatewayException('Sign in to Nyxi first.');
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
        throw const FluzGatewayException('Nyxi backend timed out.');
      },
    );
    final content = await utf8.decoder.bind(response).join().timeout(_timeout);
    Map<String, dynamic> json;
    try {
      final value = jsonDecode(content);
      json = value is Map<String, dynamic> ? value : <String, dynamic>{};
    } on FormatException {
      throw const FluzGatewayException('Unexpected response from Nyxi backend.');
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && authenticated) _token = null;
      final reason = json['error'];
      throw FluzGatewayException(
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
      throw const FluzGatewayException('Invalid authentication response.');
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
    final json = await _request('/api/fluz/status');
    connectionMode = json['mode'] is String ? json['mode'] as String : null;
    return json['connected'] == true;
  }

  /// Fluz OAuth uses the server's approved app and a browser consent flow.
  /// The Nyxi auth bearer token is never placed into the browser URL.
  Future<Uri> authorizationUrl() async {
    final result = await _request('/api/fluz/authorize');
    final value = result['url'];
    if (value is! String || !value.startsWith('https://')) {
      throw const FluzGatewayException('Fluz authorization URL is unavailable.');
    }
    return Uri.parse(value);
  }

  Future<void> disconnectFluz() async {
    await _request('/api/fluz/connect', method: 'DELETE');
  }

  Future<List<FluzBankAccount>> bankAccounts() async {
    final json = await _request('/api/fluz/bank-accounts');
    final items = json['accounts'];
    return items is List
      ? items.whereType<Map<String, dynamic>>()
          .map(FluzBankAccount.fromJson).toList()
      : <FluzBankAccount>[];
  }

  Future<List<FluzOffer>> offers() async {
    final json = await _request('/api/fluz/offers');
    final items = json['offers'];
    return items is List
        ? items.whereType<Map<String, dynamic>>().map(FluzOffer.fromJson).toList()
        : <FluzOffer>[];
  }

  Future<Uri> provisioningUrl(String cardId, {required String platform}) async {
    final result = await _request('/api/fluz/wallet-provision',
        method: 'POST', payload: {'cardId': cardId, 'platform': platform});
    final url = result['url'];
    if (url is! String || !url.startsWith('https://')) {
      throw const FluzGatewayException('Fluz Wallet provisioning is not available.');
    }
    return Uri.parse(url);
  }

  Future<List<FluzCard>> cards() async {
    final json = await _request('/api/fluz/cards');
    final raw = json['cards'];
    return raw is List
        ? raw.whereType<Map<String, dynamic>>().map(FluzCard.fromJson).toList()
        : <FluzCard>[];
  }

  Future<List<FluzTransaction>> transactions() async {
    final json = await _request('/api/fluz/transactions');
    final raw = json['transactions'];
    return raw is List
        ? raw.whereType<Map<String, dynamic>>()
            .map(FluzTransaction.fromJson).toList()
        : <FluzTransaction>[];
  }

  Future<FluzWalletBalance> walletBalance() async {
    final json = await _request('/api/fluz/balance');
    return FluzWalletBalance.fromJson(json);
  }

  Future<List<FluzTransaction>> events() async {
    final json = await _request('/api/fluz/events');
    final raw = json['events'];
    return raw is List ? raw.whereType<Map<String, dynamic>>()
        .map(FluzTransaction.fromJson).toList() : <FluzTransaction>[];
  }

  Future<FluzMonthlyInsight> monthlyInsight() async {
    final json = await _request('/api/fluz/insights');
    return FluzMonthlyInsight.fromJson(json);
  }

  Future<FluzCard> createVirtualCard({
    required String name,
    required double spendLimit,
    required String offerId,
    String period = 'MONTHLY',
    String fundingSource = 'FLUZ_BALANCE',
    String? bankAccountId,
  }) async {
    final random = Random.secure();
    // RFC 4122 v4, not merely a 36-character hexadecimal identifier.
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final uuid = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
    final json = await _request('/api/fluz/cards', method: 'POST',
      payload: {'name': name, 'spendLimit': spendLimit, 'offerId': offerId,
        'period': period, 'fundingSource': fundingSource,
        if (bankAccountId != null) 'bankAccountId': bankAccountId,
        'confirm': true},
      idempotencyKey: uuid,
    );
    final card = json['card'];
    if (card is! Map<String, dynamic>) {
      throw const FluzGatewayException('Card creation could not be confirmed.');
    }
    return FluzCard.fromJson(card);
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

class FluzGatewayException implements Exception {
  const FluzGatewayException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class FluzCard {
  const FluzCard({
    required this.id,
    required this.name,
    required this.lastFour,
    required this.status,
    required this.media,
    required this.lockState,
    required this.expirationDate,
    this.offerId = '',
  });

  factory FluzCard.fromJson(Map<String, dynamic> json) => FluzCard(
        id: json['id'] is String ? json['id'] as String : '',
        name: json['name'] is String ? json['name'] as String : 'Fluz card',
        offerId: json['offerId'] is String ? json['offerId'] as String : '',
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
  final String offerId;

  bool get isVirtual => media.toUpperCase() == 'VIRTUAL';
  String get maskedNumber => lastFour.isEmpty ? '••••' : '•••• $lastFour';
}

class FluzTransaction {
  const FluzTransaction({
    required this.id,
    required this.merchantName,
    required this.date,
    required this.amount,
    required this.status,
    required this.type,
    required this.cardId,
  });

  factory FluzTransaction.fromJson(Map<String, dynamic> json) =>
      FluzTransaction(
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

class FluzMonthlyInsight {
  const FluzMonthlyInsight({
    required this.period,
    required this.currency,
    required this.settledCharges,
  });

  factory FluzMonthlyInsight.fromJson(Map<String, dynamic> json) {
    final amount = json['settledCharges'];
    return FluzMonthlyInsight(
      period: json['period'] is String ? json['period'] as String : '',
      currency: json['currency'] is String ? json['currency'] as String : 'USD',
      settledCharges: amount is num && amount.isFinite ? amount.toDouble() : null,
    );
  }

  final String period;
  final String currency;
  /// Null means data is unavailable. Never replace null with a fake zero.
  final double? settledCharges;
}

class FluzWalletBalance {
  const FluzWalletBalance({this.walletAvailable});

  factory FluzWalletBalance.fromJson(Map<String, dynamic> json) {
    final raw = json['walletAvailable'];
    return FluzWalletBalance(
      walletAvailable: raw is num && raw.isFinite ? raw.toDouble() : null,
    );
  }

  /// Available funds inside Fluz, NOT a connected Chase checking balance.
  final double? walletAvailable;
}

class FluzOffer {
  const FluzOffer({required this.offerId, required this.programName});
  factory FluzOffer.fromJson(Map<String, dynamic> json) => FluzOffer(
    offerId: json['offerId'] is String ? json['offerId'] as String : '',
    programName: json['programName'] is String ? json['programName'] as String : 'Virtual card',
  );
  final String offerId;
  final String programName;
}

class FluzBankAccount {
  const FluzBankAccount({required this.id, required this.type,
    required this.status, required this.lastFour});
  factory FluzBankAccount.fromJson(Map<String, dynamic> json) => FluzBankAccount(
    id: json['id'] is String ? json['id'] as String : '',
    type: json['type'] is String ? json['type'] as String : '',
    status: json['status'] is String ? json['status'] as String : '',
    lastFour: json['lastFour'] is String ? json['lastFour'] as String : '',
  );

  final String id;
  final String type;
  final String status;
  final String lastFour;
  String get description => '${type.isEmpty ? 'Bank account' : type} •••• $lastFour';
}
