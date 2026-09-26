package dev.abdeldjalilchougui.bluetooth_spp

/** One way of opening an RFCOMM socket. */
internal enum class ConnectAttempt {
    /** createRfcommSocketToServiceRecord (SDP lookup, authenticated link). */
    SECURE,

    /** createInsecureRfcommSocketToServiceRecord (SDP lookup, no MITM protection). */
    INSECURE,

    /** Hidden createRfcommSocket(1) via reflection: skips SDP, fixed channel 1. */
    CHANNEL_1_SECURE,

    /** Hidden createInsecureRfcommSocket(1) via reflection. */
    CHANNEL_1_INSECURE,
}

/** Decides the ordered list of connect attempts. */
internal object ConnectPlan {
    fun attempts(secure: Boolean, insecureFallback: Boolean, channelFallback: Boolean): List<ConnectAttempt> {
        val out = mutableListOf<ConnectAttempt>()
        if (secure) {
            out.add(ConnectAttempt.SECURE)
            if (insecureFallback) out.add(ConnectAttempt.INSECURE)
        } else {
            out.add(ConnectAttempt.INSECURE)
        }
        if (channelFallback) {
            out.add(if (secure) ConnectAttempt.CHANNEL_1_SECURE else ConnectAttempt.CHANNEL_1_INSECURE)
        }
        return out
    }

    fun remainingMillis(deadline: Long, now: Long): Long = maxOf(0L, deadline - now)
}
