import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ProfileService.dart';
import 'api_service.dart';

class AuthSessionService {
  static const Duration requestTimeout = Duration(seconds: 20);
  static const List<String> _refreshPaths = <String>[
    '/auth/refresh',
    '/auth/refresh-token',
    '/auth/token/refresh',
    '/auth/refreshToken',
    '/auth/login/refresh',
  ];

  static Completer<bool>? _refreshCompleter;

  static Future<http.Response> performWithAutoRefresh({
    required http.Client client,
    required Future<http.Response> Function(String token) request,
    String? overrideBaseUrl,
    String? authToken,
    Duration timeout = requestTimeout,
  }) async {
    final resolvedToken = authToken ?? await _readStoredAccessToken();
    if (resolvedToken == null || resolvedToken.trim().isEmpty) {
      throw Exception('Token autentikasi tidak ditemukan. Silakan login ulang.');
    }

    final initialResponse = await request(resolvedToken.trim());
    if (initialResponse.statusCode != 401) {
      return initialResponse;
    }

    final refreshed = await _refreshSession(
      client: client,
      overrideBaseUrl: overrideBaseUrl,
      timeout: timeout,
    );

    if (!refreshed) {
      return initialResponse;
    }

    final refreshedToken = await _readStoredAccessToken();
    if (refreshedToken == null || refreshedToken.trim().isEmpty) {
      return initialResponse;
    }

    return request(refreshedToken.trim());
  }

  static Future<bool> _refreshSession({
    required http.Client client,
    String? overrideBaseUrl,
    Duration timeout = requestTimeout,
  }) async {
    final existing = _refreshCompleter;
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    try {
      final refreshToken = await _readStoredRefreshToken();
      if (refreshToken == null || refreshToken.trim().isEmpty) {
        await _clearInvalidSession();
        completer.complete(false);
        return false;
      }

      final resolvedBaseUrl = ApiService.resolveBaseUrl(overrideBaseUrl);
      final attempts = <Future<http.Response> Function()>[];

      for (final path in _refreshPaths) {
        for (final payload in <Map<String, dynamic>>[
          {'refresh_token': refreshToken.trim()},
          {'refreshToken': refreshToken.trim()},
          {'token': refreshToken.trim()},
          const <String, dynamic>{},
        ]) {
          attempts.add(() async {
            final response = await client
                .post(
                  Uri.parse('$resolvedBaseUrl$path'),
                  headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer ${refreshToken.trim()}',
                  },
                  body: payload.isEmpty ? null : jsonEncode(payload),
                )
                .timeout(timeout);
            return response;
          });
        }
      }

      for (final attempt in attempts) {
        try {
          final response = await attempt();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            continue;
          }

          final decodedBody = _decodeResponseBody(response.body);
          final responseMap = _normalizeMap(decodedBody);
          final dataMap = _extractDataMap(responseMap);
          final newAccessToken = _extractToken(responseMap, dataMap);
          if (newAccessToken == null || newAccessToken.trim().isEmpty) {
            continue;
          }

          final newRefreshToken =
              _extractRefreshToken(responseMap, dataMap) ?? refreshToken.trim();
          final tokenType = _extractTokenType(responseMap, dataMap);

          await _storeTokens(
            accessToken: newAccessToken.trim(),
            refreshToken: newRefreshToken.trim(),
            tokenType: tokenType,
          );

          completer.complete(true);
          return true;
        } on TimeoutException {
          continue;
        } catch (_) {
          continue;
        }
      }

