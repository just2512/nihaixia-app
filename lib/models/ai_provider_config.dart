import '../utils/ai_model_config_validation.dart';

/// A user-defined remote model provider connection.
///
/// Secrets are never represented by this DTO. [credentialRef] is only an
/// opaque reference owned by the platform Credential Vault.
class AiProviderConfig {
  AiProviderConfig({
    required this.providerId,
    required this.displayName,
    required this.protocolAdapterId,
    required this.baseUrl,
    this.credentialRef,
    this.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.configSchemaVersion = 1,
  })  : createdAt = (createdAt ?? DateTime.now()).toUtc(),
        updatedAt = (updatedAt ?? DateTime.now()).toUtc() {
    requireNonEmpty(providerId, 'AI_PROVIDER_ID_REQUIRED');
    requireTrimmedNonEmpty(displayName, 'AI_PROVIDER_DISPLAY_NAME_INVALID');
    requireTrimmedNonEmpty(protocolAdapterId, 'AI_PROVIDER_PROTOCOL_REQUIRED');
    validateHttpsBaseUrl(baseUrl);
    if (credentialRef != null) {
      requireTrimmedNonEmpty(
        credentialRef!,
        'AI_PROVIDER_CREDENTIAL_REFERENCE_INVALID',
      );
    }
    if (configSchemaVersion != 1) {
      throw ArgumentError('AI_PROVIDER_SCHEMA_VERSION_UNSUPPORTED');
    }
  }

  final String providerId;
  final String displayName;
  final String protocolAdapterId;
  final String baseUrl;
  final String? credentialRef;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int configSchemaVersion;

  Map<String, Object?> toDatabaseRow() => {
        'provider_id': providerId,
        'display_name': displayName,
        'protocol_adapter_id': protocolAdapterId,
        'base_url': baseUrl,
        'credential_ref': credentialRef,
        'enabled': enabled ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'config_schema_version': configSchemaVersion,
      };

  factory AiProviderConfig.fromDatabaseRow(Map<String, Object?> row) =>
      AiProviderConfig(
        providerId: row['provider_id'] as String,
        displayName: row['display_name'] as String,
        protocolAdapterId: row['protocol_adapter_id'] as String,
        baseUrl: row['base_url'] as String,
        credentialRef: row['credential_ref'] as String?,
        enabled: row['enabled'] == 1,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        configSchemaVersion: row['config_schema_version'] as int,
      );
}
