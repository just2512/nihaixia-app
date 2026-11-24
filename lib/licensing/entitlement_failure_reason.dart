/// Stable diagnostics for permanent licensing and device-verification failures.
/// This enum reports why a single ai_access decision is not available; it is
/// not a list of independently purchasable Feature entitlements.
enum EntitlementFailureReason {
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
