import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/config.dart';

class AuthStore {
  final _storage = const FlutterSecureStorage();
  String? _token;
  bool _loaded = false;

  Future<String?> load() async {
    if (!_loaded) {
      _token = await _storage.read(key: 'token');
      _loaded = true;
    }
    return _token;
  }

  String? get token => _token;

  Future<void> save(String token) async {
    _token = token;
    _loaded = true;
    await _storage.write(key: 'token', value: token);
  }

  Future<void> clear() async {
    _token = null;
    _loaded = true;
    await _storage.delete(key: 'token');
  }
}

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);
  final int status; // 0 = no connection
  final String code;
  final String message;
  bool get isNetwork => status == 0 || status >= 500;
  @override
  String toString() => 'ApiException($status, $code, $message)';
}

class ApiClient {
  ApiClient(this._auth, {required this.onUnauthorized}) {
    _dio = Dio(BaseOptions(baseUrl: apiBase, connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 30), validateStatus: (_) => true));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final t = _auth.token;
      if (t != null) o.headers['Authorization'] = 'Bearer $t';
      h.next(o);
    }));
  }

  final AuthStore _auth;
  final void Function() onUnauthorized;
  late final Dio _dio;

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, dynamic>? query, bool auth = true}) async {
    final Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(path, data: body, queryParameters: query, options: Options(method: method, responseType: ResponseType.json));
    } on DioException catch (e) {
      throw ApiException(0, 'network', e.message ?? 'No connection');
    }
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return res.data;
    final data = res.data;
    final code = data is Map && data['error'] is String ? data['error'] as String : 'http_$status';
    final msg = data is Map && data['message'] is String ? data['message'] as String : 'Request failed ($status)';
    if (status == 401 && auth) onUnauthorized();
    throw ApiException(status, code, msg);
  }

  Future<String> login(String password, {String? code}) async {
    final data = await _send('POST', '/auth/login', body: {'password': password, if (code != null && code.isNotEmpty) 'code': code}, auth: false);
    return (data as Map)['token'] as String;
  }

  /// Whether the server asks for a 6-digit code at sign-in. False when it cannot be reached.
  Future<bool> totpRequired() async {
    try {
      final d = await _send('GET', '/auth/config', auth: false);
      return d is Map && d['totp'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<dynamic>> categories() async => ((await _send('GET', '/categories')) as Map)['categories'] as List<dynamic>;
  Future<Map<String, dynamic>> settings() async => Map<String, dynamic>.from(((await _send('GET', '/settings')) as Map)['settings'] as Map);
  Future<List<dynamic>> transactionsSince(String? since) async {
    final data = await _send('GET', '/transactions', query: {'include_deleted': '1', 'limit': '5000', 'updated_since': ?since});
    return (data as Map)['transactions'] as List<dynamic>;
  }

  /// The friends ledger: `{doc, updated_at}`, both null when the server has none yet.
  Future<Map<String, dynamic>> ledger() async => Map<String, dynamic>.from((await _send('GET', '/ledger')) as Map);

  /// `{stored: true}` or `{stored: false, doc, updated_at}` when the server copy is newer.
  Future<Map<String, dynamic>> putLedger(String doc, String updatedAt) async =>
      Map<String, dynamic>.from((await _send('PUT', '/ledger', body: {'doc': doc, 'updated_at': updatedAt})) as Map);

  /// App state that is not an entry (goal, sweeps, shop rules, cards, switches): `{doc, updated_at}`, both null when the server has none.
  Future<Map<String, dynamic>> appState() async => Map<String, dynamic>.from((await _send('GET', '/state')) as Map);
  Future<void> putAppState(String doc, String updatedAt) => _send('PUT', '/state', body: {'doc': doc, 'updated_at': updatedAt});

  Future<void> putSetting(String key, String value) async {
    await _send('PUT', '/settings/$key', body: {'value': value});
  }

  Future<List<dynamic>> bills() async => ((await _send('GET', '/bills')) as Map)['bills'] as List<dynamic>;
  Future<void> addCategory(String name, String kind, bool capDefault) => _send('POST', '/categories', body: {'name': name, 'kind': kind, 'cap_default': capDefault});
  Future<void> putCategory(int id, Map<String, dynamic> body) => _send('PUT', '/categories/$id', body: body);
  Future<void> deleteCategory(int id) => _send('DELETE', '/categories/$id');
  Future<void> putBill(String id, Map<String, dynamic> body) => _send('PUT', '/bills/$id', body: body);
  Future<void> deleteBill(String id) async {
    try {
      await _send('DELETE', '/bills/$id');
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
  }

  Future<List<dynamic>> recurring() async => ((await _send('GET', '/recurring')) as Map)['recurring'] as List<dynamic>;
  Future<void> putRecurring(String id, Map<String, dynamic> body) => _send('PUT', '/recurring/$id', body: body);
  Future<void> deleteRecurring(String id) async {
    try {
      await _send('DELETE', '/recurring/$id');
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
  }

  Future<Map<String, dynamic>> parseReceipt(String text) async => Map<String, dynamic>.from((await _send('POST', '/parse-receipt', body: {'text': text})) as Map);

  Future<void> putTransaction(String id, Map<String, dynamic> body) => _send('PUT', '/transactions/$id', body: body);

  /// A 404 means the server never had it, which is the same end state as deleted.
  Future<void> deleteTransaction(String id) async {
    try {
      await _send('DELETE', '/transactions/$id');
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
  }
}


