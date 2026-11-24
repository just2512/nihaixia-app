import 'dart:convert';

const yanjiLicenseAppId = 'com.nihaisha.nihaisha_app';
const yanjiLifetimeProductId = 'yanji_pro_lifetime';

/// Failure causes for local perpetual-license verification and storage.
enum LicenseFailureReason {
  initializationTimeout,
  unlicensed,
  featureNotGranted,
  storeCorrupt,
  storageUnavailable,
  issuerUnknown,
  signatureInvalid,
  unsupportedRevision,
  deviceMismatch,
  keyMissing,
  keyInvalidated,
  keystoreUnavailable,
  providerError,
  licenseRevoked,
  issuerCompromised,
  invalidTokenFormat,
  wrongApplication,
  wrongProduct,
}

enum LicenseFeature {
  aiAccess('ai_access'),

  /// Historical revision-1 identifiers. They are not separate entitlements.
  @Deprecated('Use aiAccess; revision-1 claims map to the single AI entitlement.')
  aiAdvanced('ai_advanced'),
  @Deprecated('Use aiAccess; revision-1 claims map to the single AI entitlement.')
  contextualAssistant('contextual_assistant'),

  /// Reserved protocol identifiers; not currently granted.
  advancedLearning('advanced_learning'),
  advancedExport('advanced_export');

  const LicenseFeature(this.id);
  final String id;
}

class ProfessionalEditionCatalog {
  ProfessionalEditionCatalog._();

  static const productId = yanjiLifetimeProductId;
  static const minimumSupportedProtocolRevision = 1;
  static const supportedProtocolRevisions = <int>{1, 2};

  /// Protocol-known IDs. The two revision-1 AI claims remain known only so
  /// historical signed Tokens can be interpreted without changing their bytes.
  static const knownFeatureIds = <String>{
    'ai_access',
    'ai_advanced',
    'contextual_assistant',
    'advanced_learning',
    'advanced_export',
  };

  /// Revision 1 is historical input; revision 2 has one runtime entitlement.
  static const protocolAllowedFeatureIdsByRevision = <int, Set<String>>{
    1: {'ai_advanced', 'contextual_assistant'},
    2: {'ai_access'},
  };

  /// New issuance is revision 2 only and carries exactly one entitlement.
  static const issuableFeatureIdsByRevision = <int, Set<String>>{
    2: {'ai_access'},
  };

  /// The only entitlement enforced by this client.
  static const enforcedFeatureIds = <String>{'ai_access'};

  static const legacyAiFeatureIds = <String>{
    'ai_advanced',
    'contextual_assistant',
  };

  static Set<String> allowedFeatureIdsForRevision(int revision) =>
      protocolAllowedFeatureIdsByRevision[revision] ?? const <String>{};
}

enum EntitlementStatus {
  unlicensed,
  loading,
  valid,
  validWithUnsupportedFeatures,
  validWithoutGrantedFeatures,
  keyMissing,
  keyInvalidated,
  signatureInvalid,
  appMismatch,
  productMismatch,
  issuerUnknown,
  issuerCompromised,
  deviceMismatch,
  revokedInUpdatedApp,
  storeCorrupt,
}

class LicensePayload {
  const LicensePayload({
    required this.schemaVersion,
    required this.licenseId,
    required this.orderId,
    required this.productId,
    required this.protocolRevision,
    required this.appId,
    required this.perpetual,
    required this.featureIds,
    required this.devicePublicKeySha256,
    required this.requestId,
    required this.issuedAt,
    required this.issuerKeyId,
  });

  final int schemaVersion;
  final String licenseId;
  final String orderId;
  final String productId;
  final int protocolRevision;
  final String appId;
  final bool perpetual;
  final Set<String> featureIds;

  /// Base64URL SHA-256 of the device's complete Android Keystore SPKI DER key.
  final String devicePublicKeySha256;

  /// Issuer-side request/ledger correlation only; not a client pending-request match.
  final String requestId;

  /// Informational UTC timestamp; never an expiry or offline clock gate.
  final DateTime issuedAt;
  final String issuerKeyId;

  Set<String> get knownFeatureIds => Set<String>.unmodifiable(
        featureIds.intersection(ProfessionalEditionCatalog.knownFeatureIds),
      );

  Set<String> get unknownFeatureIds => Set<String>.unmodifiable(
        featureIds.difference(ProfessionalEditionCatalog.knownFeatureIds),
      );

  Set<String> get knownButNotAllowedFeatureIds => Set<String>.unmodifiable(
        knownFeatureIds.difference(
          ProfessionalEditionCatalog.allowedFeatureIdsForRevision(
            protocolRevision,
          ),
        ),
      );

