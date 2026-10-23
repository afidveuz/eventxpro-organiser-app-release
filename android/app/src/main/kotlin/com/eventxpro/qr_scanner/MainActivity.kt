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
        private const val PROFILE_NAME = "EventXPro_Scanner"
        private const val DATAWEDGE_ACTION = "com.symbol.datawedge.api.ACTION"
        private const val EXTRA_CREATE_PROFILE = "com.symbol.datawedge.api.CREATE_PROFILE"
        private const val EXTRA_SET_CONFIG = "com.symbol.datawedge.api.SET_CONFIG"
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        // EventChannel: Stream hardware decoded events to Flutter Central Scan Controller
        EventChannel(engine.dartExecutor.binaryMessenger, channelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    scanSink = events
                    registerScanner()
                    // Auto-configure Zebra DataWedge Profile on connection
                    createAndConfigureDataWedgeProfile()
                }

                override fun onCancel(args: Any?) {
                    unregisterScanner()
                    scanSink = null
                }
            })

        // MethodChannel: Query hardware scanner status & control DataWedge
        MethodChannel(engine.dartExecutor.binaryMessenger, controlChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isScannerAvailable" -> {
                        result.success(true)
                    }
                    "provisionDataWedge" -> {
                        createAndConfigureDataWedgeProfile()
                        result.success(true)
                    }
                    "sendDataWedgeCommand" -> {
                        val command = call.argument<String>("command")
                        val extra = call.argument<String>("parameter")
                        val dwIntent = Intent(DATAWEDGE_ACTION)
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
        createAndConfigureDataWedgeProfile()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleScanIntent(intent)
    }

    private fun handleScanIntent(intent: Intent?) {
        if (intent == null) return
        Log.d(TAG, "Received scan intent action: ${intent.action}")
        val value = intent.getStringExtra("com.symbol.datawedge.data_string")
            ?: intent.getStringExtra("data") // Honeywell standard data extra
            ?: intent.getStringExtra("data_string")
            ?: intent.getStringExtra("barcode_data")
            ?: intent.getStringExtra("com.symbol.datawedge.decode_data")
            ?: return

        if (value.isNotEmpty()) {
            emitBarcode(value)
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
            addAction("com.symbol.datawedge.api.RESULT_ACTION")
            // Honeywell default broadcast actions
            addAction("com.honeywell.sample.action.BARCODE_DATA")
            addAction("com.honeywell.decode.intent.action.EDIT_DATA")
        }

        ContextCompat.registerReceiver(
            this,
            receiver,
            filter,
            ContextCompat.RECEIVER_EXPORTED
        )
    }

    /**
     * Programmatically provisions the Zebra DataWedge profile so the TC15
     * immediately starts broadcasting scan results to com.eventxpro.SCAN.
     */
    private fun createAndConfigureDataWedgeProfile() {
        try {
            // 1. Create profile if it doesn't exist
            val createIntent = Intent(DATAWEDGE_ACTION).apply {
                putExtra(EXTRA_CREATE_PROFILE, PROFILE_NAME)
                putExtra("SEND_RESULT", "LAST_RESULT")
                putExtra("COMMAND_IDENTIFIER", "CREATE_PROFILE_CMD")
            }
            sendBroadcast(createIntent)

            // 2. Configure the profile (Associate with app, Enable Intent broadcast, Disable Keystroke)
            val profileConfig = Bundle().apply {
                putString("PROFILE_NAME", PROFILE_NAME)
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

            val setConfigIntent = Intent(DATAWEDGE_ACTION).apply {
                putExtra(EXTRA_SET_CONFIG, profileConfig)
                putExtra("SEND_RESULT", "LAST_RESULT")
                putExtra("COMMAND_IDENTIFIER", "SET_CONFIG_CMD")
            }
            sendBroadcast(setConfigIntent)
            Log.d(TAG, "Sent Zebra DataWedge auto-provisioning intents for $PROFILE_NAME")
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
        unregisterScanner()
        scanSink = null
        super.onDestroy()
    }
}
