package dev.abdeldjalilchougui.bluetooth_spp

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build

/** Android-dependent helpers shared by the plugin and its stream handlers. */
@SuppressLint("MissingPermission")
internal object Devices {
    /** Serialises a device. Fields that need a missing permission become null. */
    fun toMap(device: BluetoothDevice): HashMap<String, Any?> = hashMapOf(
        "address" to device.address,
        "name" to safe { device.name },
        "type" to safe { device.type },
        "bondState" to safe { device.bondState },
        "deviceClass" to safe { device.bluetoothClass?.deviceClass },
    )

    private inline fun <T> safe(block: () -> T): T? = try {
        block()
    } catch (_: SecurityException) {
        null
    }

    @Suppress("DEPRECATION")
    fun deviceExtra(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

    /** Registers a receiver for Bluetooth broadcasts (see [ReceiverFlags]). */
    fun register(context: Context, receiver: BroadcastReceiver, filter: IntentFilter) {
        val flags = ReceiverFlags.forBluetoothBroadcasts(Build.VERSION.SDK_INT)
        if (flags != null) {
            context.registerReceiver(receiver, filter, flags)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    fun unregister(context: Context, receiver: BroadcastReceiver) {
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // Not registered.
        }
    }

    fun isGranted(context: Context, permission: String): Boolean =
        Build.VERSION.SDK_INT < 23 || context.checkSelfPermission(permission) == android.content.pm.PackageManager.PERMISSION_GRANTED
}
