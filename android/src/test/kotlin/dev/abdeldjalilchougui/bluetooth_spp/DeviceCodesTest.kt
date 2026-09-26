package dev.abdeldjalilchougui.bluetooth_spp

import kotlin.test.Test
import kotlin.test.assertEquals

internal class DeviceCodesTest {
    @Test
    fun rssiAbsentIsNull() {
        assertEquals(null, DeviceCodes.rssiOrNull(Short.MIN_VALUE))
        assertEquals(-67, DeviceCodes.rssiOrNull((-67).toShort()))
    }

    @Test
    fun normalizesAddress() {
        assertEquals("00:1D:A5:68:98:8B", DeviceCodes.normalizeAddress(" 00:1d:a5:68:98:8b "))
    }

    @Test
    fun validatesAddress() {
        assertEquals(true, DeviceCodes.isValidAddress("00:1D:A5:68:98:8B"))
        assertEquals(false, DeviceCodes.isValidAddress("00:1D:A5:68:98"))
        assertEquals(false, DeviceCodes.isValidAddress("00-1D-A5-68-98-8B"))
        assertEquals(false, DeviceCodes.isValidAddress("00:1D:A5:68:98:8G"))
    }
}
