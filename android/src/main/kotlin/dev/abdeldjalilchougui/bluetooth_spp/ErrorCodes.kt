package dev.abdeldjalilchougui.bluetooth_spp

import java.io.IOException

/** Error codes shared with the Dart side, and the mapping from native exceptions. */
internal object ErrorCodes {
    const val BLUETOOTH_UNAVAILABLE = "bluetooth_unavailable"
    const val BLUETOOTH_DISABLED = "bluetooth_disabled"
    const val PERMISSION_DENIED = "permission_denied"
    const val INVALID_ARGUMENT = "invalid_argument"
    const val CONNECT_FAILED = "connect_failed"
    const val TIMEOUT = "timeout"
    const val NOT_CONNECTED = "not_connected"
    const val IO_ERROR = "io_error"
    const val ACTIVITY_UNAVAILABLE = "activity_unavailable"
    const val BUSY = "busy"
    const val UNKNOWN = "unknown"

    /** Maps a failure while opening a socket. [timedOut] is true when our watchdog closed it. */
    fun forConnect(t: Throwable, timedOut: Boolean): String = when (t) {
        is SecurityException -> PERMISSION_DENIED
        is IllegalArgumentException -> INVALID_ARGUMENT
        is IOException -> if (timedOut) TIMEOUT else CONNECT_FAILED
        // Reflection fallback failures (method missing or throwing).
        is ReflectiveOperationException -> if (timedOut) TIMEOUT else CONNECT_FAILED
        else -> UNKNOWN
    }

    /** Maps a failure on an open connection. */
    fun forIo(t: Throwable): String = when (t) {
        is SecurityException -> PERMISSION_DENIED
        is IllegalArgumentException -> INVALID_ARGUMENT
        is IOException -> IO_ERROR
        else -> UNKNOWN
    }

    fun messageOf(t: Throwable): String = t.message ?: t.javaClass.simpleName
}
