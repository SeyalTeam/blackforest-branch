import 'dart:async';

const String apiHostPrimary = 'dev1-blacforest.vseyal.com';
const String apiHostFallback = 'dev1-blacforest.vseyal.com';

String _normalizeHost(String? value) {
  var normalized = (value ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return '';

  if (normalized.startsWith('//')) {
    normalized = 'https:$normalized';
  }

  if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
    final parsed = Uri.tryParse(normalized);
    if (parsed != null && parsed.host.trim().isNotEmpty) {
      normalized = parsed.host.trim().toLowerCase();
    }
  }

  if (normalized.contains('/')) {
    normalized = normalized.split('/').first;
  }

  if (normalized.contains(':')) {
    normalized = normalized.split(':').first;
  }

  return normalized.trim();
}

bool isKnownApiHost(String host) {
  final normalized = _normalizeHost(host);
  return normalized == apiHostPrimary || normalized == apiHostFallback;
}

Future<void> ensureApiHostRoutingReady() async {}

List<String> getApiHostCandidates({String? preferredHost}) {
  return const <String>[apiHostPrimary, apiHostFallback];
}

Uri withActiveApiHost(Uri uri) {
  return uri;
}

List<Uri> buildApiHostCandidateUris(Uri baseUri) {
  return <Uri>[
    baseUri,
    baseUri.replace(host: apiHostFallback),
  ];
}

String resolveApiAssetUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return value;
  if (value.startsWith('data:image/')) return value;

  final sanitized = value.replaceAll(' ', '%20');
  final normalizedInput = sanitized.startsWith('//')
      ? 'https:$sanitized'
      : sanitized;

  if (normalizedInput.startsWith('http://') ||
      normalizedInput.startsWith('https://')) {
    return normalizedInput;
  }

  final relative = normalizedInput.startsWith('/')
      ? normalizedInput
      : '/$normalizedInput';
  return 'https://$apiHostPrimary$relative';
}
