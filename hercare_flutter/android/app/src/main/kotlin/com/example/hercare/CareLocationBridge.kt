package com.hercare.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max
import kotlin.math.round

/** Explicit, foreground, one-shot approximate location; no listeners or storage. */
class CareLocationBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val PERMISSION_REQUEST = 42871
        private const val PERMISSION_DEADLINE_MS = 45_000L
        private const val ACQUISITION_DEADLINE_MS = 10_000L
        private const val MAX_AGE_MS = 120_000L
        private const val MAX_FUTURE_MS = 30_000L
    }

    private val channel = MethodChannel(messenger, "com.hercare/care_location")
    private val handler = Handler(Looper.getMainLooper())
    private val manager = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
    private var pending: MethodChannel.Result? = null
    private var cancellation: CancellationSignal? = null
    private var deadline: Runnable? = null
    private var waitingForPermission = false
    private var permissionOutstanding = false
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentApproximatePosition" -> request(result)
                "cancelCurrentApproximatePosition" -> {
                    cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasPermission(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
        activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED

    private fun request(result: MethodChannel.Result) {
        if (disposed || pending != null || activity.isFinishing || activity.isDestroyed) {
            result.success(null)
            return
        }
        if (manager == null || (!hasPermission() && permissionOutstanding)) {
            result.success(null)
            return
        }
        pending = result
        if (hasPermission()) {
            acquire(result)
            return
        }
        waitingForPermission = true
        permissionOutstanding = true
        setDeadline(result, PERMISSION_DEADLINE_MS)
        try {
            // Request only approximate access. Never upgrade to precise/background.
            activity.requestPermissions(
                arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION), PERMISSION_REQUEST,
            )
        } catch (_: RuntimeException) {
            permissionOutstanding = false
            finish(result, null)
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        permissionOutstanding = false
        if (!waitingForPermission) return
        waitingForPermission = false
        val result = pending ?: return
        if (grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED || !hasPermission()) {
            finish(result, null)
            return
        }
        acquire(result)
    }

    private fun setDeadline(result: MethodChannel.Result, delayMs: Long) {
        deadline?.let(handler::removeCallbacks)
        deadline = Runnable { finish(result, null) }.also {
            handler.postDelayed(it, delayMs)
        }
    }

    private fun acquire(result: MethodChannel.Result) {
        if (disposed || pending !== result || !hasPermission()) {
            finish(result, null)
            return
        }
        val locationManager = manager ?: return finish(result, null)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && !locationManager.isLocationEnabled) {
                finish(result, null)
                return
            }
            val providers = locationManager.allProviders
            // Fused is an optional Android provider, not a Google Places/location SDK.
            // No GPS/fine-location request is made when network is unavailable.
            val provider = listOf(LocationManager.NETWORK_PROVIDER, "fused").firstOrNull {
                providers.contains(it) && locationManager.isProviderEnabled(it)
            }
            if (provider == null) {
                finish(result, null)
                return
            }
            setDeadline(result, ACQUISITION_DEADLINE_MS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val signal = CancellationSignal()
                cancellation = signal
                locationManager.getCurrentLocation(provider, signal, activity.mainExecutor) { location ->
                    if (pending === result) finish(result, approximate(location))
                }
            } else {
                // Older devices have no bounded one-shot API: only accept a recent
                // existing fix, never install a continuous/persistent listener.
                val candidates = listOf(provider, LocationManager.PASSIVE_PROVIDER)
                    .distinct().filter(providers::contains)
                    .mapNotNull {
                        try {
                            approximate(locationManager.getLastKnownLocation(it))
                        } catch (_: RuntimeException) {
                            null // One unavailable provider cannot hide another valid fix.
                        }
                    }
                val newest = candidates.maxByOrNull { it["recorded_at"] as Long }
                finish(result, newest)
            }
        } catch (_: RuntimeException) {
            // Permission withdrawal, missing providers and disabled services fall
            // back to public city/Maps help without exposing logs or old fixes.
            finish(result, null)
        }
    }

    private fun approximate(location: Location?): Map<String, Any>? {
        if (location == null || !hasPermission() || !location.hasAccuracy()) return null
        val latitude = location.latitude
        val longitude = location.longitude
        val actualAccuracy = location.accuracy.toDouble()
        val age = System.currentTimeMillis() - location.time
        val elapsedAge = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000
        if (!latitude.isFinite() || !longitude.isFinite() ||
            latitude !in -90.0..90.0 || longitude !in -180.0..180.0 ||
            !actualAccuracy.isFinite() || actualAccuracy < 0 || actualAccuracy > 10_000 ||
            location.time <= 0 || location.elapsedRealtimeNanos <= 0 ||
            age !in -MAX_FUTURE_MS..MAX_AGE_MS ||
            elapsedAge !in -MAX_FUTURE_MS..MAX_AGE_MS) return null
        return mapOf(
            "latitude" to round(latitude * 100) / 100,
            "longitude" to round(longitude * 100) / 100,
            "accuracy" to max(actualAccuracy, 1_500.0),
            // Keep the real fix time; never relabel an old fix as "now".
            "recorded_at" to location.time,
        )
    }

    private fun finish(result: MethodChannel.Result, data: Map<String, Any>?) {
        if (pending !== result) return
        pending = null
        waitingForPermission = false
        deadline?.let(handler::removeCallbacks)
        deadline = null
        val signal = cancellation
        cancellation = null
        signal?.cancel()
        result.success(data)
    }

    /** Called on activity stop, explicit UI cancellation and disposal. */
    fun cancel() {
        val result = pending ?: return
        finish(result, null)
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        cancel()
        channel.setMethodCallHandler(null)
    }
}
