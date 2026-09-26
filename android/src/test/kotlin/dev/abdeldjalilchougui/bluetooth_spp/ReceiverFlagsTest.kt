package dev.abdeldjalilchougui.bluetooth_spp

import android.content.Context
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class ReceiverFlagsTest {
    /**
     * ACTION_FOUND, ACTION_DISCOVERY_* and ACTION_BOND_STATE_CHANGED are sent
     * by the Bluetooth app (uid 1002), not by system_server. A receiver
     * registered with RECEIVER_NOT_EXPORTED never got them on an API 37
     * emulator, so discovery never ended and bond() would never complete.
     */
    @Test
    fun bluetoothReceiversAreExportedFromApi33() {
        assertEquals(Context.RECEIVER_EXPORTED, ReceiverFlags.forBluetoothBroadcasts(33))
        assertEquals(Context.RECEIVER_EXPORTED, ReceiverFlags.forBluetoothBroadcasts(37))
    }

    @Test
    fun noFlagBeforeApi33() {
        assertNull(ReceiverFlags.forBluetoothBroadcasts(32))
    }
}
