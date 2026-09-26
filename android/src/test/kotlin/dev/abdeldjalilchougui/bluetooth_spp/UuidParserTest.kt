package dev.abdeldjalilchougui.bluetooth_spp

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class UuidParserTest {
    private val spp = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    @Test
    fun parsesFullForm() {
        assertEquals(spp, UuidParser.parse("00001101-0000-1000-8000-00805F9B34FB"))
    }

    @Test
    fun parsesLowerCaseAndTrimsWhitespace() {
        assertEquals(spp, UuidParser.parse("  00001101-0000-1000-8000-00805f9b34fb "))
    }

    @Test
    fun expands16BitShortForm() {
        assertEquals(spp, UuidParser.parse("1101"))
        assertEquals(spp, UuidParser.parse("0x1101"))
    }

    @Test
    fun expands32BitShortForm() {
        assertEquals(spp, UuidParser.parse("00001101"))
        assertEquals(
            UUID.fromString("ABCD1101-0000-1000-8000-00805F9B34FB"),
            UuidParser.parse("0xabcd1101"),
        )
    }

    @Test
    fun rejectsMalformedValues() {
        for (bad in listOf("", "xyz", "123", "11011", "00001101-0000-1000-8000", "0000110100001000800000805F9B34FB",
            "00001101-0000-1000-8000-00805F9B34FG")) {
            assertFailsWith<IllegalArgumentException>(bad) { UuidParser.parse(bad) }
        }
    }
}
