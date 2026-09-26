package dev.abdeldjalilchougui.bluetooth_spp

import java.io.IOException
import java.io.InputStream

/**
 * Blocking read loop meant for a dedicated thread. Each successful read is
 * delivered as a fresh copy. [onEnd] is called once with null at end of
 * stream, or with the IOException that stopped it, unless [stop] was called.
 */
internal class ReadLoop(
    private val input: InputStream,
    private val bufferSize: Int,
    private val onData: (ByteArray) -> Unit,
    private val onEnd: (IOException?) -> Unit,
) : Runnable {
    @Volatile
    private var stopped = false

    fun stop() {
        stopped = true
    }

    override fun run() {
        val buffer = ByteArray(bufferSize)
        var error: IOException? = null
        try {
            while (!stopped) {
                val n = input.read(buffer)
                if (n < 0) break
                if (n > 0 && !stopped) onData(buffer.copyOf(n))
            }
        } catch (e: IOException) {
            error = e
        }
        if (!stopped) onEnd(error)
    }
}
