package dev.abdeldjalilchougui.bluetooth_spp

import kotlin.test.Test
import kotlin.test.assertEquals

internal class ConnectPlanTest {
    @Test
    fun secureOnlyByDefault() {
        assertEquals(listOf(ConnectAttempt.SECURE), ConnectPlan.attempts(secure = true, insecureFallback = false, channelFallback = false))
    }

    @Test
    fun insecureOnly() {
        assertEquals(listOf(ConnectAttempt.INSECURE), ConnectPlan.attempts(secure = false, insecureFallback = false, channelFallback = false))
    }

    @Test
    fun secureWithInsecureFallback() {
        assertEquals(
            listOf(ConnectAttempt.SECURE, ConnectAttempt.INSECURE),
            ConnectPlan.attempts(secure = true, insecureFallback = true, channelFallback = false),
        )
    }

    @Test
    fun allFallbacks() {
        assertEquals(
            listOf(ConnectAttempt.SECURE, ConnectAttempt.INSECURE, ConnectAttempt.CHANNEL_1_SECURE),
            ConnectPlan.attempts(secure = true, insecureFallback = true, channelFallback = true),
        )
    }

    @Test
    fun insecureWithChannelFallbackStaysInsecure() {
        assertEquals(
            listOf(ConnectAttempt.INSECURE, ConnectAttempt.CHANNEL_1_INSECURE),
            ConnectPlan.attempts(secure = false, insecureFallback = true, channelFallback = true),
        )
    }

    @Test
    fun remainingTimeIsSharedAcrossAttempts() {
        assertEquals(700L, ConnectPlan.remainingMillis(deadline = 1700L, now = 1000L))
        assertEquals(0L, ConnectPlan.remainingMillis(deadline = 1000L, now = 1200L))
    }
}
