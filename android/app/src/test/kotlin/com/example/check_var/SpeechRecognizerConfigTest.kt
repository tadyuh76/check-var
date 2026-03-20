package com.example.check_var

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SpeechRecognizerConfigTest {

    @Test
    fun `speech recognizer defaults to vietnamese and configures language extras`() {
        val source = File("src/main/kotlin/com/example/checkvar/SpeechRecognizerManager.kt").readText()

        assertTrue(source.contains("""private val language: String = "vi-VN""""))
        assertTrue(source.contains("RecognizerIntent.EXTRA_LANGUAGE"))
        assertTrue(source.contains("RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE"))
        assertFalse(source.contains("RecognizerIntent.EXTRA_PREFER_OFFLINE"))
    }

    @Test
    fun `service bridge forwards the language argument to the recognizer`() {
        val source = File("src/main/kotlin/com/example/checkvar/ServiceBridge.kt").readText()

        assertTrue(source.contains("""call.argument<String>("language") ?: "vi-VN""""))
        assertTrue(source.contains("""startSpeakerRecognition(language)"""))
    }
}
