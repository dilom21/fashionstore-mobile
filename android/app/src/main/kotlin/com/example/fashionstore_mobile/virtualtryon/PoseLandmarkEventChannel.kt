package com.example.fashionstore_mobile.virtualtryon

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.tasks.components.containers.Landmark
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * CU26 - Vestidor Virtual (Etapa 2C).
 *
 * Canal `com.vantermen/pose_landmarks`: envía a Flutter el resultado de
 * MediaPipe (LIVE_STREAM) como datos NUMÉRICOS.
 *
 * NUNCA se envían imágenes: ni `Bitmap`, ni `ByteArray` del frame, ni
 * `ImageProxy`, ni `MPImage`.
 *
 * Los eventos hacia Flutter se limitan a ~10 por segundo
 * ([INTERVALO_MINIMO_MS]): MediaPipe sigue procesando a plena velocidad, solo
 * se evita saturar los rebuilds de la interfaz.
 */
class PoseLandmarkEventChannel(
    engine: FlutterEngine,
    private val manager: PoseLandmarkerManager,
) : EventChannel.StreamHandler {

    private val canal =
        EventChannel(engine.dartExecutor.binaryMessenger, NOMBRE_CANAL).apply {
            setStreamHandler(this@PoseLandmarkEventChannel)
        }

    private val hiloPrincipal = Handler(Looper.getMainLooper())

    /** Único sink activo (null cuando Flutter cancela la suscripción). */
    @Volatile
    private var sink: EventChannel.EventSink? = null

    private var ultimoEnvioMs = 0L

    init {
        // MediaPipe entrega los resultados en su propio hilo: aquí solo se
        // construye el mapa y se publica en el hilo principal.
        manager.onResultado = { resultado, frameInfo ->
            emitir(resultado, frameInfo)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        ultimoEnvioMs = 0L
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** Construye el evento y lo publica en el hilo principal de Flutter. */
    private fun emitir(
        resultado: PoseLandmarkerResult,
        frameInfo: PoseLandmarkerManager.FrameInfo,
    ) {
        // Tiempo de inferencia real: se mide al recibir el resultado.
        val tiempoInferenciaMs = SystemClock.uptimeMillis() - resultado.timestampMs()

        val ahora = SystemClock.uptimeMillis()
        if (ahora - ultimoEnvioMs < INTERVALO_MINIMO_MS) return
        ultimoEnvioMs = ahora

        val evento = try {
            construirEvento(resultado, frameInfo, tiempoInferenciaMs)
        } catch (error: Throwable) {
            Log.e(TAG, "No se pudo construir el evento de landmarks", error)
            return
        }

        hiloPrincipal.post {
            sink?.success(evento)
        }
    }

    private fun construirEvento(
        resultado: PoseLandmarkerResult,
        frameInfo: PoseLandmarkerManager.FrameInfo,
        tiempoInferenciaMs: Long,
    ): Map<String, Any?> {
        // numPoses = 1: se usa únicamente la primera pose detectada.
        val puntos = resultado.landmarks().firstOrNull().orEmpty()
        val puntosMundo = resultado.worldLandmarks().firstOrNull().orEmpty()

        return hashMapOf(
            "poseDetected" to puntos.isNotEmpty(),
            "timestampMs" to resultado.timestampMs(),
            "inferenceTimeMs" to tiempoInferenciaMs,
            "landmarkCount" to puntos.size,
            "imageWidth" to frameInfo.anchoImagen,
            "imageHeight" to frameInfo.altoImagen,
            "isFrontCamera" to frameInfo.esCamaraFrontal,
            "landmarks" to puntos.mapIndexed { indice, punto ->
                mapaNormalizado(indice, punto)
            },
            "worldLandmarks" to puntosMundo.mapIndexed { indice, punto ->
                mapaMundo(indice, punto)
            },
        )
    }

    /** Landmarks normalizados (x/y/z en 0..1). `visibility`/`presence` son Optional. */
    private fun mapaNormalizado(
        indice: Int,
        punto: NormalizedLandmark,
    ): Map<String, Any?> = mapOf(
        "index" to indice,
        "x" to punto.x().toDouble(),
        "y" to punto.y().toDouble(),
        "z" to punto.z().toDouble(),
        "visibility" to punto.visibility().orElse(null)?.toDouble(),
        "presence" to punto.presence().orElse(null)?.toDouble(),
    )

    /** Landmarks en coordenadas del mundo (metros). */
    private fun mapaMundo(indice: Int, punto: Landmark): Map<String, Any?> = mapOf(
        "index" to indice,
        "x" to punto.x().toDouble(),
        "y" to punto.y().toDouble(),
        "z" to punto.z().toDouble(),
        "visibility" to punto.visibility().orElse(null)?.toDouble(),
        "presence" to punto.presence().orElse(null)?.toDouble(),
    )

    /** Libera el handler del canal y desengancha el listener del manager. */
    fun dispose() {
        sink = null
        manager.onResultado = null
        canal.setStreamHandler(null)
    }

    companion object {
        /** Nombre del canal compartido con `PoseLandmarkStreamService` (Flutter). */
        const val NOMBRE_CANAL = "com.vantermen/pose_landmarks"

        /** ~10 eventos por segundo hacia Flutter. */
        private const val INTERVALO_MINIMO_MS = 100L

        private const val TAG = "PoseLandmarkEventChannel"
    }
}
