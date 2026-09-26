package dev.abdeldjalilchougui.bluetooth_spp

/**
 * Thread-safe map of open connections keyed by the id the Dart side chose.
 * An id can be reserved while its socket is still connecting so that a
 * duplicate connect is rejected early.
 */
internal class ConnectionRegistry<T : Any> {
    private val lock = Any()
    private val entries = HashMap<String, T>()
    private val reserved = HashSet<String>()

    val size: Int get() = synchronized(lock) { entries.size }

    fun reserve(id: String): Boolean = synchronized(lock) {
        if (entries.containsKey(id) || reserved.contains(id)) false else reserved.add(id)
    }

    fun release(id: String) {
        synchronized(lock) { reserved.remove(id) }
    }

    fun add(id: String, connection: T) {
        synchronized(lock) {
            check(!entries.containsKey(id)) { "Connection id '$id' is already in use" }
            reserved.remove(id)
            entries[id] = connection
        }
    }

    fun get(id: String): T? = synchronized(lock) { entries[id] }

    fun remove(id: String): T? = synchronized(lock) { entries.remove(id) }

    fun ids(): Set<String> = synchronized(lock) { entries.keys.toSet() }

    /** Removes and returns every connection, and forgets reservations. */
    fun drain(): List<T> = synchronized(lock) {
        val all = entries.values.toList()
        entries.clear()
        reserved.clear()
        all
    }
}
