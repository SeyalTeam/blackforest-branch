class ApiConfig {
  static const String domain = "https://blackforest.vseyal.com";
  static const String baseUrl = "$domain/api";
  static const String apiKey = "bf_prod_9Xv2Lm5Kp8Qr3Zn1Yw7J";

  static Map<String, String> getHeaders(String? token) {
    final headers = {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
    };
    if (token != null) {
      headers["Authorization"] = "Bearer $token";
    }
    return headers;
  }
}
