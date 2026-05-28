import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';

/// Resolusi terpusat untuk farming_cycle_id.
///
/// Sumber kebenaran "cycle aktif" adalah backend (`GET /farming-cycle/active`),
/// yang mengembalikan cycle dengan status == "active". Hasilnya di-cache di
/// SharedPreferences agar halaman kontrol tidak perlu menunggu jaringan setiap
/// kali, sekaligus tetap sinkron dengan cycle yang baru dibuat / dipilih.
class FarmingCycleResolver {
  FarmingCycleResolver._();

  static const Duration _requestTimeout = Duration(seconds: 15);

  /// Semua kunci yang dipakai aplikasi untuk menyimpan cycle id terpilih.
  static const List<String> cycleIdKeys = <String>[
    'farming_cycle_id',
    'farmingCycleId',
    'selected_farming_cycle_id',
    'selectedFarmingCycleId',
    'active_farming_cycle_id',
    'activeFarmingCycleId',
    'cycle_id',
    'cycleId',
  ];

  /// Baca cycle id dari cache lokal (SharedPreferences) saja.
  static Future<int?> readCachedCycleId() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in cycleIdKeys) {
      final intValue = prefs.getInt(key);
      if (intValue != null) {
        return intValue;
      }

      final stringValue = prefs.getString(key);
      final parsed = int.tryParse(stringValue?.trim() ?? '');
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  /// Simpan cycle id terpilih ke semua kunci yang dikenal.
  static Future<void> cacheCycleId(int cycleId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in cycleIdKeys) {
      await prefs.setInt(key, cycleId);
    }
  }

  /// Resolusi cycle id yang akan dipakai halaman kontrol.
  ///
  /// - [preferBackend] true  → selalu tanya backend dulu (dipakai saat tab
  ///   kontrol dibuka, agar mengikuti cycle aktif terbaru), fallback ke cache.
  /// - [preferBackend] false → pakai cache dulu, baru tanya backend kalau kosong.
  static Future<int?> resolveCycleId({
    bool preferBackend = false,
    http.Client? client,
    String? overrideBaseUrl,
    String? authToken,
  }) async {
    if (preferBackend) {
      final backendId = await _fetchActiveCycleIdFromBackend(
        client: client,
        overrideBaseUrl: overrideBaseUrl,
        authToken: authToken,
      );
      if (backendId != null) {
        await cacheCycleId(backendId);
        return backendId;
      }
      return readCachedCycleId();
    }

    final cached = await readCachedCycleId();
    if (cached != null) {
      return cached;
    }

    final backendId = await _fetchActiveCycleIdFromBackend(
      client: client,
      overrideBaseUrl: overrideBaseUrl,
      authToken: authToken,
    );
    if (backendId != null) {
      await cacheCycleId(backendId);
    }
    return backendId;
  }

  static Future<int?> _fetchActiveCycleIdFromBackend({
    http.Client? client,
    String? overrideBaseUrl,
    String? authToken,
  }) async {
    final token = authToken ?? await _readStoredToken();
    if (token == null || token.trim().isEmpty) {
      return null;
    }

    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;
    final baseUrl = ApiService.resolveBaseUrl(overrideBaseUrl);

    try {
      final response = await httpClient
          .get(
            Uri.parse('$baseUrl/farming-cycle/active'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer ${token.trim()}',
            },
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        // 404 = belum ada cycle aktif → bukan error fatal.
        debugPrint(
          '[FarmingCycleResolver] GET /farming-cycle/active status: ${response.statusCode}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      return _extractId(decoded);
    } on TimeoutException {
      debugPrint('[FarmingCycleResolver] timeout fetching active cycle');
      return null;
    } catch (error) {
      debugPrint('[FarmingCycleResolver] error fetching active cycle: $error');
      return null;
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  static int? _extractId(Object? decoded) {
    Object? node = decoded;

    if (node is List) {
      node = node.isEmpty ? null : node.first;
    }

    if (node is Map) {
      final map = node;
      final nested = map['data'] ?? map['cycle'] ?? map['item'] ?? map['active_cycle'];
      if (nested is Map) {
        return _asInt(nested['id']);
      }
      return _asInt(map['id']);
    }

    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static Future<String?> _readStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    if (token != null && token.trim().isNotEmpty) {
      return token.trim();
    }
    final fallback = prefs.getString('accessToken');
    if (fallback != null && fallback.trim().isNotEmpty) {
      return fallback.trim();
    }
    return null;
  }
}
