package dev.abdeldjalilchougui.bluetooth_spp

/** A slice of a byte array. */
internal data class Chunk(val offset: Int, val length: Int)

/** Splits a write into slices no larger than a chunk size. */
internal object ByteChunker {
    fun chunks(total: Int, chunkSize: Int): List<Chunk> {
        require(total >= 0) { "total must be >= 0" }
        require(chunkSize > 0) { "chunkSize must be > 0" }
        val out = ArrayList<Chunk>((total + chunkSize - 1) / chunkSize)
        var offset = 0
        while (offset < total) {
            val len = minOf(chunkSize, total - offset)
            out.add(Chunk(offset, len))
            offset += len
        }
        return out
    }
}
