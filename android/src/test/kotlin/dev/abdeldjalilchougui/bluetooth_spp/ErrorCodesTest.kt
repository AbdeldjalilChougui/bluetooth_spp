package dev.abdeldjalilchougui.bluetooth_spp

import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals

internal class ErrorCodesTest {
    @Test
    fun connectSecurityExceptionIsPermissionDenied() {
        assertEquals(ErrorCodes.PERMISSION_DENIED, ErrorCodes.forConnect(SecurityException("Need BLUETOOTH_CONNECT"), false))
    }

    @Test
    fun connectIllegalArgumentIsInvalidArgument() {
        assertEquals(ErrorCodes.INVALID_ARGUMENT, ErrorCodes.forConnect(IllegalArgumentException("bad"), false))
    }

    @Test
    fun connectIoExceptionIsConnectFailed() {
        assertEquals(
            ErrorCodes.CONNECT_FAILED,
            ErrorCodes.forConnect(IOException("read failed, socket might closed or timeout, read ret: -1"), false),
        )
    }

    @Test
    fun connectIoExceptionAfterTimeoutIsTimeout() {
        assertEquals(ErrorCodes.TIMEOUT, ErrorCodes.forConnect(IOException("socket closed"), true))
    }

    @Test
    fun connectSecurityExceptionWinsOverTimeout() {
        assertEquals(ErrorCodes.PERMISSION_DENIED, ErrorCodes.forConnect(SecurityException("x"), true))
    }

    @Test
    fun connectReflectionFailureIsConnectFailed() {
        assertEquals(ErrorCodes.CONNECT_FAILED, ErrorCodes.forConnect(NoSuchMethodException("createRfcommSocket"), false))
    }

    @Test
    fun connectUnknownThrowableIsUnknown() {
        assertEquals(ErrorCodes.UNKNOWN, ErrorCodes.forConnect(IllegalStateException("?"), false))
    }

    @Test
    fun ioMapping() {
        assertEquals(ErrorCodes.IO_ERROR, ErrorCodes.forIo(IOException("Broken pipe")))
        assertEquals(ErrorCodes.PERMISSION_DENIED, ErrorCodes.forIo(SecurityException("x")))
        assertEquals(ErrorCodes.INVALID_ARGUMENT, ErrorCodes.forIo(IllegalArgumentException("x")))
        assertEquals(ErrorCodes.UNKNOWN, ErrorCodes.forIo(RuntimeException("x")))
    }

    @Test
    fun messageFallsBackToClassName() {
        assertEquals("boom", ErrorCodes.messageOf(IOException("boom")))
        assertEquals("IOException", ErrorCodes.messageOf(IOException()))
    }

    @Test
    fun codesAreStableStrings() {
        assertEquals(
            listOf(
                "bluetooth_unavailable", "bluetooth_disabled", "permission_denied", "invalid_argument",
                "connect_failed", "timeout", "not_connected", "io_error", "activity_unavailable", "busy", "unknown",
            ),
            listOf(
                ErrorCodes.BLUETOOTH_UNAVAILABLE, ErrorCodes.BLUETOOTH_DISABLED, ErrorCodes.PERMISSION_DENIED,
                ErrorCodes.INVALID_ARGUMENT, ErrorCodes.CONNECT_FAILED, ErrorCodes.TIMEOUT, ErrorCodes.NOT_CONNECTED,
                ErrorCodes.IO_ERROR, ErrorCodes.ACTIVITY_UNAVAILABLE, ErrorCodes.BUSY, ErrorCodes.UNKNOWN,
            ),
        )
    }
}
