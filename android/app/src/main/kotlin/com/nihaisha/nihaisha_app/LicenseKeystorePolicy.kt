package com.nihaisha.nihaisha_app

/**
 * Pure policy used by the Android Keystore adapter.
 *
 * API 24-30 exposes only isInsideSecureHardware(), which cannot distinguish
 * StrongBox from TEE. In that range a hardware-backed key is therefore
 * reported as UNKNOWN rather than overstating its protection level.
 */
internal object LicenseKeystorePolicy {
    const val SOFTWARE = "SOFTWARE"
    const val TRUSTED_ENVIRONMENT = "TRUSTED_ENVIRONMENT"
    const val STRONGBOX = "STRONGBOX"
    const val UNKNOWN = "UNKNOWN"

    fun shouldAttemptStrongBox(apiLevel: Int, strongBoxApiLevel: Int = 28): Boolean =
        apiLevel >= strongBoxApiLevel

    fun securityLevelForModernApi(
        securityLevel: Int,
        softwareLevel: Int,
        trustedEnvironmentLevel: Int,
        strongBoxLevel: Int
    ): String = when (securityLevel) {
        softwareLevel -> SOFTWARE
        trustedEnvironmentLevel -> TRUSTED_ENVIRONMENT
        strongBoxLevel -> STRONGBOX
        else -> UNKNOWN
    }

    fun securityLevelForLegacyApi(isInsideSecureHardware: Boolean): String =
        if (isInsideSecureHardware) UNKNOWN else SOFTWARE

    fun isValidActivationPayloadSegment(value: String?): Boolean {
        if (value.isNullOrEmpty() || value.length > 8192 || value.length % 4 == 1) {
            return false
        }
        return value.matches(Regex("^[A-Za-z0-9_-]+$"))
    }
}
