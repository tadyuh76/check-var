package com.example.check_var

import org.junit.Assert.*
import org.junit.Test

class SpeakerTestLaunchTest {

    @Test
    fun `buildCallActiveEvent contains correct type and state`() {
        val active = SpeakerTestLaunch.buildCallActiveEvent(isActive = true)
        assertEquals("call_state", active["type"])
        assertEquals(true, active["isActive"])

        val inactive = SpeakerTestLaunch.buildCallActiveEvent(isActive = false)
        assertEquals("call_state", inactive["type"])
        assertEquals(false, inactive["isActive"])
    }

    @Test
    fun `buildTranscriptEvent creates partial event`() {
        val event = SpeakerTestLaunch.buildTranscriptEvent("hello world", isFinal = false)
        assertEquals("transcript_partial", event["type"])
        assertEquals("hello world", event["text"])
    }

    @Test
    fun `buildTranscriptEvent creates final event`() {
        val event = SpeakerTestLaunch.buildTranscriptEvent("goodbye", isFinal = true)
        assertEquals("transcript_final", event["type"])
        assertEquals("goodbye", event["text"])
    }

    @Test
    fun `buildRecognizerReadyEvent creates ready event`() {
        val event = SpeakerTestLaunch.buildRecognizerReadyEvent()
        assertEquals("recognizer_ready", event["type"])
    }

    @Test
    fun `launch reason constant matches expected value`() {
        assertEquals("speaker_test_launch", SpeakerTestLaunch.REASON_SPEAKER_TEST)
        assertEquals("launch_reason", SpeakerTestLaunch.REASON_KEY)
    }
}
