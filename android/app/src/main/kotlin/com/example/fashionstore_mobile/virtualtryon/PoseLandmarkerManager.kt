package com.example.fashionstore_mobile.virtualtryon

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ImageProxy
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult

/**
 * CU26 - Vestidor Virtual (Etapa 2C).
 *
 * Instancia ÚNICA y compartida del PoseLandmarker de MediaPipe Tasks Vision en
 * modo `LIVE_STREAM`. La posee `MainActivity` y la comparten el canal de
 * diagnóstico (2A) y la vista de cámara (2B/2C). No hay singletons globales ni
 * un PoseLandmarker por frame.
 *
 * Responsabilidades:
 * - Crear/liberar el PoseLandmarker.
 * - Convertir cada `ImageProxy` de CameraX (RGBA_8888) en MPImage y lanzar
 *   `detectAsync` sin bloquear la cámara.
 *
 * NO envía imágenes a Flutter: solo resultados numéricos.
 */
class PoseLandmarkerManager(private val context: Context) {

    /** Metadatos del frame que se envía a MediaPipe (para el diagnóstico). */
    data class FrameInfo(
        val anchoImagen: Int,
        val altoImagen: Int,
        val esCamaraFrontal: Boolean,
        val timestampMs: Long,
    )

    /**
     * Resultado LIVE_STREAM + metadatos del frame. Lo consume
     * `PoseLandmarkEventChannel`. Se ejecuta en el hilo que usa MediaPipe, así
     * que quien lo consuma debe saltar al hilo principal si toca Flutter.
     */
    var onResultado: ((PoseLandmarkerResult, FrameInfo) -> Unit)? = null

    /** Errores internos de MediaPipe (no detienen la cámara). */
    var onError: ((RuntimeException) -> Unit)? = null

    private var poseLandmarker: PoseLandmarker? = null

    /** Metadatos del último frame enviado (escrito por el analizador). */
    @Volatile
    private var ultimoFrame: FrameInfo? = null

    /** Indica si ya hay un PoseLandmarker cargado. */
    val isInitialized: Boolean
        get() = poseLandmarker != null

    /**
     * Crea el PoseLandmarker usando el modelo de assets.
     *
     * @return `true` si quedó inicializado.
     * @throws Throwable si la carga falla: el mensaje real se propaga para no
     *         ocultar la causa (se reporta desde el puente como PlatformException).
     */
    @Synchronized
    fun initialize(): Boolean {
        // Evita crear instancias innecesarias si ya está listo.
        if (poseLandmarker != null) return true

        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(MODEL_ASSET_PATH)
            .build()

        // El RunningMode se fija al crear el landmarker: no puede cambiarse
        // dinámicamente (no se crea en IMAGE y luego se pasa a LIVE_STREAM).
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .setOutputSegmentationMasks(false)
            .setResultListener { resultado, _ ->
                val frame = ultimoFrame
                if (frame != null) onResultado?.invoke(resultado, frame)
            }
            .setErrorListener { error ->
                Log.e(TAG, "Error de MediaPipe: ${error.message}", error)
                onError?.invoke(error)
            }
            .build()

        poseLandmarker = PoseLandmarker.createFromOptions(context, options)
        return true
    }


    /**
     * Convierte el frame de CameraX y lanza la inferencia asíncrona.
     *
     * No bloquea esperando el resultado: `detectAsync` encola el frame y el
     * resultado llega después por el listener de resultados.
     *
     * El `imageProxy` se cierra SIEMPRE y exactamente una vez.
     *
     * @return `true` si el frame llegó a enviarse a MediaPipe.
     */
    fun detectLiveStream(imageProxy: ImageProxy, esCamaraFrontal: Boolean): Boolean {
        var enviado = false
        try {
            val landmarker = poseLandmarker
            if (landmarker == null) {
                // MediaPipe todavía no está listo: se descarta el frame.
                return false
            }

            // 1. Datos que hacen falta ANTES de cerrar el ImageProxy.
            val ancho = imageProxy.width
            val alto = imageProxy.height
            val rotacion = imageProxy.imageInfo.rotationDegrees
            val timestampMs = SystemClock.uptimeMillis()

            // 2. Bitmap ARGB_8888 del tamaño del frame RGBA_8888 de CameraX.
            val original = Bitmap.createBitmap(ancho, alto, Bitmap.Config.ARGB_8888)
            original.copyPixelsFromBuffer(imageProxy.planes[0].buffer)

            // 3. Rotación y, en cámara frontal, espejo horizontal para que las
            //    coordenadas coincidan con el preview que ve el usuario.
            val matriz = Matrix().apply {
                postRotate(rotacion.toFloat())
                if (esCamaraFrontal) {
                    postScale(-1f, 1f, ancho.toFloat(), alto.toFloat())
                }
            }
            val orientado =
                Bitmap.createBitmap(original, 0, 0, ancho, alto, matriz, true)
            if (orientado !== original) original.recycle()

            // 4. Bitmap -> MPImage (formato que espera MediaPipe Tasks).
            val mpImage = BitmapImageBuilder(orientado).build()

            ultimoFrame = FrameInfo(
                anchoImagen = mpImage.width,
                altoImagen = mpImage.height,
                esCamaraFrontal = esCamaraFrontal,
                timestampMs = timestampMs,
            )

            // 5. Inferencia asíncrona (aquí NO se espera el resultado).
            landmarker.detectAsync(mpImage, timestampMs)
            enviado = true
        } catch (error: Throwable) {
            Log.e(TAG, "No se pudo preparar el frame para MediaPipe", error)
        } finally {
            imageProxy.close()
        }
        return enviado
    }

    /** Libera los recursos nativos. Es seguro llamarlo más de una vez. */
    @Synchronized
    fun close() {
        onResultado = null
        onError = null
        ultimoFrame = null
        try {
            poseLandmarker?.close()
        } catch (error: Throwable) {
            Log.w(TAG, "No se pudo cerrar el PoseLandmarker", error)
        }
        poseLandmarker = null
    }

    companion object {
        /** Ruta del modelo dentro de `android/app/src/main/assets`. */
        const val MODEL_ASSET_PATH = "pose_landmarker_lite.task"

        private const val TAG = "PoseLandmarkerManager"
    }
}
