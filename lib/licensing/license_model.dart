import 'dart:convert';

const yanjiLicenseAppId = 'com.nihaisha.nihaisha_app';
const yanjiLifetimeProductId = 'yanji_pro_lifetime';

enum LicenseFeature {
  aiAdvanced('ai_advanced'),
  contextualAssistant('contextual_assistant'),
  advancedLearning('advanced_learning'),
  advancedExport('advanced_export');

  const LicenseFeature(this.id);
  final String id;
}

class ProfessionalEditionCatalog {
  ProfessionalEditionCatalog._();

  static const productId = yanjiLifetimeProductId;
  static const productRevision = 1;
  static const featureIds = <String>{
    'ai_advanced',
    'contextual_assistant',
    'advanced_learning',
    'advanced_export',
  };
  static const deviceSecurityLevels = <String>{
    'SOFTWARE',
    'TRUSTED_ENVIRONMENT',
    'STRONGBOX',
    'UNKNOWN',
  };
}

enum EntitlementStatus {
  unlicensed,
  loading,
  valid,
  validWithUnknownFeatures,
  unknownFeatureOnly,
  keyMissing,
  keyInvalidated,
  signatureInvalid,
  appMismatch,
  productMismatch,
  issuerUnknown,
  issuerCompromised,
  deviceMismatch,
  requestMismatch,
  revokedInUpdatedApp,
  storeCorrupt,
}

class LicensePayload {
  const LicensePayload({
    required this.schemaVersion,
    required this.licenseId,
    required this.orderId,
    required this.productId,
    required this.productRevision,
    required this.appId,
    required this.perpetual,
    required this.featureIds,
    required this.deviceKeySha256,
    required this.requestId,
    required this.requestNonce,
    required this.requestSha256,
    required this.deviceKeySecurityLevel,
    required this.issuedAt,
    required this.issuerKeyId,
  });

  final int schemaVersion;
  final String licenseId;
  final String orderId;
  final String productId;
  final int productRevision;
  final String appId;
  final bool perpetual;
  final Set<String> featureIds;

  /// Base64URL SHA-256 of the Android Keystore SPKI DER public key.
  final String deviceKeySha256;

  /// Identifies the exact YANJIR1 request used for issuance.
  final String requestId;
  final String requestNonce;
  final String requestSha256;

  /// Reported device metadata, not hardware attestation.
  final String deviceKeySecurityLevel;

  /// Informational UTC timestamp, not an expiry or offline clock gate.
  final DateTime issuedAt;
  final String issuerKeyId;

  Set<String> get knownFeatureIds =>
      Set.unmodifiable(featureIds.intersection(ProfessionalEditionCatalog.featureIds));

  Set<String> get unknownFeatureIds =>
      Set.unmodifiable(featureIds.difference(ProfessionalEditionCatalog.featureIds));

  bool grants(LicenseFeature feature) =>
      ProfessionalEditionCatalog.featureIds.contains(feature.id) &&
      featureIds.contains(feature.id);

  factory LicensePayload.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('License payload must be a JSON object.');
    }
    final json = Map<String, Object?>.from(value);

    int requiredInt(String key) {
      final result = json[key];
      if (result is! int) {
        throw FormatException('Invalid integer field: $key');
      }
      return result;
    }

    String requiredString(String key, {int maxLength = 256}) {
      final result = json[key];
      if (result is! String ||
          result.trim().isEmpty ||
          result.length > maxLength) {
        throw FormatException('Invalid string field: $key');
      }
      return result;
    }

    final schemaVersion = requiredInt('schema_version');
    final licenseId = requiredString('license_id');
    final orderId = requiredString('order_id', maxLength: 80);
    final productId = requiredString('product_id', maxLength: 80);
    final productRevision = requiredInt('product_revision');
    final appId = requiredString('app_id', maxLength: 160);
    final perpetual = json['perpetual'];
    if (perpetual != true) {
      throw const FormatException('Only perpetual licenses are supported.');
    }

    final rawFeatures = json['features'];
    if (rawFeatures is! List ||
        rawFeatures.isEmpty ||
        rawFeatures.length > 32) {
      throw const FormatException('Invalid license feature list.');
    }
    final featureIds = <String>{};
    for (final feature in rawFeatures) {
      if (feature is! String ||
          !RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(feature) ||
          !featureIds.add(feature)) {
        throw const FormatException('Invalid or duplicate license feature.');
      }
    }

    final deviceKeySha256 =
        requiredString('device_key_sha256', maxLength: 64);
    final requestId = requiredString('request_id', maxLength: 64);
    final requestNonce = requiredString('request_nonce', maxLength: 64);
    final requestSha256 = requiredString('request_sha256', maxLength: 64);
    if (!_isSha256Base64Url(deviceKeySha256) ||
        !_isSha256Base64Url(requestSha256) ||
        !_isRandomNonceBase64Url(requestNonce)) {
      throw const FormatException('Invalid device/request binding fields.');
    }
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(requestId)) {
      throw const FormatException('Invalid request id.');
    }

    final deviceKeySecurityLevel =
        requiredString('device_key_security_level', maxLength: 32);
    if (!ProfessionalEditionCatalog.deviceSecurityLevels
        .contains(deviceKeySecurityLevel)) {
      throw const FormatException('Invalid reported device security level.');
    }

    final issuedAtText = requiredString('issued_at', maxLength: 64);
    final issuedAt = DateTime.tryParse(issuedAtText);
    if (issuedAt == null || !issuedAt.isUtc || !issuedAtText.endsWith('Z')) {
      throw const FormatException('issued_at must be an ISO-8601 UTC value.');
    }

    final issuerKeyId = requiredString('issuer_key_id', maxLength: 64);
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$').hasMatch(issuerKeyId)) {
      throw const FormatException('Invalid issuer key id.');
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(licenseId) ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$').hasMatch(orderId)) {
      throw const FormatException('Invalid license or order identifier.');
    }

    return LicensePayload(
      schemaVersion: schemaVersion,
      licenseId: licenseId,
      orderId: orderId,
      productId: productId,
      productRevision: productRevision,
      appId: appId,
      perpetual: true,
      featureIds: Set<String>.unmodifiable(featureIds),
      deviceKeySha256: deviceKeySha256,
      requestId: requestId,
      requestNonce: requestNonce,
      requestSha256: requestSha256,
      deviceKeySecurityLevel: deviceKeySecurityLevel,
      issuedAt: issuedAt,
      issuerKeyId: issuerKeyId,
    );
  }

  static bool _isSha256Base64Url(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) return false;
    try {
      return _decodeBase64Url(value).length == 32;
    } on FormatException {
      return false;
    }
  }

  static bool _isRandomNonceBase64Url(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) return false;
    try {
      return _decodeBase64Url(value).length == 32;
    } on FormatException {
      return false;
    }
  }

  static List<int> _decodeBase64Url(String value) {
    final normalized = value.padRight(
      value.length + ((4 - value.length % 4) % 4),
      '=',
    );
    return base64Url.decode(normalized);
  }
}
