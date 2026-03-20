package com.example.check_var

import android.telephony.TelephonyManager

object CallMonitorPolicy {

    fun shouldShowOverlay(callState: Int, overlayGranted: Boolean): Boolean {
        return callState == TelephonyManager.CALL_STATE_OFFHOOK && overlayGranted
    }

    fun shouldHideOverlay(callState: Int): Boolean {
        return callState == TelephonyManager.CALL_STATE_IDLE ||
                callState == TelephonyManager.CALL_STATE_RINGING
    }

    fun isCallActive(callState: Int): Boolean {
        return callState == TelephonyManager.CALL_STATE_OFFHOOK
    }
}
