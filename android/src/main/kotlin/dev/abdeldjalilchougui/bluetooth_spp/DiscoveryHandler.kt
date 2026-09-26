package dev.abdeldjalilchougui.bluetooth_spp

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.plugin.common.EventChannel

/**
 * Listening starts discovery; results are streamed until
 * ACTION_DISCOVERY_FINISHED. Cancelling stops discovery.
 */
@SuppressLint("MissingPermission")
internal class DiscoveryHandler(
    private val context: Context,
    private val adapter: () -> BluetoothAdapter?,
) : EventChannel.StreamHandler {
    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop(cancel = true)
        val a = adapter()
        if (a == null) return events.error(ErrorCodes.BLUETOOTH_UNAVAILABLE, "No Bluetooth adapter", null)
        if (!a.isEnabled) return events.error(ErrorCodes.BLUETOOTH_DISABLED, "Bluetooth is off", null)
        val needed = PermissionPolicy.scan(Build.VERSION.SDK_INT)
        if (!PermissionPolicy.granted(needed) { Devices.isGranted(context, it) }) {
            return events.error(ErrorCodes.PERMISSION_DENIED, "Discovery needs $needed", null)
        }
        var started = false
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothAdapter.ACTION_DISCOVERY_STARTED -> started = true
                    BluetoothDevice.ACTION_FOUND -> {
                        val device = Devices.deviceExtra(intent) ?: return
                        val map = Devices.toMap(device)
                        map["rssi"] = DeviceCodes.rssiOrNull(
                            intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE),
                        )
                        events.success(map)
                    }
                    // A FINISHED from a discovery we cancelled can arrive before ours starts.
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> if (started) {
                        stop(cancel = false)
                        events.endOfStream()
                    }
                }
            }
        }
        receiver = r
        Devices.register(
            context,
            r,
            IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            },
        )
        try {
            if (a.isDiscovering) a.cancelDiscovery()
            if (!a.startDiscovery()) {
                stop(cancel = false)
                events.error(ErrorCodes.UNKNOWN, "startDiscovery() returned false (is location turned on?)", null)
            }
        } catch (e: SecurityException) {
            stop(cancel = false)
            events.error(ErrorCodes.PERMISSION_DENIED, ErrorCodes.messageOf(e), null)
        }
    }

    override fun onCancel(arguments: Any?) = stop(cancel = true)

    /** Unregisters the receiver and optionally cancels a running discovery. */
    fun stop(cancel: Boolean) {
        val r = receiver ?: return
        receiver = null
        Devices.unregister(context, r)
        if (cancel) {
            try {
                adapter()?.cancelDiscovery()
            } catch (_: SecurityException) {
            }
        }
    }
}
