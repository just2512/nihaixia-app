package com.nihaisha.nihaisha_app

import java.io.ByteArrayOutputStream
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalAiWavPolicyTest {
    @Test
    fun acceptsValidSixteenKilohertzMonoPcmWaveAtThirtySecondLimit() {
        assertNull(LocalAiWavPolicy.validationError(createWaveFile(dataBytes = 960_000)))
    }

    @Test
    fun acceptsOddSizedAncillaryChunkWithRequiredPadding() {
        assertNull(LocalAiWavPolicy.validationError(createWaveFile(includeOddAncillaryChunk = true)))
    }

    @Test
    fun rejectsIncompleteTrailingChunkHeader() {
        assertEquals(
            INVALID_MESSAGE,
            LocalAiWavPolicy.validationError(
                createWaveFile(trailingRiffBytes = byteArrayOf(1, 2, 3, 4))
            )
        )
    }

    @Test
    fun rejectsWaveLongerThanThirtySeconds() {
        assertEquals(INVALID_MESSAGE, LocalAiWavPolicy.validationError(createWaveFile(dataBytes = 960_002)))
    }

    @Test
    fun rejectsUnsupportedEncodingChannelsSampleRateAndBitDepth() {
        val invalidFiles = listOf(
            createWaveFile(encoding = 3),
            createWaveFile(channels = 2, byteRate = 64_000, blockAlign = 4),
            createWaveFile(sampleRate = 44_100, byteRate = 88_200),
            createWaveFile(bitsPerSample = 8, byteRate = 16_000, blockAlign = 1)
        )
        for (file in invalidFiles) {
            assertEquals(INVALID_MESSAGE, LocalAiWavPolicy.validationError(file))
        }
    }

    @Test
    fun rejectsInvalidHeadersAndTruncatedChunks() {
        val invalidHeader = createWaveFile().apply {
            writeBytes(readBytes().also { it[0] = 'X'.code.toByte() })
        }
        val truncatedChunk = createWaveFile().apply {
            writeBytes(readBytes().also { bytes ->
                bytes[40] = 0xff.toByte()
                bytes[41] = 0xff.toByte()
                bytes[42] = 0xff.toByte()
                bytes[43] = 0x7f
            })
        }
        val shortFile = File.createTempFile("local-ai-short-", ".wav").apply {
            writeBytes(byteArrayOf(1, 2, 3, 4))
            deleteOnExit()
        }
        for (file in listOf(invalidHeader, truncatedChunk, shortFile)) {
            assertEquals(INVALID_MESSAGE, LocalAiWavPolicy.validationError(file))
        }
    }

    @Test
    fun rejectsMissingAudioData() {
        assertEquals(INVALID_MESSAGE, LocalAiWavPolicy.validationError(createWaveFile(dataBytes = 0)))
    }

    private fun createWaveFile(
        encoding: Int = 1,
        channels: Int = 1,
        sampleRate: Long = 16_000,
        byteRate: Long = 32_000,
        blockAlign: Int = 2,
        bitsPerSample: Int = 16,
        dataBytes: Int = 32_000,
        includeOddAncillaryChunk: Boolean = false,
        trailingRiffBytes: ByteArray = byteArrayOf()
    ): File {
        val output = ByteArrayOutputStream()
        output.writeAscii("RIFF")
        val ancillaryChunkBytes = if (includeOddAncillaryChunk) 12L else 0L
        output.writeUInt32LittleEndian(36L + dataBytes + ancillaryChunkBytes + trailingRiffBytes.size)
        output.writeAscii("WAVE")
        if (includeOddAncillaryChunk) {
            output.writeAscii("JUNK")
            output.writeUInt32LittleEndian(3)
            output.write(byteArrayOf(1, 2, 3))
            output.write(0) // RIFF chunks with odd payloads carry one padding byte.
        }
        output.writeAscii("fmt ")
        output.writeUInt32LittleEndian(16)
        output.writeUInt16LittleEndian(encoding)
        output.writeUInt16LittleEndian(channels)
        output.writeUInt32LittleEndian(sampleRate)
        output.writeUInt32LittleEndian(byteRate)
        output.writeUInt16LittleEndian(blockAlign)
        output.writeUInt16LittleEndian(bitsPerSample)
        output.writeAscii("data")
        output.writeUInt32LittleEndian(dataBytes.toLong())
        output.write(ByteArray(dataBytes))
        output.write(trailingRiffBytes)
        return File.createTempFile("local-ai-audio-", ".wav").apply {
            writeBytes(output.toByteArray())
            deleteOnExit()
        }
    }

    private fun ByteArrayOutputStream.writeAscii(value: String) {
        write(value.toByteArray(Charsets.US_ASCII))
    }

    private fun ByteArrayOutputStream.writeUInt16LittleEndian(value: Int) {
        write(value and 0xff)
        write((value ushr 8) and 0xff)
    }

    private fun ByteArrayOutputStream.writeUInt32LittleEndian(value: Long) {
        write((value and 0xff).toInt())
        write(((value ushr 8) and 0xff).toInt())
        write(((value ushr 16) and 0xff).toInt())
        write(((value ushr 24) and 0xff).toInt())
    }

    companion object {
        private const val INVALID_MESSAGE =
            "录音格式无效，必须为 16 kHz、单声道、16-bit PCM WAV，且时长不超过 30 秒"
    }
}
