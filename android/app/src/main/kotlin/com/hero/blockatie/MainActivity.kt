package com.hero.blockatie

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "blockatie.driver/readiness"
    private val vpnEventChannelName = "blockatie.driver/vpn_events"
    private val readinessLaunchExtra = "open_driver_readiness"
    private var readinessChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readinessChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        readinessChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isVpnActive" -> result.success(isVpnActive())
                    "consumeReadinessLaunch" -> result.success(consumeReadinessLaunch())
                    "showLocationOffNotification" -> {
                        result.success(
                            DriverReadinessNotifications.showLocationOff(
                                this,
                                call.argument<Boolean>("isArabic") == true,
                            ),
                        )
                    }
                    "hideLocationOffNotification" -> {
                        DriverReadinessNotifications.hideLocationOff(this)
                        result.success(null)
                    }
                    "startLocationReadinessMonitor" -> {
                        result.success(
                            LocationReadinessMonitorService.start(
                                this,
                                call.argument<Boolean>("isArabic") == true,
                            ),
                        )
                    }
                    "stopLocationReadinessMonitor" -> {
                        LocationReadinessMonitorService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, vpnEventChannelName)
            .setStreamHandler(VpnStreamHandler(this))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (consumeReadinessLaunch()) {
            readinessChannel?.invokeMethod("openReadiness", null)
        }
    }

    private fun consumeReadinessLaunch(): Boolean {
        val shouldOpen = intent?.getBooleanExtra(readinessLaunchExtra, false) == true
        if (shouldOpen) intent?.removeExtra(readinessLaunchExtra)
        return shouldOpen
    }

    private fun isVpnActive(): Boolean {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return manager.allNetworks.any { network ->
            manager.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }
    }

    private class VpnStreamHandler(private val context: Context) : EventChannel.StreamHandler {
        private val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        private val handler = Handler(Looper.getMainLooper())
        private var sink: EventChannel.EventSink? = null
        private var lastValue: Boolean? = null
        private var callback: ConnectivityManager.NetworkCallback? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            sink = events
            emitCurrent()
            callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = emitCurrent()
                override fun onLost(network: Network) = emitCurrent()
                override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = emitCurrent()
            }.also {
                manager.registerNetworkCallback(NetworkRequest.Builder().build(), it)
            }
        }

        override fun onCancel(arguments: Any?) {
            callback?.let {
                try { manager.unregisterNetworkCallback(it) } catch (_: IllegalArgumentException) { }
            }
            callback = null
            sink = null
            lastValue = null
        }

        private fun emitCurrent() {
            handler.post {
                val active = manager.allNetworks.any { network ->
                    manager.getNetworkCapabilities(network)
                        ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
                }
                if (active != lastValue) {
                    lastValue = active
                    sink?.success(active)
                }
            }
        }
    }
}
