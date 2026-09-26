package dev.abdeldjalilchougui.bluetooth_spp

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.lang.reflect.InvocationTargetException
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bluetooth Classic SPP plugin. Blocking work (connect, write, close) runs on
 * background threads; results and events are posted back to the main thread.
 */
@SuppressLint("MissingPermission")
class BluetoothSppPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private var methodChannel: MethodChannel? = null
    private var adapterStateChannel: EventChannel? = null
    private var discoveryChannel: EventChannel? = null
    private var connectionsChannel: EventChannel? = null
    private var adapterStateHandler: AdapterStateHandler? = null
    private var discoveryHandler: DiscoveryHandler? = null

    private val main = Handler(Looper.getMainLooper())
    private var io: ExecutorService? = null
    private var watchdog: ScheduledExecutorService? = null
    private val registry = ConnectionRegistry<NativeConnection>()
    private val connecting: MutableSet<BluetoothSocket> = Collections.synchronizedSet(HashSet())
    private var connectionSink: EventChannel.EventSink? = null
    private val bondReceivers = HashMap<String, BroadcastReceiver>()

    @Volatile
    private var detached = false

    private var activityBinding: ActivityPluginBinding? = null
    private var pendingEnable: Result? = null

    private fun adapter(): BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    // region FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        detached = false
        io = Executors.newCachedThreadPool { r -> Thread(r, "bluetooth_spp-io").apply { isDaemon = true } }
        watchdog = Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "bluetooth_spp-timeout").apply { isDaemon = true }
        }
        val messenger = binding.binaryMessenger
        methodChannel = MethodChannel(messenger, "$PREFIX/methods").also { it.setMethodCallHandler(this) }
        val stateHandler = AdapterStateHandler(context, ::adapter)
        val scanHandler = DiscoveryHandler(context, ::adapter)
        adapterStateHandler = stateHandler
        discoveryHandler = scanHandler
        adapterStateChannel = EventChannel(messenger, "$PREFIX/adapter_state").also { it.setStreamHandler(stateHandler) }
        discoveryChannel = EventChannel(messenger, "$PREFIX/discovery").also { it.setStreamHandler(scanHandler) }
        connectionsChannel = EventChannel(messenger, "$PREFIX/connections").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    connectionSink = events
                }

                override fun onCancel(arguments: Any?) {
                    connectionSink = null
                }
            })
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true
        methodChannel?.setMethodCallHandler(null)
        adapterStateChannel?.setStreamHandler(null)
        discoveryChannel?.setStreamHandler(null)
        connectionsChannel?.setStreamHandler(null)
        methodChannel = null
        adapterStateChannel = null
        discoveryChannel = null
        connectionsChannel = null
        connectionSink = null
        adapterStateHandler?.dispose()
        discoveryHandler?.stop(cancel = true)
        adapterStateHandler = null
        discoveryHandler = null
        for (r in bondReceivers.values) Devices.unregister(context, r)
        bondReceivers.clear()
        pendingEnable = null
        // Unblock pending connects and close open sockets, off the main thread.
        val sockets = synchronized(connecting) { connecting.toList().also { connecting.clear() } }
        val open = registry.drain()
        watchdog?.shutdownNow()
        watchdog = null
        val pool = io
        io = null
        val closer = Runnable {
            for (s in sockets) closeQuietly(s)
            for (c in open) c.close()
        }
        if (pool != null) {
            pool.execute(closer)
            pool.shutdown()
        } else {
            Thread(closer, "bluetooth_spp-teardown").start()
        }
    }

    // endregion

    // region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // Keep pendingEnable: the result is delivered to the recreated activity.
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        pendingEnable?.error(ErrorCodes.ACTIVITY_UNAVAILABLE, "Activity detached before the enable request finished", null)
        pendingEnable = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_ENABLE_CODE) return false
        val result = pendingEnable ?: return true
        pendingEnable = null
        result.success(resultCode == Activity.RESULT_OK || adapter()?.isEnabled == true)
        return true
    }

    // endregion

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "isEnabled" -> result.success(adapter()?.isEnabled ?: false)
                "adapterState" -> result.success(adapter()?.state ?: -1)
                "requestEnable" -> requestEnable(result)
                "bondedDevices" -> {
                    val a = requireAdapter(result) ?: return
                    result.success(a.bondedDevices.orEmpty().map { Devices.toMap(it) })
                }
                "cancelDiscovery" -> {
                    adapter()?.cancelDiscovery()
                    result.success(null)
                }
                "bond" -> bond(call, result)
                "removeBond" -> removeBond(call, result)
                "permissionsStatus" -> result.success(permissionsStatus())
                "connect" -> connect(call, result)
                "write" -> write(call, result)
                "disconnect" -> disconnect(call, result)
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error(ErrorCodes.PERMISSION_DENIED, ErrorCodes.messageOf(e), null)
        } catch (e: IllegalArgumentException) {
            result.error(ErrorCodes.INVALID_ARGUMENT, ErrorCodes.messageOf(e), null)
        }
    }

    private fun requireAdapter(result: Result, mustBeOn: Boolean = false): BluetoothAdapter? {
        val a = adapter()
        if (a == null) {
            result.error(ErrorCodes.BLUETOOTH_UNAVAILABLE, "This device has no Bluetooth adapter", null)
            return null
        }
        if (mustBeOn && !a.isEnabled) {
            result.error(ErrorCodes.BLUETOOTH_DISABLED, "Bluetooth is off", null)
            return null
        }
        return a
    }

    private fun addressArg(call: MethodCall): String {
        val raw = call.argument<String>("address") ?: throw IllegalArgumentException("address is required")
        val address = DeviceCodes.normalizeAddress(raw)
        require(DeviceCodes.isValidAddress(address)) { "Invalid Bluetooth address: '$raw'" }
        return address
    }

    private fun requestEnable(result: Result) {
        val a = requireAdapter(result) ?: return
        if (a.isEnabled) return result.success(true)
        val activity = activityBinding?.activity
            ?: return result.error(ErrorCodes.ACTIVITY_UNAVAILABLE, "requestEnable needs a foreground activity", null)
        if (pendingEnable != null) return result.error(ErrorCodes.BUSY, "An enable request is already showing", null)
        pendingEnable = result
        try {
            activity.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_ENABLE_CODE)
        } catch (e: SecurityException) {
            pendingEnable = null
            throw e
        }
    }

    private fun bond(call: MethodCall, result: Result) {
        val address = addressArg(call)
        val a = requireAdapter(result, mustBeOn = true) ?: return
        val device = a.getRemoteDevice(address)
        if (device.bondState == BluetoothDevice.BOND_BONDED) return result.success(true)
        if (bondReceivers.containsKey(address)) {
            return result.error(ErrorCodes.BUSY, "Already bonding with $address", null)
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                if (Devices.deviceExtra(intent)?.address != address) return
                val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                if (state == BluetoothDevice.BOND_BONDED || state == BluetoothDevice.BOND_NONE) {
                    bondReceivers.remove(address)?.let { Devices.unregister(context, it) }
                    result.success(state == BluetoothDevice.BOND_BONDED)
                }
            }
        }
        bondReceivers[address] = receiver
        Devices.register(context, receiver, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED))
        val started = try {
            device.bondState == BluetoothDevice.BOND_BONDING || device.createBond()
        } catch (e: SecurityException) {
            bondReceivers.remove(address)
            Devices.unregister(context, receiver)
            throw e
        }
        if (!started) {
            bondReceivers.remove(address)
            Devices.unregister(context, receiver)
            result.success(false)
        }
    }

    /** Best effort: BluetoothDevice.removeBond() is hidden API, called through reflection. */
    private fun removeBond(call: MethodCall, result: Result) {
        val address = addressArg(call)
        val a = requireAdapter(result) ?: return
        val device = a.getRemoteDevice(address)
        if (device.bondState == BluetoothDevice.BOND_NONE) return result.success(true)
        val removed = try {
            device.javaClass.getMethod("removeBond").invoke(device) as? Boolean ?: false
        } catch (e: InvocationTargetException) {
            val cause = e.cause
            if (cause is SecurityException) throw cause
            false
        } catch (_: ReflectiveOperationException) {
            false
        }
        result.success(removed)
    }

    private fun permissionsStatus(): Map<String, Any> {
        val sdk = Build.VERSION.SDK_INT
        val connect = PermissionPolicy.connect(sdk)
        val scan = PermissionPolicy.scan(sdk)
        val granted = { p: String -> Devices.isGranted(context, p) }
        val missing = (connect + scan).distinct().filterNot { PermissionPolicy.granted(listOf(it), granted) }
        return mapOf(
            "sdkInt" to sdk,
            "connectGranted" to PermissionPolicy.granted(connect, granted),
            "scanGranted" to PermissionPolicy.granted(scan, granted),
            "missing" to missing,
        )
    }

    // region Connections

    private fun connect(call: MethodCall, result: Result) {
        val id = call.argument<String>("id") ?: throw IllegalArgumentException("id is required")
        val address = addressArg(call)
        val uuid = UuidParser.parse(call.argument<String>("uuid") ?: SPP_UUID)
        val timeoutMs = (call.argument<Number>("timeoutMs") ?: DEFAULT_TIMEOUT_MS).toLong()
        require(timeoutMs > 0) { "timeoutMs must be positive" }
        val plan = ConnectPlan.attempts(
            secure = call.argument<Boolean>("secure") ?: true,
            insecureFallback = call.argument<Boolean>("insecureFallback") ?: false,
            channelFallback = call.argument<Boolean>("channelFallback") ?: false,
        )
        val a = requireAdapter(result, mustBeOn = true) ?: return
        val pool = io ?: return result.error(ErrorCodes.NOT_CONNECTED, "Plugin is detached", null)
        if (!registry.reserve(id)) {
            return result.error(ErrorCodes.INVALID_ARGUMENT, "Connection id '$id' is in use", null)
        }
        val device = a.getRemoteDevice(address)
        pool.execute { runConnect(id, a, device, uuid, plan, timeoutMs, result) }
    }

    /** Runs on an io thread. Tries each attempt until one connects or time runs out. */
    private fun runConnect(
        id: String,
        adapter: BluetoothAdapter,
        device: BluetoothDevice,
        uuid: UUID,
        plan: List<ConnectAttempt>,
        timeoutMs: Long,
        result: Result,
    ) {
        try {
            adapter.cancelDiscovery() // A running inquiry slows down and breaks RFCOMM connects.
        } catch (_: SecurityException) {
        }
        val deadline = System.currentTimeMillis() + timeoutMs
        var lastError: Throwable = IOException("No connect attempt was made")
        var timedOut = false
        for (attempt in plan) {
            val remaining = ConnectPlan.remainingMillis(deadline, System.currentTimeMillis())
            if (remaining == 0L) {
                timedOut = true
                break
            }
            val socket = try {
                createSocket(device, uuid, attempt)
            } catch (t: Throwable) {
                lastError = unwrap(t)
                if (lastError is SecurityException) break
                continue
            }
            connecting.add(socket)
            val fired = AtomicBoolean(false)
            val timer = watchdog?.schedule(
                {
                    fired.set(true)
                    closeQuietly(socket)
                },
                remaining,
                TimeUnit.MILLISECONDS,
            )
            try {
                socket.connect()
                timer?.cancel(false)
                connecting.remove(socket)
                if (fired.get()) throw IOException("Connect timed out")
                onConnected(id, socket, result)
                return
            } catch (t: Throwable) {
                timer?.cancel(false)
                connecting.remove(socket)
                closeQuietly(socket)
                lastError = t
                if (fired.get()) timedOut = true
                if (t is SecurityException || detached) break
            }
        }
        registry.release(id)
        val code = ErrorCodes.forConnect(lastError, timedOut)
        val message = if (code == ErrorCodes.TIMEOUT) {
            "No connection within ${timeoutMs}ms (${ErrorCodes.messageOf(lastError)})"
        } else {
            ErrorCodes.messageOf(lastError)
        }
        reply { result.error(code, message, lastError.javaClass.name) }
    }

    private fun createSocket(device: BluetoothDevice, uuid: UUID, attempt: ConnectAttempt): BluetoothSocket =
        when (attempt) {
            ConnectAttempt.SECURE -> device.createRfcommSocketToServiceRecord(uuid)
            ConnectAttempt.INSECURE -> device.createInsecureRfcommSocketToServiceRecord(uuid)
            // Hidden API: skips the SDP lookup that clone dongles answer wrongly.
            ConnectAttempt.CHANNEL_1_SECURE -> device.javaClass
                .getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                .invoke(device, 1) as BluetoothSocket
            ConnectAttempt.CHANNEL_1_INSECURE -> device.javaClass
                .getMethod("createInsecureRfcommSocket", Int::class.javaPrimitiveType)
                .invoke(device, 1) as BluetoothSocket
        }

    private fun onConnected(id: String, socket: BluetoothSocket, result: Result) {
        if (detached) {
            closeQuietly(socket)
            registry.release(id)
            return
        }
        val connection = try {
            NativeConnection(
                id,
                socket,
                onData = { bytes -> emit(id, "data", bytes) },
                onEnd = { error -> onRemoteEnd(id, error) },
            )
        } catch (e: IOException) {
            closeQuietly(socket)
            registry.release(id)
            reply { result.error(ErrorCodes.CONNECT_FAILED, ErrorCodes.messageOf(e), null) }
            return
        }
        registry.add(id, connection)
        // Reply before reading so the Dart side knows the id before data arrives.
        reply { result.success(null) }
        connection.start()
    }

    /** The reader ended without a local close: the remote side dropped the link. */
    private fun onRemoteEnd(id: String, error: IOException?) {
        val connection = registry.remove(id) ?: return
        connection.close()
        emit(id, "closed", error?.let { ErrorCodes.messageOf(it) })
    }

    private fun emit(id: String, event: String, payload: Any?) {
        val map = hashMapOf<String, Any?>("id" to id, "event" to event)
        if (event == "data") map["bytes"] = payload else map["error"] = payload
        main.post { connectionSink?.success(map) }
    }

    private fun write(call: MethodCall, result: Result) {
        val id = call.argument<String>("id") ?: throw IllegalArgumentException("id is required")
        val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException("bytes is required")
        val connection = registry.get(id)
            ?: return result.error(ErrorCodes.NOT_CONNECTED, "No open connection '$id'", null)
        connection.write(bytes) { error ->
            reply {
                when (error) {
                    null -> result.success(null)
                    is ClosedQueueException -> result.error(ErrorCodes.NOT_CONNECTED, ErrorCodes.messageOf(error), null)
                    else -> result.error(ErrorCodes.forIo(error), ErrorCodes.messageOf(error), null)
                }
            }
        }
    }

    private fun disconnect(call: MethodCall, result: Result) {
        val id = call.argument<String>("id") ?: throw IllegalArgumentException("id is required")
        val connection = registry.remove(id)
            ?: return result.error(ErrorCodes.NOT_CONNECTED, "No open connection '$id'", null)
        val pool = io
        if (pool == null) {
            connection.close()
            return result.success(null)
        }
        pool.execute {
            connection.close()
            reply { result.success(null) }
        }
    }

    // endregion

    private fun reply(block: () -> Unit) {
        main.post {
            if (!detached) block()
        }
    }

    private fun unwrap(t: Throwable): Throwable =
        if (t is InvocationTargetException) t.cause ?: t else t

    private fun closeQuietly(socket: BluetoothSocket) {
        try {
            socket.close()
        } catch (_: IOException) {
        }
    }

    companion object {
        private const val PREFIX = "dev.abdeldjalilchougui/bluetooth_spp"
        private const val REQUEST_ENABLE_CODE = 0x5350
        private const val SPP_UUID = "00001101-0000-1000-8000-00805F9B34FB"
        private const val DEFAULT_TIMEOUT_MS = 15000L
    }
}
