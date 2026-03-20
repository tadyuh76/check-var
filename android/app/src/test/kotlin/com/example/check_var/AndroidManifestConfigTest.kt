package com.example.check_var

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Test

class AndroidManifestConfigTest {

    @Test
    fun `call monitor service is not declared as phoneCall foreground service`() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        val callMonitorBlock = Regex(
            """<service\s+android:name="\.CallMonitorService"[\s\S]*?/>""",
        ).find(manifest)?.value ?: ""

        assertFalse(
            callMonitorBlock.contains("""android:foregroundServiceType="phoneCall""""),
        )
    }
}
