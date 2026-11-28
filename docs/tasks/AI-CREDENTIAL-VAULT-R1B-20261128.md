# AI-CREDENTIAL-VAULT-R1B-20261128

## Task card

- **Task ID:** AI-CREDENTIAL-VAULT-R1B-20261128
- **Parent task:** AI-MODEL-CONFIG-20261128 (Stage 1, §14)
- **Owner:** Remote
- **Integration owner:** Integration (single public configuration PR; no second public PR)
- **Base SHA:** `ee1fc1e1aca47d489885893423e14ab6895ba738` (R1A branch HEAD; based on master `79324c44d638826d6e97cfb0951fc0cef35ec0f9`)
- **Work branch:** `remote/ai-credential-vault-r1b-20261128`
- **Status:** IN_PROGRESS / NOT MERGED

## Allowed paths

- `docs/tasks/AI-CREDENTIAL-VAULT-R1B-20261128.md` (this task card only; do not edit shared execution ledger)
- `pubspec.yaml`, `pubspec.lock` (only the secure-storage dependency and its lock resolution)
- `lib/services/ai_credential_vault.dart` (new single Vault abstraction/implementation)
- `test/ai_credential_vault_test.dart` (new focused contract tests)
- Android backup-rule XML only if required to exclude secure-storage key material from cloud/device backup; preserve all existing backup rules.

## Explicitly forbidden paths

- All R1A files: `lib/models/ai_provider_config.dart`, `lib/models/ai_model_config.dart`, `lib/models/ai_task_model_selection.dart`, `lib/models/ai_local_model_asset.dart`, `lib/utils/ai_model_config_validation.dart`, `lib/data/ai_model_config_repository.dart`, `lib/data/database_helper.dart`, and their existing tests.
- `docs/ai-layered-runtime-architecture.md`, `docs/ai-capability-audit.md`, `docs/ai-modernization-execution-ledger.md`, and `docs/local-real-device-acceptance-handoff.md`.
- License TokenStore / entitlement / Native E4B / model Gateway / Settings UI / vector index files.

## Scope

Implement only the Stage 1 Credential Vault boundary:
- Secrets are written/read/deleted through platform secure storage.
- SQLite and ProviderConfig retain only opaque `credentialRef`; no API key/secret/token plaintext is persisted in app database, logs, errors, analytics, or test snapshots.
- Credential references are random, opaque, versioned identifiers; malformed/unknown references fail closed.
- No silent fallback to plaintext, SharedPreferences, SQLite, files, or the license TokenStore.
- Storage errors propagate as typed failures; no empty-secret success and no automatic provider switch.
- Platform support must be explicit. Unsupported platform operations fail closed rather than falling back to weaker storage.

## Evidence and acceptance

1. Pin a compatible secure-storage dependency and record its license/platform/SDK constraints.
2. Tests cover create/read/delete, random reference uniqueness, malformed and unknown references, storage failure propagation, overwrite/rotation semantics, and ensure no plaintext secret is exposed through public values/errors.
3. Android backup rules exclude the plugin's encrypted preferences and wrapped-key material without disabling unrelated app backup or dropping existing exclusions.
4. Flutter analyze + focused tests + full Flutter regression + Branch validation + Android arm64/JVM + PR required gate + Fork License all SUCCESS on the final integrated PR HEAD; SKIPPED is not PASS.
5. Final integration is folded into the single Stage 1 configuration PR (#629); do not open a second public PR for R1B.
6. Find N2 KeyStore/backup/restore behavior remains LOCAL ONLY / UNKNOWN until the real device is tested. CI does not promote device status.

## Non-goals

- No Provider HTTP adapter, Gateway, AI global switch, model settings UI, automatic model discovery, cloud request, or actual secret rotation UI.
- No schema migration in this workstream; R1A owns configuration schema migration.
- No claim of hardware-backed/StrongBox behavior without device TRACE.

## Rollback

Remove the Vault integration only after any stored secrets have been explicitly migrated or deleted; never copy secrets into plaintext or SQLite during rollback. Preserve ProviderConfig rows and non-secret settings.
