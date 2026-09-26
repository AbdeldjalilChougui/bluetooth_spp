package dev.abdeldjalilchougui.bluetooth_spp

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class ByteChunkerTest {
    @Test
    fun emptyInputHasNoChunks() {
        assertEquals(emptyList(), ByteChunker.chunks(0, 4))
    }

    @Test
    fun smallerThanChunkIsOneChunk() {
        assertEquals(listOf(Chunk(0, 3)), ByteChunker.chunks(3, 4))
    }

    @Test
    fun exactMultiple() {
        assertEquals(listOf(Chunk(0, 4), Chunk(4, 4)), ByteChunker.chunks(8, 4))
    }

    @Test
    fun remainderIsLastChunk() {
        assertEquals(listOf(Chunk(0, 4), Chunk(4, 4), Chunk(8, 2)), ByteChunker.chunks(10, 4))
    }

    @Test
    fun chunksCoverInputWithoutGaps() {
        val chunks = ByteChunker.chunks(1000, 7)
        var next = 0
        for (c in chunks) {
            assertEquals(next, c.offset)
            next += c.length
        }
        assertEquals(1000, next)
    }

    @Test
    fun rejectsBadArguments() {
        assertFailsWith<IllegalArgumentException> { ByteChunker.chunks(-1, 4) }
        assertFailsWith<IllegalArgumentException> { ByteChunker.chunks(4, 0) }
    }
}
