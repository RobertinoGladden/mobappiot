import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../AuthSessionService.dart';
import '../api_service.dart';

class NotifAlertService {
	static const String baseUrl = ApiService.baseUrl;

	static const List<String> _notificationSettingsPaths = [
		'/alerts/settings',
		'/alerts/preferences',
		'/notifications/settings',
	];

	static String _resolveBaseUrl(String? overrideBaseUrl) {
		return ApiService.resolveBaseUrl(overrideBaseUrl);
	}

	static List<Map<String, dynamic>> _decodeAlertList(String responseBody) {
		if (responseBody.trim().isEmpty) {
			return <Map<String, dynamic>>[];
		}

		final decodedBody = json.decode(responseBody);

		if (decodedBody is List) {
			return decodedBody
					.whereType<Map>()
					.map((item) => _normalizeAlertMap(item))
					.toList();
		}

		if (decodedBody is Map<String, dynamic>) {
			final listCandidate = decodedBody['data'] ?? decodedBody['alerts'];
			if (listCandidate is List) {
				return listCandidate
						.whereType<Map>()
						.map((item) => _normalizeAlertMap(item))
						.toList();
			}

			return [_normalizeAlertMap(decodedBody)];
		}

		if (decodedBody is Map) {
			final normalized = decodedBody.map(
				(key, value) => MapEntry(key.toString(), value),
			);
			final listCandidate = normalized['data'] ?? normalized['alerts'];
			if (listCandidate is List) {
				return listCandidate
						.whereType<Map>()
						.map((item) => _normalizeAlertMap(item))
						.toList();
			}

			return [_normalizeAlertMap(normalized)];
		}

		throw Exception('Unexpected response format');
	}

	static Map<String, dynamic> _decodeMap(String responseBody) {
		final decodedBody = json.decode(responseBody);

		if (decodedBody is Map<String, dynamic>) {
			return _normalizeAlertMap(decodedBody);
		}

		if (decodedBody is Map) {
			return _normalizeAlertMap(decodedBody);
		}

		if (decodedBody is List &&
				decodedBody.isNotEmpty &&
				decodedBody.first is Map) {
			final first = decodedBody.first as Map;
			return _normalizeAlertMap(first);
		}

		return {'success': true};
	}

	static Map<String, dynamic> _extractSettingsMap(String responseBody) {
		final decoded = _decodeMap(responseBody);

		final data = decoded['data'];
		if (data is Map<String, dynamic>) {
			return data;
		}
		if (data is Map) {
			return data.map((key, value) => MapEntry(key.toString(), value));
		}

		final settings = decoded['settings'];
		if (settings is Map<String, dynamic>) {
			return settings;
		}
		if (settings is Map) {
			return settings.map((key, value) => MapEntry(key.toString(), value));
		}

		final preferences = decoded['preferences'];
		if (preferences is Map<String, dynamic>) {
			return preferences;
		}
		if (preferences is Map) {
			return preferences.map((key, value) => MapEntry(key.toString(), value));
		}

		return decoded;
	}

	static Map<String, dynamic> _normalizeAlertMap(Map rawAlert) {
		final normalized =
				rawAlert.map((key, value) => MapEntry(key.toString(), value));
		final resolvedState = _resolveAlertState(normalized);
		if (resolvedState != null) {
			normalized['state'] = resolvedState;
		}
		return normalized;
	}

	static String? _resolveAlertState(Map<String, dynamic> alert) {
		final stateRaw =
				(alert['state'] ?? alert['status'])?.toString().toLowerCase();
		if (stateRaw == 'active') {
			return 'active';
		}
		if (stateRaw == 'resolved' || stateRaw == 'dismissed') {
			return 'resolved';
		}

		if (alert['resolved_at'] != null || alert['is_resolved'] == true) {
			return 'resolved';
		}
		if (alert['is_active'] == true) {
			return 'active';
		}
		if (alert['is_active'] == false) {
			return 'resolved';
		}

		return null;
	}

