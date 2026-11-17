package com.example.vela

import android.app.Application
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class VelaApplication : Application() {
    private external fun initializeIroh(context: android.content.Context)

    var engine: FlutterEngine? = null
        private set
    var nodeReady: Boolean = false
    private var activity: WeakReference<MainActivity>? = null
    val channels by lazy { AppChannels(this) }
    val currentActivity: MainActivity? get() = activity?.get()

    fun getOrCreateEngine(): FlutterEngine {
        engine?.let { return it }
        val created = FlutterEngine(this)
        try {
            channels.install(created)
        } catch (e: Exception) {
            created.destroy()
            throw e
        }
        engine = created
        return created
    }

    fun attachActivity(value: MainActivity) {
        activity = WeakReference(value)
    }

    fun detachActivity(value: MainActivity) {
        if (activity?.get() !== value) return
        activity = null
        engine?.let {
            if (ReceivingService.running && !it.dartExecutor.isExecutingDart) startHeadlessEngine()
        }
    }

    fun startHeadlessEngine() {
        val existing = engine
        if (existing?.dartExecutor?.isExecutingDart == true || activity?.get() != null) return
        val created = getOrCreateEngine()
        try {
            created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        } catch (e: Exception) {
            engine = null
            created.destroy()
            throw e
        }
    }

    override fun onCreate() {
        super.onCreate()
        System.loadLibrary("rust_lib_vela")
        initializeIroh(applicationContext)
        val handler = Handler(Looper.getMainLooper())
        val coalescer =
            NetworkChangeCoalescer({ task, delay -> handler.postDelayed(task, delay) }) {
                engine?.let {
                    MethodChannel(it.dartExecutor.binaryMessenger, "vela/background")
                        .invokeMethod("networkChanged", null)
                }
            }
        fun changed() {
            handler.post { coalescer.changed() }
        }
        val callback =
            object : ConnectivityManager.NetworkCallback() {
                private val links = mutableMapOf<Network, LinkProperties>()

                override fun onAvailable(network: Network) = changed()

                override fun onLost(network: Network) {
                    links.remove(network)
                    changed()
                }

                override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) {
                    if (links.put(network, properties) != properties) changed()
                }
            }
        val request =
            NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .build()
        val connectivity = getSystemService(ConnectivityManager::class.java)
        connectivity.registerNetworkCallback(request, callback)
        connectivity.registerDefaultNetworkCallback(
            object : ConnectivityManager.NetworkCallback() {
                private var current: Network? = null
                private var routeState: List<Boolean>? = null

                override fun onAvailable(network: Network) {
                    if (current != network) {
                        current = network
                        routeState = null
                        changed()
                    }
                }

                override fun onLost(network: Network) {
                    if (current == network) {
                        current = null
                        routeState = null
                        changed()
                    }
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    capabilities: NetworkCapabilities,
                ) {
                    if (current != network) return
                    val currentState =
                        listOf(
                                NetworkCapabilities.TRANSPORT_WIFI,
                                NetworkCapabilities.TRANSPORT_CELLULAR,
                                NetworkCapabilities.TRANSPORT_ETHERNET,
                                NetworkCapabilities.TRANSPORT_VPN,
                                NetworkCapabilities.TRANSPORT_BLUETOOTH,
                            )
                            .map { capabilities.hasTransport(it) } +
                            listOf(
                                    NetworkCapabilities.NET_CAPABILITY_INTERNET,
                                    NetworkCapabilities.NET_CAPABILITY_VALIDATED,
                                    NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED,
                                )
                                .map { capabilities.hasCapability(it) }
                    if (routeState != null && routeState != currentState) changed()
                    routeState = currentState
                }
            }
        )
    }
}
