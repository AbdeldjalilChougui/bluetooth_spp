package dev.abdeldjalilchougui.bluetooth_spp

import android.content.Context

/** `registerReceiver` flags for the Bluetooth broadcasts the plugin listens to. */
internal object ReceiverFlags {
    /**
     * API 33+: [Context.RECEIVER_EXPORTED]. Discovery and bond broadcasts
     * come from the Bluetooth app (uid 1002), which a not-exported receiver
     * does not accept; they are protected broadcasts, so no other app can
     * send them. Null (no flag) before API 33.
     */
    fun forBluetoothBroadcasts(sdk: Int): Int? = if (sdk >= 33) Context.RECEIVER_EXPORTED else null
}
