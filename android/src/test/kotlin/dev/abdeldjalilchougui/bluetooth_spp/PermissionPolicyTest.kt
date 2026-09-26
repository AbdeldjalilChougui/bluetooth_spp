package dev.abdeldjalilchougui.bluetooth_spp

import kotlin.test.Test
import kotlin.test.assertEquals

internal class PermissionPolicyTest {
    @Test
    fun android12UsesNearbyDevicesPermissions() {
        assertEquals(listOf("android.permission.BLUETOOTH_CONNECT"), PermissionPolicy.connect(31))
        assertEquals(listOf("android.permission.BLUETOOTH_SCAN"), PermissionPolicy.scan(31))
        assertEquals(listOf("android.permission.BLUETOOTH_SCAN"), PermissionPolicy.scan(35))
    }

    @Test
    fun android10And11NeedFineLocationToScan() {
        assertEquals(emptyList(), PermissionPolicy.connect(30))
        assertEquals(listOf("android.permission.ACCESS_FINE_LOCATION"), PermissionPolicy.scan(29))
        assertEquals(listOf("android.permission.ACCESS_FINE_LOCATION"), PermissionPolicy.scan(30))
    }

    @Test
    fun android6To9NeedCoarseLocationToScan() {
        assertEquals(listOf("android.permission.ACCESS_COARSE_LOCATION"), PermissionPolicy.scan(23))
        assertEquals(listOf("android.permission.ACCESS_COARSE_LOCATION"), PermissionPolicy.scan(28))
    }

    @Test
    fun preMarshmallowNeedsNoRuntimePermission() {
        assertEquals(emptyList(), PermissionPolicy.connect(21))
        assertEquals(emptyList(), PermissionPolicy.scan(22))
    }

    @Test
    fun fineLocationAlsoSatisfiesCoarse() {
        assertEquals(true, PermissionPolicy.granted(listOf("android.permission.ACCESS_COARSE_LOCATION")) { it == "android.permission.ACCESS_FINE_LOCATION" })
        assertEquals(false, PermissionPolicy.granted(listOf("android.permission.BLUETOOTH_SCAN")) { false })
        assertEquals(true, PermissionPolicy.granted(emptyList()) { false })
    }
}
