package com.nihaisha.nihaisha_app

import java.io.File
import java.io.RandomAccessFile

/** Validates the PCM/WAVE contract expected by the local audio path. */
internal object LocalAiWavPolicy {
    private const val MAX_DURATION_SECONDS = 30L
    private const val EXPECTED_SAMPLE_RATE = 16_000L
    private const val EXPECTED_BYTE_RATE = 32_000L
    private const val EXPECTED_BLOCK_ALIGN = 2
    private const val EXPECTED_BITS_PER_SAMPLE = 16
    private const val INVALID_MESSAGE =
        "录音格式无效，必须为 16 kHz、单声道、16-bit PCM WAV，且时长不超过 30 秒"

    private data class Format(
        val encoding: Int,
        val channels: Int,
        val sampleRate: Long,
        val byteRate: Long,
        val blockAlign: Int,
        val bitsPerSample: Int
    )

    fun validationError(file: File): String? {
        return try {
            RandomAccessFile(file, "r").use { input ->
                val fileLength = input.length()
                if (fileLength < 44L || readFourCc(input) != "RIFF") {
                    return INVALID_MESSAGE
                }

                val riffEnd = readUInt32LittleEndian(input) + 8L
                if (readFourCc(input) != "WAVE" || riffEnd < 44L || riffEnd > fileLength) {
                    return INVALID_MESSAGE
                }

                var offset = 12L
                var format: Format? = null
                var audioDataBytes: Long? = null
                while (offset + 8L <= riffEnd) {
                    input.seek(offset)
                    val chunkId = readFourCc(input)
                    val chunkSize = readUInt32LittleEndian(input)
                    val chunkStart = offset + 8L
                    val chunkEnd = chunkStart + chunkSize
                    if (chunkEnd < chunkStart || chunkEnd > riffEnd || chunkEnd > fileLength) {
                        return INVALID_MESSAGE
                    }

                    when (chunkId) {
                        "fmt " -> {
                            if (format != null || chunkSize < 16L) return INVALID_MESSAGE
                            format = Format(
                                encoding = readUInt16LittleEndian(input),
                                channels = readUInt16LittleEndian(input),
                                sampleRate = readUInt32LittleEndian(input),
                                byteRate = readUInt32LittleEndian(input),
                                blockAlign = readUInt16LittleEndian(input),
                                bitsPerSample = readUInt16LittleEndian(input)
                            )
                        }
                        "data" -> {
                            if (audioDataBytes != null) return INVALID_MESSAGE
                            audioDataBytes = chunkSize
                        }
                    }

                    val nextOffset = chunkEnd + (chunkSize and 1L)
                    if (nextOffset > riffEnd) return INVALID_MESSAGE
                    offset = nextOffset
                }

                // Every byte declared inside the RIFF container must belong to a complete chunk.
                // A dangling 1-7 byte tail is a truncated chunk header, not harmless padding.
                if (offset != riffEnd) return INVALID_MESSAGE

                val parsedFormat = format ?: return INVALID_MESSAGE
                val dataBytes = audioDataBytes ?: return INVALID_MESSAGE
                if (
                    parsedFormat.encoding != 1 ||
                    parsedFormat.channels != 1 ||
                    parsedFormat.sampleRate != EXPECTED_SAMPLE_RATE ||
                    parsedFormat.byteRate != EXPECTED_BYTE_RATE ||
                    parsedFormat.blockAlign != EXPECTED_BLOCK_ALIGN ||
                    parsedFormat.bitsPerSample != EXPECTED_BITS_PER_SAMPLE ||
                    dataBytes <= 0L ||
                    dataBytes % EXPECTED_BLOCK_ALIGN != 0L ||
                    dataBytes > EXPECTED_BYTE_RATE * MAX_DURATION_SECONDS
                ) {
                    return INVALID_MESSAGE
                }
                null
            }
        } catch (_: Exception) {
            INVALID_MESSAGE
        }
    }

    private fun readFourCc(input: RandomAccessFile): String {
        val bytes = ByteArray(4)
        input.readFully(bytes)
        return String(bytes, Charsets.US_ASCII)
    }

    private fun readUInt16LittleEndian(input: RandomAccessFile): Int {
        val low = input.readUnsignedByte()
        val high = input.readUnsignedByte()
        return low or (high shl 8)
    }

    private fun readUInt32LittleEndian(input: RandomAccessFile): Long {
        val b0 = input.readUnsignedByte().toLong()
        val b1 = input.readUnsignedByte().toLong()
        val b2 = input.readUnsignedByte().toLong()
        val b3 = input.readUnsignedByte().toLong()
        return b0 or (b1 shl 8) or (b2 shl 16) or (b3 shl 24)
    }
}