      await _clearInvalidSession();
      completer.complete(false);
      return false;
    } catch (_) {
      await _clearInvalidSession();
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      return false;
    } finally {
      _refreshCompleter = null;
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
  }

  static Future<String?> _readStoredAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    if (token != null && token.trim().isNotEmpty) {
      return token.trim();
    }

    final fallbackToken = prefs.getString('accessToken');
    if (fallbackToken != null && fallbackToken.trim().isNotEmpty) {
      return fallbackToken.trim();
    }

    return null;
  }

  static Future<String?> _readStoredRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refreshToken');
    if (refreshToken != null && refreshToken.trim().isNotEmpty) {
      return refreshToken.trim();
    }

    return null;
  }

  static Future<void> _storeTokens({
    required String accessToken,
    required String refreshToken,
    String? tokenType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('authToken', accessToken);
    await prefs.setString('accessToken', accessToken);
    await prefs.setString('refreshToken', refreshToken);
    if (tokenType != null && tokenType.trim().isNotEmpty) {
      await prefs.setString('tokenType', tokenType.trim());
    }
  }

  static Future<void> _clearInvalidSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    await prefs.remove('authToken');
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');
    await prefs.remove('tokenType');
    await prefs.remove('userEmail');
    await ProfileService.clearCachedProfile();
  }

  static Object? _decodeResponseBody(String body) {
    if (body.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  static Map<String, dynamic> _normalizeMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map((key, dynamic nestedValue) {
        return MapEntry(key.toString(), nestedValue);
      });
    }

    return <String, dynamic>{};
  }

  static Map<String, dynamic>? _extractDataMap(
    Map<String, dynamic> responseMap,
  ) {
    final dynamic data = responseMap['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return _normalizeMap(data);
    }

    return null;
  }

  static String? _extractToken(
    Map<String, dynamic> responseMap,
    Map<String, dynamic>? data,
  ) {
    final candidates = <Object?>[
      responseMap['access_token'],
      responseMap['accessToken'],
      responseMap['token'],
      responseMap['jwt'],
      data?['access_token'],
      data?['accessToken'],
      data?['token'],
      data?['jwt'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }

    return null;
  }

  static String? _extractRefreshToken(
    Map<String, dynamic> responseMap,
    Map<String, dynamic>? data,
  ) {
    final candidates = <Object?>[
      responseMap['refresh_token'],
      responseMap['refreshToken'],
      data?['refresh_token'],
      data?['refreshToken'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }

    return null;
  }

  static String? _extractTokenType(
    Map<String, dynamic> responseMap,
    Map<String, dynamic>? data,
  ) {
    final candidates = <Object?>[
      responseMap['token_type'],
      responseMap['tokenType'],
      data?['token_type'],
      data?['tokenType'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }

    return null;
  }

  /// Check stored access token and refresh session if needed.
  /// Returns `true` when a valid session (token) is available after this call.
  static Future<bool> checkAndRefreshSession({
    http.Client? client,
    String? overrideBaseUrl,
    Duration timeout = requestTimeout,
  }) async {
    final token = await _readStoredAccessToken();
    if (token == null || token.trim().isEmpty) {
      return false;
    }

    final isExpired = _isJwtExpired(token.trim());
    if (!isExpired) {
      return true;
    }

    var createdClient = false;
    var usedClient = client;
    if (usedClient == null) {
      usedClient = http.Client();
      createdClient = true;
    }

    try {
      final refreshed = await _refreshSession(
        client: usedClient,
        overrideBaseUrl: overrideBaseUrl,
        timeout: timeout,
      );
      return refreshed;
    } finally {
      if (createdClient) {
        usedClient.close();
      }
    }
  }

  static bool _isJwtExpired(String token, {int leewaySeconds = 60}) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return false;

      String normalized = parts[1];
      // normalize padding for base64Url
      normalized = base64Url.normalize(normalized);
      final payloadBytes = base64Url.decode(normalized);
      final payload = jsonDecode(utf8.decode(payloadBytes));
      if (payload is Map<String, dynamic>) {
        final exp = payload['exp'];
        if (exp is int) {
          final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
          return exp <= (now + leewaySeconds);
        }
        if (exp is String) {
          final parsed = int.tryParse(exp);
          if (parsed != null) {
            final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
            return parsed <= (now + leewaySeconds);
          }
        }
      }

      return false;
    } catch (_) {
      return false;
    }
  }
}