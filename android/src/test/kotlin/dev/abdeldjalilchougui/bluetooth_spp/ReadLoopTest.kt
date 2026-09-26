package dev.abdeldjalilchougui.bluetooth_spp

import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

internal class ReadLoopTest {
    @Test
    fun emitsCopiesOfEachReadAndEndsCleanly() {
        val chunks = mutableListOf<List<Byte>>()
        var ended = false
        var endError: IOException? = null
        ReadLoop(ByteArrayInputStream(ByteArray(10) { it.toByte() }), 4, { chunks.add(it.toList()) }) {
            ended = true
            endError = it
        }.run()
        assertEquals((0 until 10).map { it.toByte() }, chunks.flatten())
        assertTrue(chunks.all { it.size <= 4 })
        assertTrue(ended)
        assertNull(endError)
    }

    @Test
    fun reportsIoErrorAsEnd() {
        val failure = IOException("bt socket closed, read return: -1")
        val failing = object : InputStream() {
            override fun read(): Int = throw failure
            override fun read(b: ByteArray, off: Int, len: Int): Int = throw failure
        }
        var endError: IOException? = null
        ReadLoop(failing, 8, {}) { endError = it }.run()
        assertSame(failure, endError)
    }

    @Test
    fun deliversDataAsItArrivesOnAThread() {
        val out = PipedOutputStream()
        val input = PipedInputStream(out)
        val received = Collections.synchronizedList(mutableListOf<Byte>())
        val gotFirst = CountDownLatch(1)
        val ended = CountDownLatch(1)
        val thread = Thread(ReadLoop(input, 16, { received.addAll(it.toList()); gotFirst.countDown() }) { ended.countDown() })
        thread.start()
        out.write("41 0C".toByteArray())
        out.flush()
        assertTrue(gotFirst.await(5, TimeUnit.SECONDS))
        out.write("\r>".toByteArray())
        out.close()
        assertTrue(ended.await(5, TimeUnit.SECONDS))
        assertEquals("41 0C\r>", String(received.toByteArray()))
    }

    @Test
    fun stopSuppressesFurtherCallbacks() {
        val loop = ReadLoop(ByteArrayInputStream(byteArrayOf(1, 2, 3)), 1, { throw AssertionError("no data after stop") }) {
            throw AssertionError("no end after stop")
        }
        loop.stop()
        loop.run()
    }
}
