class ApiConfig {
  static const String domain = "https://dev1-blacforest.vseyal.com";
  static const String baseUrl = "$domain/api";

  static Map<String, String> getHeaders(String? token) {
    final headers = {
      "Content-Type": "application/json",
    };
    if (token != null) {
      headers["Authorization"] = "Bearer $token";
    }
    return headers;
  }
}
