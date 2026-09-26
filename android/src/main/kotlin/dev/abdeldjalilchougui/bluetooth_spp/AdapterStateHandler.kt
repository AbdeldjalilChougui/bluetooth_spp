package dev.abdeldjalilchougui.bluetooth_spp

import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.plugin.common.EventChannel

/** Streams BluetoothAdapter.STATE_* values, starting with the current one. */
internal class AdapterStateHandler(
    private val context: Context,
    private val adapter: () -> BluetoothAdapter?,
) : EventChannel.StreamHandler {
    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        dispose()
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                events.success(intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1))
            }
        }
        receiver = r
        Devices.register(context, r, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
        events.success(adapter()?.state ?: -1)
    }

    override fun onCancel(arguments: Any?) = dispose()

    fun dispose() {
        receiver?.let { Devices.unregister(context, it) }
        receiver = null
    }
}
