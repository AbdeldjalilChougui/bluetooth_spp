package dev.abdeldjalilchougui.bluetooth_spp

/** Small pure helpers for device data. */
internal object DeviceCodes {
    private val ADDRESS = Regex("^[0-9A-F]{2}(:[0-9A-F]{2}){5}$")

    /** Android reports a missing EXTRA_RSSI as Short.MIN_VALUE. */
    fun rssiOrNull(raw: Short): Int? = if (raw == Short.MIN_VALUE) null else raw.toInt()

    fun normalizeAddress(address: String): String = address.trim().uppercase()

    /** Same rule as BluetoothAdapter.checkBluetoothAddress (upper-case only). */
    fun isValidAddress(address: String): Boolean = ADDRESS.matches(address)
}
