import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_service.dart';

class RiwayatDataService {
  static String resolveBaseUrl(String? overrideBaseUrl) {
    return ApiService.resolveBaseUrl(overrideBaseUrl);
  }

  static Future<List<dynamic>> getSensorData({
    http.Client? client,
    String? overrideBaseUrl,
    int hours = 24,
  }) async {
    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    try {
      final resolvedBaseUrl = resolveBaseUrl(overrideBaseUrl);
      final response = await httpClient.get(
        Uri.parse('$resolvedBaseUrl/sensor-data/history?hours=$hours'),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load riwayat data');
      }

      final decodedBody = json.decode(response.body);
      if (decodedBody is List<dynamic>) {
        return decodedBody;
      }

      if (decodedBody is Map && decodedBody['data'] is List<dynamic>) {
        return decodedBody['data'] as List<dynamic>;
      }

      throw Exception('Unexpected response format');
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  static Future<List<dynamic>> fetchSensorHistory({
    http.Client? client,
    String? overrideBaseUrl,
    int hours = 24,
    Future<List<dynamic>> Function()? fallbackFetcher,
  }) {
    if (fallbackFetcher != null) {
      return fallbackFetcher();
    }

    return getSensorData(
      client: client,
      overrideBaseUrl: overrideBaseUrl,
      hours: hours,
    );
  }
}