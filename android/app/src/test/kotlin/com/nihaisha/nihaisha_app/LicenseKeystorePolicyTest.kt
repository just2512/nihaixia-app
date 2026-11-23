package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LicenseKeystorePolicyTest {
    @Test
    fun strongBoxIsAttemptedOnlyOnApi28AndAbove() {
        assertFalse(LicenseKeystorePolicy.shouldAttemptStrongBox(24))
        assertFalse(LicenseKeystorePolicy.shouldAttemptStrongBox(27))
        assertTrue(LicenseKeystorePolicy.shouldAttemptStrongBox(28))
        assertTrue(LicenseKeystorePolicy.shouldAttemptStrongBox(35))
    }

    @Test
    fun modernSecurityLevelsAreMappedWithoutGuessingUnknownValues() {
        assertEquals(
            LicenseKeystorePolicy.SOFTWARE,
            LicenseKeystorePolicy.securityLevelForModernApi(0, 0, 1, 2)
        )
        assertEquals(
            LicenseKeystorePolicy.TRUSTED_ENVIRONMENT,
            LicenseKeystorePolicy.securityLevelForModernApi(1, 0, 1, 2)
        )
        assertEquals(
            LicenseKeystorePolicy.STRONGBOX,
            LicenseKeystorePolicy.securityLevelForModernApi(2, 0, 1, 2)
        )
        assertEquals(
            LicenseKeystorePolicy.UNKNOWN,
            LicenseKeystorePolicy.securityLevelForModernApi(99, 0, 1, 2)
        )
    }

    @Test
    fun legacyApisDoNotClaimToDistinguishTeeFromStrongBox() {
        assertEquals(
            LicenseKeystorePolicy.SOFTWARE,
            LicenseKeystorePolicy.securityLevelForLegacyApi(false)
        )
        assertEquals(
            LicenseKeystorePolicy.UNKNOWN,
            LicenseKeystorePolicy.securityLevelForLegacyApi(true)
        )
    }

    @Test
    fun activationPayloadMustBeAnUnpaddedBase64UrlSegment() {
        assertTrue(LicenseKeystorePolicy.isValidActivationPayloadSegment("YWJjZA"))
        assertFalse(LicenseKeystorePolicy.isValidActivationPayloadSegment(""))
        assertFalse(LicenseKeystorePolicy.isValidActivationPayloadSegment(null))
        assertFalse(LicenseKeystorePolicy.isValidActivationPayloadSegment("YWJjZA=="))
        assertFalse(LicenseKeystorePolicy.isValidActivationPayloadSegment("abc+def"))
        assertFalse(LicenseKeystorePolicy.isValidActivationPayloadSegment("abc/def"))
        assertFalse(LicenseKeystorePolicy.isValidActivationPayloadSegment("a"))
        assertFalse(
            LicenseKeystorePolicy.isValidActivationPayloadSegment("X".repeat(8193))
        )
    }
}
