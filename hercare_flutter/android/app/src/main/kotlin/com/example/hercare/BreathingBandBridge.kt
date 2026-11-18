package com.hercare.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** Live Heart Rate Service receiver. Device identifiers and readings stay in memory. */
@SuppressLint("MissingPermission")
internal class BreathingBandBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val main = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "com.hercare/breathing_band")
    private val events = EventChannel(messenger, "com.hercare/breathing_band/events")
    private val adapter get() = activity.getSystemService(BluetoothManager::class.java)?.adapter
    private var sink: EventChannel.EventSink? = null
    private val devices = linkedMapOf<String, BluetoothDevice>()
    private var scanner: BluetoothLeScanner? = null
    private var scan: ScanCallback? = null
    private var connection: BluetoothGatt? = null
    private var pendingPermission = false
    private var permissionRequestInFlight = false
    private val scanTimeout = Runnable {
        endScan()
        status(if (devices.isEmpty()) "not_found" else "choose")
    }
    private val readingTimeout = Runnable { stop(); status("no_reading") }

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                sink = eventSink
            }
            override fun onCancel(arguments: Any?) {
                stop()
                sink = null
            }
        })
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "scan" -> prepareScan()
                "connect" -> connect(call.argument<String>("id"))
                "stop" -> stop()
                else -> { result.notImplemented(); return@setMethodCallHandler }
            }
            result.success(null)
        }
    }

    private fun status(value: String) = sink?.success(mapOf("status" to value))

    private fun hasPermissions() = PERMISSIONS.all {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    private fun prepareScan() {
        stop()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            status("unsupported")
        } else if (hasPermissions()) {
            startScan()
        } else {
            pendingPermission = true
            status("permission")
            if (!permissionRequestInFlight) {
                permissionRequestInFlight = true
                activity.requestPermissions(PERMISSIONS, REQUEST)
            }
        }
    }

    fun onPermissionResult(requestCode: Int) {
        if (requestCode != REQUEST) return
        permissionRequestInFlight = false
        if (!pendingPermission) return
        pendingPermission = false
        if (hasPermissions()) startScan() else status("denied")
    }

    private fun startScan() {
        try {
            val radio = adapter
            if (radio == null) { status("unsupported"); return }
            if (!radio.isEnabled) { status("bluetooth_off"); return }
            val source = radio.bluetoothLeScanner
            if (source == null) { status("bluetooth_off"); return }
            val callback = object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult) {
                    main.post {
                        if (scan !== this) return@post
                        val record = result.scanRecord ?: return@post
                        val name = record.deviceName ?: runCatching { result.device.name }.getOrNull()
                        val sharesHeartRate = ParcelUuid(HEART_RATE) in record.serviceUuids.orEmpty()
                        if (sharesHeartRate || name?.startsWith("Xiaomi Smart Band", true) == true) {
                            addDevice(result.device, name)
                        }
                    }
                }

                override fun onScanFailed(errorCode: Int) {
                    main.post {
                        if (scan === this) { endScan(); status(if (devices.isEmpty()) "scan_failed" else "choose") }
                    }
                }
            }
            scanner = source
            scan = callback
            status("scanning")
            // A known Xiaomi device can expose the service only after connection.
            radio.bondedDevices.forEach { device ->
                val name = device.name
                if (name?.startsWith("Xiaomi Smart Band", true) == true) addDevice(device, name)
            }
            source.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback)
            main.postDelayed(scanTimeout, 10_000)
        } catch (_: SecurityException) {
            endScan()
            status("denied")
        } catch (_: IllegalStateException) {
            endScan()
            status("scan_failed")
        }
    }

    private fun addDevice(device: BluetoothDevice, name: String?) {
        if (devices.size >= 12 || devices.containsValue(device)) return
        val id = devices.size.toString()
        devices[id] = device
        sink?.success(mapOf("device" to mapOf(
            "id" to id, "name" to (name?.trim()?.take(48)?.takeIf { it.isNotEmpty() } ?: "Heart-rate sensor"),
        )))
    }

    private fun connect(id: String?) {
        val device = devices[id] ?: return
        endScan()
        closeConnection()
        try {
            status("connecting")
            connection = device.connectGatt(activity, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            if (connection == null) { status("connection_failed"); return }
            main.postDelayed(readingTimeout, 20_000)
        } catch (_: SecurityException) {
            status("denied")
        } catch (_: IllegalStateException) {
            status("connection_failed")
        }
    }

    private fun fail(gatt: BluetoothGatt, reason: String) {
        if (connection !== gatt) return
        closeConnection()
        status(reason)
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, result: Int, state: Int) {
            main.post {
                if (connection !== gatt) return@post
                if (result != BluetoothGatt.GATT_SUCCESS || state == BluetoothProfile.STATE_DISCONNECTED) {
                    fail(gatt, "connection_failed")
                } else if (state == BluetoothProfile.STATE_CONNECTED &&
                    !runCatching { gatt.discoverServices() }.getOrDefault(false)) {
                    fail(gatt, "connection_failed")
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, result: Int) {
            main.post {
                if (connection !== gatt) return@post
                if (result != BluetoothGatt.GATT_SUCCESS || !subscribe(gatt)) {
                    fail(gatt, "no_service")
                }
            }
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, result: Int) {
            main.post {
                if (connection === gatt && result != BluetoothGatt.GATT_SUCCESS) fail(gatt, "no_service")
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            if (characteristic.uuid == MEASUREMENT) receive(gatt, value)
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < 33 && characteristic.uuid == MEASUREMENT) {
                characteristic.value?.let { receive(gatt, it) }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun subscribe(gatt: BluetoothGatt): Boolean = runCatching {
        val measurement = gatt.getService(HEART_RATE)?.getCharacteristic(MEASUREMENT) ?: return false
        val descriptor = measurement.getDescriptor(CONFIGURATION) ?: return false
        if (!gatt.setCharacteristicNotification(measurement, true)) return false
        val value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        if (Build.VERSION.SDK_INT >= 33) {
            gatt.writeDescriptor(descriptor, value) == BluetoothStatusCodes.SUCCESS
        } else {
            descriptor.value = value
            gatt.writeDescriptor(descriptor)
        }
    }.getOrDefault(false)

    private fun receive(gatt: BluetoothGatt, data: ByteArray) {
        if (data.size < 2) return
        val flags = data[0].toInt() and 0xff
        if ((flags and 6) == 4) return // contact detection supported and contact lost
        val low = data[1].toInt() and 0xff
        val rate = if ((flags and 1) == 0) low else {
            if (data.size < 3) return
            low or ((data[2].toInt() and 0xff) shl 8)
        }
        if (rate !in 1..300) return
        // Heart Rate Measurement (0x2A37): after the rate, optional energy-expended (bit 3, uint16),
        // then optional RR intervals (bit 4), uint16 each in 1/1024 s. Converted to ms for HRV.
        var offset = if ((flags and 1) == 0) 2 else 3
        if ((flags and 8) != 0) offset += 2
        val intervals = ArrayList<Int>()
        if ((flags and 16) != 0) {
            while (offset + 1 < data.size && intervals.size < 16) {
                val raw = (data[offset].toInt() and 0xff) or ((data[offset + 1].toInt() and 0xff) shl 8)
                val ms = (raw * 1000L / 1024L).toInt()
                if (ms in 250..2000) intervals.add(ms)
                offset += 2
            }
        }
        main.post {
            if (connection !== gatt) return@post
            main.removeCallbacks(readingTimeout)
            main.postDelayed(readingTimeout, 12_000)
            sink?.success(mapOf("status" to "live", "bpm" to rate, "rr" to intervals))
        }
    }

    private fun endScan() {
        main.removeCallbacks(scanTimeout)
        val callback = scan
        scan = null
        if (callback != null) runCatching { scanner?.stopScan(callback) }
        scanner = null
    }

    private fun closeConnection() {
        main.removeCallbacks(readingTimeout)
        val old = connection
        connection = null
        if (old != null) {
            runCatching { old.disconnect() }
            runCatching { old.close() }
        }
    }

    fun stop() {
        pendingPermission = false
        endScan()
        closeConnection()
        devices.clear()
        status("idle")
    }

    fun dispose() {
        stop()
        sink = null
        events.setStreamHandler(null)
        methods.setMethodCallHandler(null)
    }

    companion object {
        private const val REQUEST = 7143
        private val PERMISSIONS = arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        private val HEART_RATE = uuid("180d")
        private val MEASUREMENT = uuid("2a37")
        private val CONFIGURATION = uuid("2902")
        private fun uuid(short: String) = UUID.fromString("0000$short-0000-1000-8000-00805f9b34fb")
    }
}
