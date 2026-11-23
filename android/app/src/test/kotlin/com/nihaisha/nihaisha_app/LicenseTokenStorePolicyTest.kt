package com.nihaisha.nihaisha_app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LicenseTokenStorePolicyTest {
    @Test
    fun acceptsOnlyCompleteCompactLicenseTokenEnvelopes() {
        assertTrue(LicenseTokenStorePolicy.isValidStoredToken("YANJI1.YWJj.ZGVm"))
        assertFalse(LicenseTokenStorePolicy.isValidStoredToken("YANJIR1.YWJj.ZGVm"))
        assertFalse(LicenseTokenStorePolicy.isValidStoredToken("YANJI1.YWJj"))
        assertFalse(LicenseTokenStorePolicy.isValidStoredToken(" YANJI1.YWJj.ZGVm "))
        assertFalse(LicenseTokenStorePolicy.isValidStoredToken("YANJI1.a+.b"))
        assertFalse(LicenseTokenStorePolicy.isValidStoredToken(""))
    }

    @Test
    fun enforcesProtocolTokenByteLimit() {
        val oversized = "YANJI1." + "A".repeat(LicenseTokenStorePolicy.MAX_TOKEN_BYTES) + ".B"
        assertFalse(LicenseTokenStorePolicy.isValidStoredToken(oversized))
        assertFalse(
            LicenseTokenStorePolicy.isValidStoredTokenBytes(
                ByteArray(LicenseTokenStorePolicy.MAX_TOKEN_BYTES + 1)
            )
        )
        assertTrue(
            LicenseTokenStorePolicy.isValidStoredTokenBytes(
                ByteArray(LicenseTokenStorePolicy.MAX_TOKEN_BYTES)
            )
        )
    }
}
