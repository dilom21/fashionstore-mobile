package com.example.fashionstore_mobile.virtualtryon

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * CU26 - Vestidor Virtual (Etapas 2A/2C).
 *
 * Canal `com.vantermen/pose_landmarker`: inicializa o libera el PoseLandmarker
 * COMPARTIDO. La instancia la crea y la posee `MainActivity` y se inyecta aquí
 * (no hay singletons globales ni un PoseLandmarker por frame).
 *
 * El canal NUNCA transporta imágenes, `ImageProxy` ni frames de la cámara.
 */
class PoseLandmarkerChannel(
    engine: FlutterEngine,
    private val manager: PoseLandmarkerManager,
) : MethodChannel.MethodCallHandler {

    private val channel =
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler(this@PoseLandmarkerChannel)
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_INITIALIZE -> initialize(result)
            METHOD_CLOSE -> close(result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        try {
            result.success(manager.initialize())
        } catch (error: Throwable) {
            // Se reporta el mensaje real: no se oculta la causa.
            result.error(
                ERROR_INITIALIZE,
                error.message ?: error.toString(),
                error.stackTraceToString(),
            )
        }
    }

    private fun close(result: MethodChannel.Result) {
        try {
            manager.close()
            result.success(true)
        } catch (error: Throwable) {
            result.error(
                ERROR_CLOSE,
                error.message ?: error.toString(),
                error.stackTraceToString(),
            )
        }
    }

    /**
     * Libera únicamente el handler del canal: el PoseLandmarker pertenece a
     * `MainActivity`, que es quien lo cierra en `cleanUpFlutterEngine`.
     */
    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        /** Nombre del canal compartido con `PoseLandmarkerService` (Flutter). */
        const val CHANNEL_NAME = "com.vantermen/pose_landmarker"

        private const val METHOD_INITIALIZE = "initializePoseLandmarker"
        private const val METHOD_CLOSE = "closePoseLandmarker"

        private const val ERROR_INITIALIZE = "POSE_LANDMARKER_INIT_FAILED"
        private const val ERROR_CLOSE = "POSE_LANDMARKER_CLOSE_FAILED"
    }
}

