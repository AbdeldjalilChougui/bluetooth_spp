package dev.abdeldjalilchougui.bluetooth_spp

/** Which runtime permissions Bluetooth Classic needs on a given API level. */
internal object PermissionPolicy {
    const val CONNECT = "android.permission.BLUETOOTH_CONNECT"
    const val SCAN = "android.permission.BLUETOOTH_SCAN"
    const val FINE = "android.permission.ACCESS_FINE_LOCATION"
    const val COARSE = "android.permission.ACCESS_COARSE_LOCATION"

    /** Runtime permissions for bonded devices, connect, bond and enable. */
    fun connect(sdk: Int): List<String> = if (sdk >= 31) listOf(CONNECT) else emptyList()

    /** Runtime permissions for discovery. */
    fun scan(sdk: Int): List<String> = when {
        sdk >= 31 -> listOf(SCAN)
        sdk >= 29 -> listOf(FINE)
        sdk >= 23 -> listOf(COARSE)
        else -> emptyList()
    }

    /** True if every permission is granted; fine location satisfies coarse. */
    fun granted(permissions: List<String>, isGranted: (String) -> Boolean): Boolean =
        permissions.all { isGranted(it) || (it == COARSE && isGranted(FINE)) }
}