	static Future<List<Map<String, dynamic>>> getActiveAlerts({
		http.Client? client,
		String? overrideBaseUrl,
		Duration timeout = const Duration(seconds: 10),
	}) async {
		final httpClient = client ?? http.Client();
		final shouldCloseClient = client == null;
		final resolvedBaseUrl = _resolveBaseUrl(overrideBaseUrl);
		final uri = Uri.parse('$resolvedBaseUrl/alerts/active');

		try {
			debugPrint('[NotifAlertService] GET $uri');

			final response = await AuthSessionService.performWithAutoRefresh(
				client: httpClient,
				overrideBaseUrl: overrideBaseUrl,
				timeout: timeout,
				request: (token) {
					return httpClient
							.get(
								uri,
								headers: {
									'Accept': 'application/json',
									'Authorization': 'Bearer $token',
								},
							)
							.timeout(timeout);
				},
			).timeout(timeout);

			debugPrint(
				'[NotifAlertService] GET /alerts/active status: ${response.statusCode}',
			);

			if (response.statusCode == 204 || response.body.trim().isEmpty) {
				return <Map<String, dynamic>>[];
			}

			if (response.statusCode != 200) {
				throw Exception(
					_extractMessage(response.body) ??
							'Failed to load active alerts (${response.statusCode})',
				);
			}

			return _decodeAlertList(response.body);
		} on TimeoutException {
			throw Exception('Request timeout');
		} finally {
			if (shouldCloseClient) {
				httpClient.close();
			}
		}
	}

	static Future<List<Map<String, dynamic>>> getAlertHistory({
		http.Client? client,
		String? overrideBaseUrl,
		String? period,
		Duration timeout = const Duration(seconds: 10),
	}) async {
		final httpClient = client ?? http.Client();
		final shouldCloseClient = client == null;
		final resolvedBaseUrl = _resolveBaseUrl(overrideBaseUrl);

		final historyUri = Uri.parse('$resolvedBaseUrl/alerts/history').replace(
			queryParameters: period == null || period.trim().isEmpty
					? null
					: {'period': period.trim()},
		);

		try {
			debugPrint('[NotifAlertService] GET $historyUri');

			final response = await AuthSessionService.performWithAutoRefresh(
				client: httpClient,
				overrideBaseUrl: overrideBaseUrl,
				timeout: timeout,
				request: (token) {
					return httpClient
							.get(
								historyUri,
								headers: {
									'Accept': 'application/json',
									'Authorization': 'Bearer $token',
								},
							)
							.timeout(timeout);
				},
			);

			debugPrint(
				'[NotifAlertService] GET /alerts/history status: ${response.statusCode}',
			);

			if (response.statusCode == 204 || response.body.trim().isEmpty) {
				return <Map<String, dynamic>>[];
			}

			if (response.statusCode != 200) {
				throw Exception(
					_extractMessage(response.body) ??
							'Failed to load alert history (${response.statusCode})',
				);
			}

			return _decodeAlertList(response.body);
		} on TimeoutException {
			throw Exception('Request timeout');
		} finally {
			if (shouldCloseClient) {
				httpClient.close();
			}
		}
	}

	static Future<bool> resolveAlert({
		required String alertId,
		http.Client? client,
		String? overrideBaseUrl,
		Duration timeout = const Duration(seconds: 10),
	}) async {
		final httpClient = client ?? http.Client();
		final shouldCloseClient = client == null;
		final resolvedBaseUrl = _resolveBaseUrl(overrideBaseUrl);
		final uri = Uri.parse('$resolvedBaseUrl/alerts/$alertId/resolve');

		try {
			debugPrint('[NotifAlertService] PATCH $uri');

			final response = await AuthSessionService.performWithAutoRefresh(
				client: httpClient,
				overrideBaseUrl: overrideBaseUrl,
				timeout: timeout,
				request: (token) {
					return httpClient
							.patch(
								uri,
								headers: {
									'Accept': 'application/json',
									'Authorization': 'Bearer $token',
								},
							)
							.timeout(timeout);
				},
			);

			if (response.statusCode < 200 || response.statusCode >= 300) {
				throw Exception(_extractMessage(response.body) ?? 'Gagal menyelesaikan alert');
			}

			return true;
		} on TimeoutException {
			throw Exception('Request timeout');
		} finally {
			if (shouldCloseClient) {
				httpClient.close();
			}
		}
	}

