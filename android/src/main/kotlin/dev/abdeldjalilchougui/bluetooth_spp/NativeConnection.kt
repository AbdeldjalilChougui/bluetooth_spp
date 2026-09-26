package dev.abdeldjalilchougui.bluetooth_spp

import android.bluetooth.BluetoothSocket
import java.io.IOException
import java.util.concurrent.Executors

/**
 * An open RFCOMM socket with a dedicated reader thread and a serial writer
 * thread. Nothing here runs on the Android main thread.
 */
internal class NativeConnection(
    val id: String,
    private val socket: BluetoothSocket,
    onData: (ByteArray) -> Unit,
    onEnd: (IOException?) -> Unit,
) {
    private val writer = Executors.newSingleThreadExecutor { r -> Thread(r, "bluetooth_spp-write-$id") }
    private val queue = WriteQueue(OutputStreamSink(socket.outputStream), WRITE_CHUNK_SIZE, writer)
    private val loop = ReadLoop(socket.inputStream, READ_BUFFER_SIZE, onData, onEnd)
    private val reader = Thread(loop, "bluetooth_spp-read-$id").apply { isDaemon = true }

    fun start() = reader.start()

    fun write(bytes: ByteArray, callback: (Throwable?) -> Unit) = queue.enqueue(bytes, callback)

    /** Stops callbacks, rejects queued writes and closes the socket, which unblocks the reader. */
    fun close() {
        loop.stop()
        queue.close()
        try {
            socket.close()
        } catch (_: IOException) {
        }
        writer.shutdown()
    }

    companion object {
        const val READ_BUFFER_SIZE = 1024
        const val WRITE_CHUNK_SIZE = 512
    }
}
