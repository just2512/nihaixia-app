# AI-CREDENTIAL-VAULT-R1B-20261128

## Task card

- **Task ID:** AI-CREDENTIAL-VAULT-R1B-20261128
- **Parent task:** AI-MODEL-CONFIG-20261128 (Stage 1, §14)
- **Owner:** Remote
- **Integration owner:** Integration (single public configuration PR; no second public PR)
- **Base SHA:** `ee1fc1e1aca47d489885893423e14ab6895ba738` (R1A branch HEAD; based on master `79324c44d638826d6e97cfb0951fc0cef35ec0f9`)
- **Work branch:** `remote/ai-credential-vault-r1b-20261128`
- **Status:** IMPLEMENTED / MERGED INTO MASTER via PR #629 / POST-MERGE MASTER PUSH CI SUCCESS (`0fd7c29e0cc7b2347414483e6b17b5e4199e0e77`)

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
2. Tests cover create/read/exists/delete, random reference uniqueness, malformed and unknown references, empty stored values, storage read/write/delete failures, overwrite/rotation semantics, and ensure no plaintext secret is exposed through public values/errors.
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


## Implementation record (2026-11-28)

- Secure-storage dependency selected and pinned exactly to `flutter_secure_storage 10.3.4`; upstream license is BSD-3-Clause. Upstream package metadata requires Dart >=3.3.0 and Flutter >=3.19.0; this app declares Dart `^3.13.0`, Flutter `>=3.47.0`, and Android minSdk 24. The Windows federated implementation is locked to 4.1.0 (win32 5.15.0) to remain compatible with the existing share_plus 10.1.4 win32 constraint; do not upgrade that federated package unless the share_plus constraint is updated and tested.
- Runtime support is explicitly limited to Android and Windows. Production construction always uses the default platform secure-storage backend; arbitrary storage injection is exposed only through the analyzer-marked `AiCredentialVault.forTesting` factory. Web, Linux, macOS, iOS and other targets fail closed in the Vault constructor; no weaker fallback is provided.
- Android uses the dedicated namespace `nihaixia_ai_credentials_v1` and `resetOnError: false`. This avoids the plugin's destructive automatic reset when KeyStore access fails. The app backup rules exclude the namespace data preferences, namespaced configuration preferences and namespaced wrapped-key preferences from both cloud backup and device transfer.
- Windows uses the plugin's Windows implementation with DPAPI-protected encrypted local storage. This is not a claim of hardware-backed storage.
- Credential references use the versioned `aicred:v1:` prefix plus 256 bits from `Random.secure()`. Only opaque references are intended to leave the Vault.
- Rotation is an explicit overwrite under the existing reference; it does not introduce automatic provider switching or a settings UI. The Vault does not claim cross-platform transactional writes.
- Vault operations are serialized across instances within the Dart isolate. This compensates for the pinned Windows federated implementation version predating its upstream concurrent read/write fix; a cross-instance concurrency regression test guards the boundary.
- Focused tests cover create/read/exists/delete, random-reference uniqueness and collision handling, malformed/unknown references, injected read/write/delete failures with typed errors and no underlying exception leakage, empty stored values, explicit overwrite semantics, unsupported platforms, cross-Vault-instance operation serialization within one Dart isolate, and Android cloud-backup/device-transfer exclusions for all three namespaced SharedPreferences files. The Android KeyStore-loss branch is configured with `resetOnError: false` and remains a real-device UNKNOWN until Find N2 testing.
- **Previous candidate validation (historical; no longer sufficient for merge):** `a6b91223cd773047ac51ba84494c5ff2f96f4505` passed all five Stage 1 gates on 2026-11-28 (Branch validation, Flutter regression, Android arm64/JVM, PR required gate, and Fork License). Flutter regression reported 2,279 passed and 15 existing Yunqi oracle skips because the external fixture `D:\tools\yunqi_ref.json` is unavailable in GitHub CI. Android verification was arm64-only and 131 JVM tests passed with zero failures/errors/skips.
- **Final integrated PR HEAD validation:** `ba8807993e869c17c00ed687b9fc5d870624b43a` passed all five Stage 1 gates on the exact same SHA: Branch validation, Flutter regression, Android arm64/JVM, PR required gate, and Fork License. Changed-file tests: 37 passed. Flutter regression: 2,280 passed / 15 skipped because `D:\tools\yunqi_ref.json` was unavailable; those oracle tests remain MISSING/SKIPPED and are not reported as passes. Android arm64 APK contained only `arm64-v8a`; JVM tests were 131 passed, 0 failures, 0 errors, 0 skipped.
- **Post-merge master Push CI (2026-11-28):** Master SHA `0fd7c29e0cc7b2347414483e6b17b5e4199e0e77`; Push run `46159016032` completed SUCCESS. Flutter job `141021920486` SUCCESS (2,280 passed / 15 skipped for the missing external Yunqi oracle fixture); Android job `141024034283` SUCCESS (arm64-only APK, 131 JVM tests with 0 failures/errors/skips, backup manifest and signing-isolation checks passed). Fork License Push run `46159016036` / job `141021920468` SUCCESS. Branch validation and PR required gate were SKIPPED by the master Push workflow conditions and are not counted as PASS; the five PR gates had already passed on the exact pre-merge PR HEAD.
- **Merge commit:** `0fd7c29e0cc7b2347414483e6b17b5e4199e0e77` (Squash merge of PR #629). Cloud Stage 1 is merged and CI-verified; Find N2 KeyStore-loss/backup/restore, device transfer and old-APK upgrade remain LOCAL ONLY / UNKNOWN.
- Local Dart/Flutter execution on the user's workstation and Find N2 KeyStore-loss/backup/restore evidence remain UNKNOWN; no local/device PASS is asserted.


## Integration-owned follow-up (not Remote R1B scope)

The Integration-owned Fork inventory update is complete in PR #629: `.reuse/dep5`, `docs/fork-license-file-inventory.json`, and `docs/fork-license-file-inventory.md` include the task card, Vault service, and focused tests. The independent Fork License PR workflow passed on exact final integrated HEAD `ba8807993e869c17c00ed687b9fc5d870624b43a` (run `46157842103`); the post-merge master Push Fork License workflow also passed (run `46159016036`, job `141021920468`). This confirms inventory/boundary consistency; it does not independently establish legal copyright ownership or sublicensing title.
