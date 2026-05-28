class ApiService {
  static const String defaultBaseUrl =
      'https://backend-nila-iot-production.up.railway.app';
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultBaseUrl,
  );

  static String resolveBaseUrl(String? overrideBaseUrl) {
    final value = overrideBaseUrl?.trim();
    if (value == null || value.isEmpty || value.toLowerCase() == 'null') {
      return baseUrl;
    }
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static Map<String, String> jsonHeaders({String? token}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, String> authHeaders(String token) {
    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
}
