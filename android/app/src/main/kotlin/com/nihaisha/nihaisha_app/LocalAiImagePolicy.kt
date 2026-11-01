package com.nihaisha.nihaisha_app

/**
 * Bounds-only image validation before passing a cached image to LiteRT-LM.
 * The caller must first enforce the canonical cache path and file-size limit.
 */
internal object LocalAiImagePolicy {
    const val MIN_SHORT_EDGE_PX = 480
    const val MAX_LONG_EDGE_PX = 1600

    fun validationError(width: Int, height: Int): String? {
        if (width <= 0 || height <= 0) {
            return "照片格式无法识别，请重新拍摄"
        }
        if (minOf(width, height) < MIN_SHORT_EDGE_PX) {
            return "照片分辨率不足，短边至少需要 480 像素"
        }
        if (maxOf(width, height) > MAX_LONG_EDGE_PX) {
            return "照片尺寸超过 1600 像素，请重新拍摄"
        }
        return null
    }
}
