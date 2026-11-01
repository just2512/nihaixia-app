package com.nihaisha.nihaisha_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalAiImagePolicyTest {
    @Test
    fun acceptsMinimumShortEdgeAndMaximumLongEdge() {
        assertNull(LocalAiImagePolicy.validationError(480, 1600))
        assertNull(LocalAiImagePolicy.validationError(1600, 480))
    }

    @Test
    fun acceptsSquareImageAtMinimumAndMaximumBoundaries() {
        assertNull(LocalAiImagePolicy.validationError(480, 480))
        assertNull(LocalAiImagePolicy.validationError(1600, 1600))
    }

    @Test
    fun rejectsShortEdgeBelowMinimum() {
        assertEquals(
            "照片分辨率不足，短边至少需要 480 像素",
            LocalAiImagePolicy.validationError(479, 1200)
        )
    }

    @Test
    fun rejectsLongEdgeAboveMaximum() {
        assertEquals(
            "照片尺寸超过 1600 像素，请重新拍摄",
            LocalAiImagePolicy.validationError(1601, 800)
        )
    }

    @Test
    fun rejectsUndecodableOrInvalidDimensions() {
        assertEquals("照片格式无法识别，请重新拍摄", LocalAiImagePolicy.validationError(-1, -1))
        assertEquals("照片格式无法识别，请重新拍摄", LocalAiImagePolicy.validationError(0, 800))
    }
}
