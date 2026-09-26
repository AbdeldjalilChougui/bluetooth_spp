package dev.abdeldjalilchougui.bluetooth_spp

import java.io.IOException
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class WriteQueueTest {
    private val executor = Executors.newSingleThreadExecutor()

    @AfterTest
    fun tearDown() {
        executor.shutdownNow()
    }

    private class RecordingSink : ChunkSink {
        val log: MutableList<String> = Collections.synchronizedList(mutableListOf())
        val bytes = java.io.ByteArrayOutputStream()
        var failWith: IOException? = null
        var gate: CountDownLatch? = null

        override fun write(bytes: ByteArray, offset: Int, length: Int) {
            gate?.await(5, TimeUnit.SECONDS)
            failWith?.let { throw it }
            log.add("write:$length")
            synchronized(this.bytes) { this.bytes.write(bytes, offset, length) }
        }

        override fun flush() {
            log.add("flush")
        }
    }

    private fun awaitResult(queue: WriteQueue, data: ByteArray): Throwable? {
        val latch = CountDownLatch(1)
        var result: Throwable? = IllegalStateException("callback not called")
        queue.enqueue(data) { error ->
            result = error
            latch.countDown()
        }
        assertTrue(latch.await(5, TimeUnit.SECONDS), "callback timed out")
        return result
    }

    @Test
    fun writesInChunksThenFlushesBeforeCallback() {
        val sink = RecordingSink()
        val queue = WriteQueue(sink, 4, executor)
        assertNull(awaitResult(queue, ByteArray(10) { it.toByte() }))
        assertEquals(listOf("write:4", "write:4", "write:2", "flush"), sink.log.toList())
        assertEquals((0 until 10).map { it.toByte() }, sink.bytes.toByteArray().toList())
    }

    @Test
    fun preservesOrderAcrossManyWrites() {
        val sink = RecordingSink()
        val queue = WriteQueue(sink, 3, executor)
        val latch = CountDownLatch(50)
        val completions = Collections.synchronizedList(mutableListOf<Int>())
        repeat(50) { i ->
            queue.enqueue(byteArrayOf(i.toByte(), i.toByte())) { completions.add(i); latch.countDown() }
        }
        assertTrue(latch.await(5, TimeUnit.SECONDS))
        assertEquals((0 until 50).toList(), completions.toList())
        assertEquals((0 until 50).flatMap { listOf(it.toByte(), it.toByte()) }, sink.bytes.toByteArray().toList())
    }

    @Test
    fun sinkFailureIsReportedToThatWrite() {
        val sink = RecordingSink()
        sink.failWith = IOException("Broken pipe")
        val queue = WriteQueue(sink, 4, executor)
        val error = awaitResult(queue, byteArrayOf(1, 2, 3))
        assertIs<IOException>(error)
        assertEquals("Broken pipe", error.message)
    }

    @Test
    fun emptyWriteStillFlushes() {
        val sink = RecordingSink()
        val queue = WriteQueue(sink, 4, executor)
        assertNull(awaitResult(queue, ByteArray(0)))
        assertEquals(listOf("flush"), sink.log.toList())
    }

    @Test
    fun closeFailsPendingAndLaterWrites() {
        val sink = RecordingSink()
        val gate = CountDownLatch(1)
        sink.gate = gate
        val queue = WriteQueue(sink, 4, executor)
        val firstDone = CountDownLatch(1)
        var first: Throwable? = null
        queue.enqueue(byteArrayOf(1)) { first = it; firstDone.countDown() }
        val secondDone = CountDownLatch(1)
        var second: Throwable? = null
        queue.enqueue(byteArrayOf(2)) { second = it; secondDone.countDown() }
        queue.close()
        gate.countDown()
        assertTrue(firstDone.await(5, TimeUnit.SECONDS))
        assertTrue(secondDone.await(5, TimeUnit.SECONDS))
        // The in-flight write may finish, but the queued one must be rejected.
        assertIs<ClosedQueueException>(second)
        assertTrue(first == null || first is ClosedQueueException)
        assertIs<ClosedQueueException>(awaitResult(queue, byteArrayOf(3)))
    }
}
