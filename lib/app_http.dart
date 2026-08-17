import 'dart:async';
import 'package:http/http.dart' as raw_http;

import 'package:branch/api_server_prefs.dart';
import 'package:branch/app_version.dart';
import 'package:branch/auth_session_manager.dart';

export 'package:http/http.dart'
    show
        BaseRequest,
        BaseResponse,
        ByteStream,
        Client,
        ClientException,
        MultipartFile,
        MultipartRequest,
        Response,
        StreamedResponse;

bool _isUnauthorized(int statusCode) => statusCode == 401 || statusCode == 403;

bool _isLoginEndpoint(Uri url) {
  if (!isKnownApiHost(url.host)) return false;
  return url.path == '/api/users/login' || url.path == '/api/v1/users/login';
}

bool _shouldHandleUnauthorized(Uri url, Map<String, String>? headers) {
  if (_isLoginEndpoint(url)) return false;
  return true;
}

Future<raw_http.Response> _interceptResponse(
  Future<raw_http.Response> responseFuture, {
  required Uri url,
  required Map<String, String>? headers,
}) async {
  final response = await responseFuture;
  if (_isUnauthorized(response.statusCode) &&
      _shouldHandleUnauthorized(url, headers)) {
    unawaited(
      AuthSessionManager.instance.handleUnauthorized(
        message: 'Session expired. Please login again.',
      ),
    );
  }
  return response;
}

Future<Map<String, String>> _prepareHeaders(
  Uri url,
  Map<String, String>? headers,
) async {
  final map = headers != null
      ? Map<String, String>.from(headers)
      : <String, String>{};
  if (!map.containsKey('Content-Type')) {
    map['Content-Type'] = 'application/json';
  }
  if (!map.containsKey('x-app-version') && !map.containsKey('X-App-Version')) {
    map['x-app-version'] = AppVersion.current;
  }
  return map;
}

Future<raw_http.Response> get(
  Uri url, {
  Map<String, String>? headers,
}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return _interceptResponse(
    raw_http.get(url, headers: resolvedHeaders),
    url: url,
    headers: resolvedHeaders,
  );
}

Future<raw_http.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return _interceptResponse(
    raw_http.post(url, headers: resolvedHeaders, body: body),
    url: url,
    headers: resolvedHeaders,
  );
}

Future<raw_http.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return _interceptResponse(
    raw_http.put(url, headers: resolvedHeaders, body: body),
    url: url,
    headers: resolvedHeaders,
  );
}

Future<raw_http.Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return _interceptResponse(
    raw_http.patch(url, headers: resolvedHeaders, body: body),
    url: url,
    headers: resolvedHeaders,
  );
}

Future<raw_http.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return _interceptResponse(
    raw_http.delete(url, headers: resolvedHeaders, body: body),
    url: url,
    headers: resolvedHeaders,
  );
}

Future<raw_http.Response> head(
  Uri url, {
  Map<String, String>? headers,
}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return _interceptResponse(
    raw_http.head(url, headers: resolvedHeaders),
    url: url,
    headers: resolvedHeaders,
  );
}
