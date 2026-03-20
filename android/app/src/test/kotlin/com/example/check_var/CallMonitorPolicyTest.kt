package com.example.check_var

import android.telephony.TelephonyManager
import org.junit.Assert.*
import org.junit.Test

class CallMonitorPolicyTest {

    @Test
    fun `shouldShowOverlay returns true when offhook and overlay granted`() {
        assertTrue(
            CallMonitorPolicy.shouldShowOverlay(
                callState = TelephonyManager.CALL_STATE_OFFHOOK,
                overlayGranted = true,
            )
        )
    }

    @Test
    fun `shouldShowOverlay returns false when offhook but overlay not granted`() {
        assertFalse(
            CallMonitorPolicy.shouldShowOverlay(
                callState = TelephonyManager.CALL_STATE_OFFHOOK,
                overlayGranted = false,
            )
        )
    }

    @Test
    fun `shouldShowOverlay returns false when idle`() {
        assertFalse(
            CallMonitorPolicy.shouldShowOverlay(
                callState = TelephonyManager.CALL_STATE_IDLE,
                overlayGranted = true,
            )
        )
    }

    @Test
    fun `shouldShowOverlay returns false when ringing`() {
        assertFalse(
            CallMonitorPolicy.shouldShowOverlay(
                callState = TelephonyManager.CALL_STATE_RINGING,
                overlayGranted = true,
            )
        )
    }

    @Test
    fun `shouldHideOverlay returns true when idle`() {
        assertTrue(CallMonitorPolicy.shouldHideOverlay(TelephonyManager.CALL_STATE_IDLE))
    }

    @Test
    fun `shouldHideOverlay returns true when ringing`() {
        assertTrue(CallMonitorPolicy.shouldHideOverlay(TelephonyManager.CALL_STATE_RINGING))
    }

    @Test
    fun `shouldHideOverlay returns false when offhook`() {
        assertFalse(CallMonitorPolicy.shouldHideOverlay(TelephonyManager.CALL_STATE_OFFHOOK))
    }

    @Test
    fun `isCallActive returns true only for offhook`() {
        assertTrue(CallMonitorPolicy.isCallActive(TelephonyManager.CALL_STATE_OFFHOOK))
        assertFalse(CallMonitorPolicy.isCallActive(TelephonyManager.CALL_STATE_IDLE))
        assertFalse(CallMonitorPolicy.isCallActive(TelephonyManager.CALL_STATE_RINGING))
    }
}
