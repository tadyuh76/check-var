package com.example.check_var

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.checkvar/service"
        private const val EVENT_CHANNEL = "com.checkvar/events"
        private const val MEDIA_PROJECTION_SETUP = 1002
        private const val SPEAKER_TEST_PERMISSIONS = 1003
        const val EXTRA_APP_ACTION = "checkvar_app_action"
        const val ACTION_OPEN_CALL_DEBUG = "open_call_debug"

        var instance: MainActivity? = null
        var projectionReady = false
    }

    private var pendingPermissionsResult: MethodChannel.Result? = null

    private lateinit var serviceBridge: ServiceBridge
    private var methodChannel: MethodChannel? = null
    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var pendingSetupResult: MethodChannel.Result? = null

    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var latestFrameBytes: ByteArray? = null
    private var screenWidth = 0
    private var screenHeight = 0

    var pendingScreenshotBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this

        serviceBridge = ServiceBridge(this)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "setupProjection" -> setupProjection(result)
                "getPendingScreenshot" -> {
                    val bytes = pendingScreenshotBytes
                    pendingScreenshotBytes = null
                    result.success(bytes)
                }
                "requestSpeakerTestPermissions" -> requestSpeakerTestPermissions(result)
                else -> serviceBridge.onMethodCall(call, result)
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    serviceBridge.attachEventSink(events)
                }
                override fun onCancel(arguments: Any?) {
                    serviceBridge.detachEventSink()
                }
            })

        mediaProjectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        handleAppActionIntent(intent)
    }

    private fun requestSpeakerTestPermissions(result: MethodChannel.Result) {
        val needed = mutableListOf<String>()
        if (androidx.core.content.ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.READ_PHONE_STATE
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            needed.add(android.Manifest.permission.READ_PHONE_STATE)
        }
        if (androidx.core.content.ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            needed.add(android.Manifest.permission.RECORD_AUDIO)
        }

        if (needed.isEmpty()) {
            result.success(true)
            return
        }

        pendingPermissionsResult = result
        androidx.core.app.ActivityCompat.requestPermissions(
            this, needed.toTypedArray(), SPEAKER_TEST_PERMISSIONS
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SPEAKER_TEST_PERMISSIONS) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all {
                it == PackageManager.PERMISSION_GRANTED
            }
            pendingPermissionsResult?.success(allGranted)
            pendingPermissionsResult = null
        }
    }

    private fun setupProjection(result: MethodChannel.Result) {
        if (projectionReady) {
            result.success(true)
            return
        }
        pendingSetupResult = result
        val intent = mediaProjectionManager!!.createScreenCaptureIntent()
        startActivityForResult(intent, MEDIA_PROJECTION_SETUP)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == MEDIA_PROJECTION_SETUP) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                Handler(Looper.getMainLooper()).postDelayed({
                    try {
                        mediaProjection = mediaProjectionManager!!.getMediaProjection(resultCode, data)
                        mediaProjection!!.registerCallback(object : MediaProjection.Callback() {
                            override fun onStop() {
                                projectionReady = false
                                mediaProjection = null
                                releaseVirtualDisplay()
                            }
                        }, Handler(Looper.getMainLooper()))
                        setupVirtualDisplay()
                        projectionReady = true
                        pendingSetupResult?.success(true)
                    } catch (e: Exception) {
                        pendingSetupResult?.error("PROJECTION_ERROR", e.message, null)
                    }
                    pendingSetupResult = null
                }, 300)
            } else {
                pendingSetupResult?.error("PERMISSION_DENIED", "Screen capture permission denied", null)
                pendingSetupResult = null
            }
        }
    }

    private fun setupVirtualDisplay() {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
        val density = metrics.densityDpi

        imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 4)

        imageReader!!.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val planes = image.planes
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - pixelStride * screenWidth

                val bitmap = Bitmap.createBitmap(
                    screenWidth + rowPadding / pixelStride,
                    screenHeight,
                    Bitmap.Config.ARGB_8888
                )
                bitmap.copyPixelsFromBuffer(buffer)
                val croppedBitmap = Bitmap.createBitmap(bitmap, 0, 0, screenWidth, screenHeight)

                val outputStream = ByteArrayOutputStream()
                croppedBitmap.compress(Bitmap.CompressFormat.JPEG, 80, outputStream)
                latestFrameBytes = outputStream.toByteArray()

                bitmap.recycle()
                croppedBitmap.recycle()
            } finally {
                image.close()
            }
        }, Handler(Looper.getMainLooper()))

        virtualDisplay = mediaProjection!!.createVirtualDisplay(
            "CheckVarCapture",
            screenWidth, screenHeight, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface,
            null, null
        )
    }

    private fun releaseVirtualDisplay() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        latestFrameBytes = null
    }

    fun captureScreenNow(callback: (ByteArray?) -> Unit) {
        callback(latestFrameBytes)
    }

    override fun onDestroy() {
        releaseVirtualDisplay()
        instance = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAppActionIntent(intent)
    }

    private fun handleAppActionIntent(intent: Intent?) {
        val action = intent?.getStringExtra(EXTRA_APP_ACTION) ?: return
        intent.removeExtra(EXTRA_APP_ACTION)
        serviceBridge.handleAppAction(action)
    }
}
