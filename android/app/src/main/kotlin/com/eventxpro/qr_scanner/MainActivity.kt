package com.eventxpro.qr_scanner

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "eventxpro/scanner"
    private val controlChannelName = "eventxpro/scanner_control"
    private val scanAction = "com.eventxpro.SCAN"
    private var scanSink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    companion object {
        private const val TAG = "EventXProScanner"

        // Zebra DataWedge API Constants
        private const val ZEBRA_PROFILE_NAME = "EventXPro_Scanner"
        private const val ZEBRA_ACTION = "com.symbol.datawedge.api.ACTION"
        private const val ZEBRA_EXTRA_CREATE_PROFILE = "com.symbol.datawedge.api.CREATE_PROFILE"
        private const val ZEBRA_EXTRA_SET_CONFIG = "com.symbol.datawedge.api.SET_CONFIG"

        // Honeywell AIDC Constants
        private const val HONEYWELL_ACTION_CLAIM = "com.honeywell.aidc.action.ACTION_CLAIM_SCANNER"
        private const val HONEYWELL_ACTION_RELEASE = "com.honeywell.aidc.action.ACTION_RELEASE_SCANNER"
        private const val HONEYWELL_PACKAGE = "com.intermec.datacollectionservice"
        private const val HONEYWELL_EXTRA_SCANNER = "com.honeywell.aidc.extra.EXTRA_SCANNER"
        private const val HONEYWELL_EXTRA_PROFILE = "com.honeywell.aidc.extra.EXTRA_PROFILE"
        private const val HONEYWELL_EXTRA_PROPERTIES = "com.honeywell.aidc.extra.EXTRA_PROPERTIES"
        private const val HONEYWELL_PROFILE_NAME = "EventXPro_Profile"
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        // EventChannel: Stream hardware decoded events to Flutter Central Scan Controller
        EventChannel(engine.dartExecutor.binaryMessenger, channelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    scanSink = events
                    registerScanner()
                    // Auto-configure hardware scanner profile for detected device
                    provisionHardwareScanner()
                }

                override fun onCancel(args: Any?) {
                    unregisterScanner()
                    scanSink = null
                }
            })

        // MethodChannel: Query hardware scanner status & control scanner
        MethodChannel(engine.dartExecutor.binaryMessenger, controlChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isScannerAvailable" -> {
                        result.success(true)
                    }
                    "getDeviceInfo" -> {
                        val manufacturer = Build.MANUFACTURER ?: "Unknown"
                        val model = Build.MODEL ?: "Unknown"
                        val brand = Build.BRAND ?: "Unknown"
                        val device = Build.DEVICE ?: "Unknown"
                        val release = Build.VERSION.RELEASE ?: "Unknown"
                        val sdkInt = Build.VERSION.SDK_INT
                        val devType = getDeviceType()

                        val scannerEngine = when (devType) {
                            "HONEYWELL" -> "Honeywell Data Collection Service"
                            "ZEBRA" -> "Zebra DataWedge API"
                            else -> "Generic / Camera Simulator"
                        }

                        val infoMap = mapOf(
                            "manufacturer" to manufacturer,
                            "model" to model,
                            "brand" to brand,
                            "device" to device,
                            "osRelease" to release,
                            "sdkInt" to sdkInt,
                            "deviceType" to devType,
                            "scannerEngine" to scannerEngine,
                            "isHardwareScannerCapable" to (devType != "GENERIC_ANDROID")
                        )
                        result.success(infoMap)
                    }
                    "provisionScanner" -> {
                        provisionHardwareScanner()
                        result.success(true)
                    }
                    "provisionDataWedge" -> {
                        createAndConfigureDataWedgeProfile()
                        result.success(true)
                    }
                    "provisionHoneywell" -> {
                        provisionHoneywellScanner()
                        result.success(true)
                    }
                    "sendDataWedgeCommand" -> {
                        val command = call.argument<String>("command")
                        val extra = call.argument<String>("parameter")
                        val dwIntent = Intent(ZEBRA_ACTION)
                        if (command != null && extra != null) {
                            dwIntent.putExtra(command, extra)
                        }
                        sendBroadcast(dwIntent)
                        result.success(true)
                    }
                    "simulateScanIntent" -> {
                        val fakeCode = call.argument<String>("code") ?: ""
                        emitBarcode(fakeCode)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        provisionHardwareScanner()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleScanIntent(intent)
    }

    private fun getDeviceType(): String {
        val manufacturer = (Build.MANUFACTURER ?: "").lowercase()
        val brand = (Build.BRAND ?: "").lowercase()
        val model = (Build.MODEL ?: "").lowercase()

        return when {
            manufacturer.contains("honeywell") ||
            brand.contains("honeywell") ||
            model.contains("eda") ||
            model.contains("ct40") ||
            model.contains("ct60") ||
            model.contains("ck65") ||
            model.contains("rt10") -> "HONEYWELL"

            manufacturer.contains("zebra") ||
            brand.contains("zebra") ||
            manufacturer.contains("symbol") ||
            manufacturer.contains("motorola solutions") ||
            model.contains("tc") -> "ZEBRA"

            else -> "GENERIC_ANDROID"
        }
    }

    private fun provisionHardwareScanner() {
        val type = getDeviceType()
        Log.d(TAG, "Detected device type: $type (Manufacturer: ${Build.MANUFACTURER}, Model: ${Build.MODEL})")

        when (type) {
            "HONEYWELL" -> {
                provisionHoneywellScanner()
            }
            "ZEBRA" -> {
                createAndConfigureDataWedgeProfile()
            }
            else -> {
                // Unknown / Generic: attempt both safely to ensure broadcast works on any clone or hybrid
                provisionHoneywellScanner()
                createAndConfigureDataWedgeProfile()
            }
        }
    }

    private fun handleScanIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: "Unknown"
        Log.d(TAG, "Received scan intent action: $action")

        // 1. Extract text from Honeywell, Zebra, and generic intent extras
        var value: String? = intent.getStringExtra("data") // Honeywell primary decoded string
            ?: intent.getStringExtra("com.symbol.datawedge.data_string") // Zebra primary
            ?: intent.getStringExtra("data_string") // Honeywell / third-party
            ?: intent.getStringExtra("com.honeywell.decode.intent.extra.DATA_STRING")
            ?: intent.getStringExtra("barcode_data")
            ?: intent.getStringExtra("com.symbol.datawedge.decode_data")

        // 2. Fallback to Honeywell raw dataBytes if string extra is null
        if (value.isNullOrEmpty()) {
            val rawBytes = intent.getByteArrayExtra("dataBytes")
                ?: intent.getByteArrayExtra("com.honeywell.decode.intent.extra.DATA_BYTES")
            if (rawBytes != null && rawBytes.isNotEmpty()) {
                val charsetName = intent.getStringExtra("charset") ?: "UTF-8"
                try {
                    value = String(rawBytes, java.nio.charset.Charset.forName(charsetName))
                } catch (_: Exception) {
                    value = String(rawBytes, Charsets.UTF_8)
                }
            }
        }

        if (!value.isNullOrEmpty()) {
            emitBarcode(value.trim())
        }
    }

    private fun emitBarcode(barcode: String) {
        Log.d(TAG, "Barcode decoded and emitted to Flutter: $barcode")
        runOnUiThread {
            scanSink?.success(barcode)
        }
    }

    private fun registerScanner() {
        if (receiver != null) return
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                handleScanIntent(intent)
            }
        }

        val filter = IntentFilter().apply {
            addAction(scanAction) // com.eventxpro.SCAN
            addCategory(Intent.CATEGORY_DEFAULT)
            addAction("com.symbol.datawedge.api.RESULT_ACTION")
            // Honeywell default broadcast actions
            addAction("com.honeywell.decode.intent.action.EDIT_DATA")
            addAction("com.honeywell.sample.action.BARCODE_DATA")
            addAction("com.honeywell.action.BARCODE_DATA")
        }

        ContextCompat.registerReceiver(
            this,
            receiver,
            filter,
            ContextCompat.RECEIVER_EXPORTED
        )
        Log.d(TAG, "Registered unified scanner receiver for $scanAction + Honeywell + Zebra actions")
    }

    /**
     * Programmatically claims and provisions Honeywell Data Collection Service (AIDC)
     * so devices like ScanPal EDA51, CT40, etc. immediately broadcast scan results.
     */
    private fun provisionHoneywellScanner() {
        try {
            val properties = Bundle().apply {
                putBoolean("DPR_DATA_INTENT", true)
                putString("DPR_DATA_INTENT_ACTION", scanAction)
                putString("DPR_DATA_INTENT_CATEGORY", Intent.CATEGORY_DEFAULT)
                putBoolean("DPR_WEDGE", false) // disable keystroke typing to eliminate UI lag
            }

            val claimIntent = Intent(HONEYWELL_ACTION_CLAIM).apply {
                setPackage(HONEYWELL_PACKAGE)
                putExtra(HONEYWELL_EXTRA_SCANNER, "dcs.scanner.imager")
                putExtra(HONEYWELL_EXTRA_PROFILE, HONEYWELL_PROFILE_NAME)
                putExtra(HONEYWELL_EXTRA_PROPERTIES, properties)
            }
            sendBroadcast(claimIntent)
            Log.d(TAG, "Sent Honeywell AIDC claim intent for $scanAction")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to auto-configure Honeywell scanner: ${e.message}")
        }
    }

    private fun releaseHoneywellScanner() {
        try {
            val releaseIntent = Intent(HONEYWELL_ACTION_RELEASE).apply {
                setPackage(HONEYWELL_PACKAGE)
            }
            sendBroadcast(releaseIntent)
            Log.d(TAG, "Sent Honeywell AIDC release intent")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release Honeywell scanner: ${e.message}")
        }
    }

    /**
     * Programmatically provisions the Zebra DataWedge profile so the TC15 / TC21
     * immediately starts broadcasting scan results to com.eventxpro.SCAN.
     */
    private fun createAndConfigureDataWedgeProfile() {
        try {
            // 1. Create profile if it doesn't exist
            val createIntent = Intent(ZEBRA_ACTION).apply {
                putExtra(ZEBRA_EXTRA_CREATE_PROFILE, ZEBRA_PROFILE_NAME)
                putExtra("SEND_RESULT", "LAST_RESULT")
                putExtra("COMMAND_IDENTIFIER", "CREATE_PROFILE_CMD")
            }
            sendBroadcast(createIntent)

            // 2. Configure the profile (Associate with app, Enable Intent broadcast, Disable Keystroke)
            val profileConfig = Bundle().apply {
                putString("PROFILE_NAME", ZEBRA_PROFILE_NAME)
                putString("PROFILE_ENABLED", "true")
                putString("CONFIG_MODE", "CREATE_IF_NOT_EXIST")

                // Associate app with this profile
                val appConfig = Bundle().apply {
                    putString("PACKAGE_NAME", packageName)
                    putStringArray("ACTIVITY_LIST", arrayOf("*"))
                }
                putParcelableArray("APP_LIST", arrayOf(appConfig))

                // Configure Barcode Plugin (Scanner)
                val barcodeProps = Bundle().apply {
                    putString("PLUGIN_NAME", "BARCODE")
                    putString("RESET_CONFIG", "false")
                    val params = Bundle().apply {
                        putString("scanner_selection", "auto")
                        putString("decoder_qrcode", "true")
                    }
                    putBundle("PARAM_LIST", params)
                }

                // Configure Intent Output Plugin (Broadcast com.eventxpro.SCAN)
                val intentProps = Bundle().apply {
                    putString("PLUGIN_NAME", "INTENT")
                    putString("RESET_CONFIG", "false")
                    val params = Bundle().apply {
                        putString("intent_output_enabled", "true")
                        putString("intent_action", scanAction)
                        putString("intent_delivery", "2") // 2 = Broadcast Intent
                    }
                    putBundle("PARAM_LIST", params)
                }

                // Configure Keystroke Output Plugin (DISABLED to prevent typing)
                val keystrokeProps = Bundle().apply {
                    putString("PLUGIN_NAME", "KEYSTROKE")
                    putString("RESET_CONFIG", "false")
                    val params = Bundle().apply {
                        putString("keystroke_output_enabled", "false")
                    }
                    putBundle("PARAM_LIST", params)
                }

                putParcelableArrayList("PLUGIN_CONFIG", arrayListOf(barcodeProps, intentProps, keystrokeProps))
            }

            val setConfigIntent = Intent(ZEBRA_ACTION).apply {
                putExtra(ZEBRA_EXTRA_SET_CONFIG, profileConfig)
                putExtra("SEND_RESULT", "LAST_RESULT")
                putExtra("COMMAND_IDENTIFIER", "SET_CONFIG_CMD")
            }
            sendBroadcast(setConfigIntent)
            Log.d(TAG, "Sent Zebra DataWedge auto-provisioning intents for $ZEBRA_PROFILE_NAME")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to auto-configure DataWedge: ${e.message}")
        }
    }

    private fun unregisterScanner() {
        receiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // Ignore if already unregistered
            }
        }
        receiver = null
    }

    override fun onDestroy() {
        releaseHoneywellScanner()
        unregisterScanner()
        scanSink = null
        super.onDestroy()
    }
}