  Set<String> get knownButNotEnforcedFeatureIds => Set<String>.unmodifiable(
        protocolRevision == 1
            ? const <String>{}
            : featureIds
                .intersection(
                  ProfessionalEditionCatalog.allowedFeatureIdsForRevision(
                    protocolRevision,
                  ),
                )
                .difference(ProfessionalEditionCatalog.enforcedFeatureIds),
      );

  Set<String> get unsupportedFeatureIds => Set<String>.unmodifiable({
        ...unknownFeatureIds,
        ...knownButNotAllowedFeatureIds,
        ...knownButNotEnforcedFeatureIds,
      });

  /// Effective runtime entitlement. Historical revision-1 claims are OR-mapped
  /// to this one bit; revision-2 accepts only the canonical ai_access claim.
  bool get grantsAiAccess {
    switch (protocolRevision) {
      case 1:
        return featureIds
            .intersection(ProfessionalEditionCatalog.legacyAiFeatureIds)
            .isNotEmpty;
      case 2:
        return featureIds.contains(LicenseFeature.aiAccess.id);
      default:
        return false;
    }
  }

  /// Kept as a one-element projection for protocol diagnostics only.
  Set<String> get grantedFeatureIds => grantsAiAccess
      ? const <String>{'ai_access'}
      : const <String>{};

  bool grants(LicenseFeature feature) =>
      feature == LicenseFeature.aiAccess && grantsAiAccess;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema_version': schemaVersion,
        'license_id': licenseId,
        'order_id': orderId,
        'product_id': productId,
        'protocol_revision': protocolRevision,
        'app_id': appId,
        'perpetual': perpetual,
        'features': featureIds.toList()..sort(),
        'device_public_key_sha256': devicePublicKeySha256,
        'request_id': requestId,
        'issued_at': issuedAt.toUtc().toIso8601String(),
        'issuer_key_id': issuerKeyId,
      };

  factory LicensePayload.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('License payload must be a JSON object.');
    }
    final json = Map<String, Object?>.from(value);
    const allowedFields = <String>{
      'schema_version',
      'license_id',
      'order_id',
      'product_id',
      'protocol_revision',
      'app_id',
      'perpetual',
      'features',
      'device_public_key_sha256',
      'request_id',
      'issued_at',
      'issuer_key_id',
    };
    if (json.keys.any((key) => !allowedFields.contains(key))) {
      throw const FormatException('License payload contains unsupported fields.');
    }

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
          result != result.trim() ||
          result.length > maxLength) {
        throw FormatException('Invalid string field: $key');
      }
      return result;
    }

    final schemaVersion = requiredInt('schema_version');
    final licenseId = requiredString('license_id', maxLength: 128);
    final orderId = requiredString('order_id', maxLength: 80);
    final productId = requiredString('product_id', maxLength: 80);
    final protocolRevision = requiredInt('protocol_revision');
    final appId = requiredString('app_id', maxLength: 160);
    if (json['perpetual'] != true) {
      throw const FormatException('Only perpetual licenses are supported.');
    }

    final rawFeatures = json['features'];
    if (rawFeatures is! List ||
        rawFeatures.isEmpty ||
        rawFeatures.length > 32) {
      throw const FormatException('Invalid license feature list.');
    }
    final featureIds = <String>{};
    var previousFeature = '';
    for (final feature in rawFeatures) {
      if (feature is! String ||
          !RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(feature) ||
          !featureIds.add(feature)) {
        throw const FormatException('Invalid or duplicate license feature.');
      }
      if (previousFeature.isNotEmpty && previousFeature.compareTo(feature) >= 0) {
        throw const FormatException('License features must be sorted.');
      }
      previousFeature = feature;
    }

    final devicePublicKeySha256 = requiredString(
      'device_public_key_sha256',
      maxLength: 64,
    );
    if (!_isSha256Base64Url(devicePublicKeySha256)) {
      throw const FormatException('Invalid device public-key fingerprint.');
    }

    final requestId = requiredString('request_id', maxLength: 64);
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(requestId)) {
      throw const FormatException('Invalid canonical request id.');
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
      protocolRevision: protocolRevision,
      appId: appId,
      perpetual: true,
      featureIds: Set<String>.unmodifiable(featureIds),
      devicePublicKeySha256: devicePublicKeySha256,
      requestId: requestId,
      issuedAt: issuedAt,
      issuerKeyId: issuerKeyId,
    );
  }

  static bool _isSha256Base64Url(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) return false;
    try {
      final normalized = value.padRight(
        value.length + ((4 - value.length % 4) % 4),
        '=',
      );
      return base64Url.decode(normalized).length == 32;
    } on FormatException {
      return false;
    }
  }
}
