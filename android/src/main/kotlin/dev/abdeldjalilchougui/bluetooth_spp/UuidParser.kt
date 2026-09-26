package dev.abdeldjalilchougui.bluetooth_spp

import java.util.UUID

/** Parses service UUIDs in full, 16-bit or 32-bit Bluetooth short form. */
internal object UuidParser {
    private const val BASE_SUFFIX = "-0000-1000-8000-00805F9B34FB"
    private val FULL = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    private val SHORT = Regex("^(?:0[xX])?([0-9a-fA-F]{4}|[0-9a-fA-F]{8})$")

    fun parse(value: String): UUID {
        val v = value.trim()
        if (FULL.matches(v)) return UUID.fromString(v)
        val m = SHORT.matchEntire(v) ?: throw IllegalArgumentException("Invalid service UUID: '$value'")
        val hex = m.groupValues[1].padStart(8, '0').uppercase()
        return UUID.fromString(hex + BASE_SUFFIX)
    }
}
