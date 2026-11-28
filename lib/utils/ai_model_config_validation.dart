void requireNonEmpty(String value, String code) {
  if (value.trim().isEmpty) throw ArgumentError(code);
}

void requireTrimmedNonEmpty(String value, String code) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw ArgumentError(code);
  }
}

void requirePositive(int? value, String code) {
  if (value == null || value <= 0) throw ArgumentError(code);
}

void validateHttpsBaseUrl(String value) {
  final uri = Uri.tryParse(value);
  if (value != value.trim() ||
      uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError('AI_PROVIDER_BASE_URL_MUST_BE_HTTPS_ORIGIN');
  }
}