	static Future<bool> resolveAllAlerts({
		http.Client? client,
		String? overrideBaseUrl,
		Duration timeout = const Duration(seconds: 10),
	}) async {
		final httpClient = client ?? http.Client();
		final shouldCloseClient = client == null;
		final resolvedBaseUrl = _resolveBaseUrl(overrideBaseUrl);
		final uri = Uri.parse('$resolvedBaseUrl/alerts/resolve-all');

		try {
			debugPrint('[NotifAlertService] PATCH $uri');

			final response = await AuthSessionService.performWithAutoRefresh(
				client: httpClient,
				overrideBaseUrl: overrideBaseUrl,
				timeout: timeout,
				request: (token) {
					return httpClient
							.patch(
								uri,
								headers: {
									'Accept': 'application/json',
									'Authorization': 'Bearer $token',
								},
							)
							.timeout(timeout);
				},
			);

			if (response.statusCode < 200 || response.statusCode >= 300) {
				throw Exception(_extractMessage(response.body) ?? 'Gagal menyelesaikan semua alert');
			}

			return true;
		} on TimeoutException {
			throw Exception('Request timeout');
		} finally {
			if (shouldCloseClient) {
				httpClient.close();
			}
		}
	}

	static Future<Map<String, dynamic>> getNotificationSettings({
		http.Client? client,
		String? overrideBaseUrl,
		Duration timeout = const Duration(seconds: 10),
	}) async {
		final httpClient = client ?? http.Client();
		final shouldCloseClient = client == null;
		final resolvedBaseUrl = _resolveBaseUrl(overrideBaseUrl);

		try {
			for (final path in _notificationSettingsPaths) {
				final uri = Uri.parse('$resolvedBaseUrl$path');
				debugPrint('[NotifAlertService] GET $uri');

				final response = await AuthSessionService.performWithAutoRefresh(
					client: httpClient,
					overrideBaseUrl: overrideBaseUrl,
					timeout: timeout,
					request: (token) {
						return httpClient
								.get(
									uri,
									headers: {
										'Accept': 'application/json',
										'Authorization': 'Bearer $token',
									},
								)
								.timeout(timeout);
					},
				);

				if (response.statusCode == 404) {
					continue;
				}

				if (response.statusCode < 200 || response.statusCode >= 300) {
					throw Exception(
						_extractMessage(response.body) ??
								'Failed to load notification settings (${response.statusCode})',
					);
				}

				return _extractSettingsMap(response.body);
			}

			throw Exception('Notification settings endpoint not available');
		} on TimeoutException {
			throw Exception('Request timeout');
		} finally {
			if (shouldCloseClient) {
				httpClient.close();
			}
		}
	}

	static Future<Map<String, dynamic>> updateNotificationSettings({
		required Map<String, dynamic> settings,
		http.Client? client,
		String? overrideBaseUrl,
		Duration timeout = const Duration(seconds: 10),
	}) async {
		final httpClient = client ?? http.Client();
		final shouldCloseClient = client == null;
		final resolvedBaseUrl = _resolveBaseUrl(overrideBaseUrl);

		try {
			for (final path in _notificationSettingsPaths) {
				final uri = Uri.parse('$resolvedBaseUrl$path');
				debugPrint('[NotifAlertService] PATCH $uri');

				final response = await AuthSessionService.performWithAutoRefresh(
					client: httpClient,
					overrideBaseUrl: overrideBaseUrl,
					timeout: timeout,
					request: (token) {
						return httpClient
								.patch(
									uri,
									headers: {
										'Accept': 'application/json',
										'Content-Type': 'application/json',
										'Authorization': 'Bearer $token',
									},
									body: jsonEncode(settings),
								)
								.timeout(timeout);
					},
				);

				if (response.statusCode == 404) {
					continue;
				}

				if (response.statusCode < 200 || response.statusCode >= 300) {
					throw Exception(
						_extractMessage(response.body) ??
								'Failed to update notification settings (${response.statusCode})',
					);
				}

				return _extractSettingsMap(response.body);
			}

			throw Exception('Notification settings endpoint not available');
		} on TimeoutException {
			throw Exception('Request timeout');
		} finally {
			if (shouldCloseClient) {
				httpClient.close();
			}
		}
	}

	static String? _extractMessage(String responseBody) {
		try {
			final decoded = json.decode(responseBody);
			if (decoded is Map) {
				final map = decoded.map((key, value) => MapEntry(key.toString(), value));
				final message = map['message'] ?? map['error'] ?? map['detail'];
				if (message != null) {
					return message.toString();
				}
			}
		} catch (_) {}

		return null;
	}
}