package com.hercare.app

import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.min

internal class PostureBridge(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.hercare/posture")
    private var detector: PoseDetector? = null
    private var generation = 0

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    detector?.close()
                    detector = PoseDetection.getClient(
                        PoseDetectorOptions.Builder()
                            .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
                            .build()
                    )
                    result.success(++generation)
                }
                "inspect" -> inspect(call, result)
                "close" -> {
                    if (call.argument<Int>("session") == generation) {
                        detector?.close()
                        detector = null
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun inspect(call: MethodCall, result: MethodChannel.Result) {
        val active = detector
        val bytes = call.argument<ByteArray>("bytes")
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        val rotation = call.argument<Int>("rotation")
        if (active == null || call.argument<Int>("session") != generation ||
            bytes == null || width !in 1..1920 || height !in 1..1920 ||
            bytes.size != width * height * 3 / 2 || rotation == null ||
            rotation !in 0..270 || rotation % 90 != 0) {
            result.success("unavailable")
            return
        }
        try {
            val image = InputImage.fromByteArray(bytes, width, height, rotation, InputImage.IMAGE_FORMAT_NV21)
            active.process(image).addOnSuccessListener { pose ->
                val left = pose.getPoseLandmark(PoseLandmark.LEFT_SHOULDER)
                val right = pose.getPoseLandmark(PoseLandmark.RIGHT_SHOULDER)
                if (left == null || right == null || left.inFrameLikelihood < .7f || right.inFrameLikelihood < .7f) {
                    result.success("framing")
                    return@addOnSuccessListener
                }
                val dx = abs(left.position.x - right.position.x).toDouble()
                val dy = abs(left.position.y - right.position.y).toDouble()
                result.success(when {
                    hypot(dx, dy) < min(width, height) * .14 -> "framing"
                    atan2(dy, dx) > .30 -> "tilted"
                    else -> "visible"
                })
            }.addOnFailureListener { result.success("unavailable") }
              .addOnCanceledListener { result.success("unavailable") }
        } catch (_: RuntimeException) {
            result.success("unavailable")
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        detector?.close()
        detector = null
    }
}
