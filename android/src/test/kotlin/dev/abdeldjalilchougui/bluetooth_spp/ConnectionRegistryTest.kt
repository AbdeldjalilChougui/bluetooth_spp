package dev.abdeldjalilchougui.bluetooth_spp

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

internal class ConnectionRegistryTest {
    @Test
    fun addGetRemove() {
        val r = ConnectionRegistry<String>()
        r.add("a", "conn-a")
        r.add("b", "conn-b")
        assertEquals(2, r.size)
        assertSame("conn-a", r.get("a"))
        assertEquals(setOf("a", "b"), r.ids())
        assertEquals("conn-a", r.remove("a"))
        assertNull(r.get("a"))
        assertNull(r.remove("a"))
        assertEquals(1, r.size)
    }

    @Test
    fun duplicateIdIsRejected() {
        val r = ConnectionRegistry<String>()
        r.add("a", "one")
        assertFailsWith<IllegalStateException> { r.add("a", "two") }
        assertEquals("one", r.get("a"))
    }

    @Test
    fun reserveBlocksIdUntilReleased() {
        val r = ConnectionRegistry<String>()
        assertTrue(r.reserve("a"))
        assertEquals(false, r.reserve("a"))
        assertNull(r.get("a"))
        r.release("a")
        assertTrue(r.reserve("a"))
        r.add("a", "x")
        assertEquals("x", r.get("a"))
        assertEquals(false, r.reserve("a"))
    }

    @Test
    fun drainRemovesEverything() {
        val r = ConnectionRegistry<Int>()
        r.add("a", 1)
        r.add("b", 2)
        r.reserve("c")
        assertEquals(listOf(1, 2), r.drain().sorted())
        assertEquals(0, r.size)
        assertTrue(r.ids().isEmpty())
        assertTrue(r.reserve("c"))
    }

    @Test
    fun concurrentAddsAreAllKept() {
        val r = ConnectionRegistry<Int>()
        val pool = Executors.newFixedThreadPool(8)
        val done = CountDownLatch(200)
        repeat(200) { i -> pool.execute { r.add("id$i", i); done.countDown() } }
        assertTrue(done.await(5, TimeUnit.SECONDS))
        pool.shutdown()
        assertEquals(200, r.size)
    }
}
