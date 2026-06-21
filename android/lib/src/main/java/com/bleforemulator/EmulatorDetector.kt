package com.bleforemulator

import android.os.Build

object EmulatorDetector {
    /**
     * Returns true when running on an AVD or Genymotion emulator.
     * Checks Build.FINGERPRINT (most reliable) and Build.MODEL as a fallback.
     */
    fun isEmulator(): Boolean {
        val fp = Build.FINGERPRINT
        return fp.startsWith("generic")
            || fp.startsWith("unknown")
            || fp.contains("emulator")
            || fp.contains("sdk_gphone")
            || Build.MODEL.contains("Emulator")
            || Build.MODEL.contains("Android SDK built for")
            // TODO: add Genymotion fingerprint patterns if needed
    }
}
