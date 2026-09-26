package dev.abdeldjalilchougui.bluetooth_spp

import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException

/** Where a [WriteQueue] puts bytes. Implemented over a socket's OutputStream. */
internal interface ChunkSink {
    fun write(bytes: ByteArray, offset: Int, length: Int)
    fun flush()
}

internal class OutputStreamSink(private val out: OutputStream) : ChunkSink {
    override fun write(bytes: ByteArray, offset: Int, length: Int) = out.write(bytes, offset, length)
    override fun flush() = out.flush()
}

/** Thrown to callbacks of writes that were queued when the connection closed. */
internal class ClosedQueueException : IOException("Connection closed")

/**
 * Serial write queue. Each write is split into chunks, written and flushed on
 * [executor] (never the main thread); its callback runs once the bytes are
 * flushed (null) or failed (the exception). Order is preserved.
 */
internal class WriteQueue(
    private val sink: ChunkSink,
    private val chunkSize: Int,
    private val executor: ExecutorService,
) {
    @Volatile
    private var closed = false

    fun enqueue(bytes: ByteArray, callback: (Throwable?) -> Unit) {
        if (closed) {
            callback(ClosedQueueException())
            return
        }
        try {
            executor.execute { runWrite(bytes, callback) }
        } catch (e: RejectedExecutionException) {
            callback(ClosedQueueException())
        }
    }

    private fun runWrite(bytes: ByteArray, callback: (Throwable?) -> Unit) {
        if (closed) {
            callback(ClosedQueueException())
            return
        }
        val error = try {
            for (c in ByteChunker.chunks(bytes.size, chunkSize)) sink.write(bytes, c.offset, c.length)
            sink.flush()
            null
        } catch (t: Throwable) {
            t
        }
        callback(error)
    }

    /** Rejects queued and future writes. A write already in the sink may still complete. */
    fun close() {
        closed = true
    }
}
