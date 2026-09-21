package com.example.fashionstore_mobile.virtualtryon

import android.content.Context
import android.util.Log
import android.view.View
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.platform.PlatformView
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * CU26 - Vestidor Virtual (Etapas 2B/2C).
 *
 * Vista nativa de cámara embebida en Flutter mediante PlatformView: CameraX
 * (`PreviewView` + `ImageAnalysis`) con la cámara frontal (o la trasera como
 * respaldo si el dispositivo no tiene frontal).
 *
 * El frame NO se procesa aquí: se delega al [PoseLandmarkerManager] compartido,
 * que lanza MediaPipe en modo LIVE_STREAM. Aquí nunca se espera el resultado,
 * así que la cámara no se bloquea.
 */
class PoseCameraPlatformView(
    context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val manager: PoseLandmarkerManager,
) : PlatformView {

    private val previewView: PreviewView = PreviewView(context).apply {
        // TextureView (COMPATIBLE): necesaria para que el preview se vea al
        // integrarse en la capa de textura del PlatformView de Flutter.
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }

    /** Analizador dedicado en su propio hilo (uno solo, sin acumulación). */
    private val backgroundExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private var cameraProvider: ProcessCameraProvider? = null
    private var preview: Preview? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var liberada = false

    init {
        enlazarCamara(context.applicationContext)
    }

    /** Enlaza Preview + ImageAnalysis al ciclo de vida de la Activity. */
    private fun enlazarCamara(context: Context) {
        val futuro = ProcessCameraProvider.getInstance(context)
        futuro.addListener({
            val provider = try {
                futuro.get()
            } catch (error: Throwable) {
                Log.e(TAG, "No se pudo obtener ProcessCameraProvider", error)
                return@addListener
            }
            if (liberada) return@addListener

            try {
                val esFrontal = provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)
                val selector = when {
                    esFrontal -> CameraSelector.DEFAULT_FRONT_CAMERA
                    provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) ->
                        CameraSelector.DEFAULT_BACK_CAMERA
                    else -> null
                }
                if (selector == null) {
                    Log.w(TAG, "El dispositivo no tiene cámaras disponibles")
                    return@addListener
                }

                val nuevoPreview = Preview.Builder().build()
                nuevoPreview.setSurfaceProvider(previewView.surfaceProvider)

                // KEEP_ONLY_LATEST: si MediaPipe va más lento que la cámara se
                // descartan los frames viejos (sin acumulación de buffers).
                // RGBA_8888: formato que necesita la conversión a MPImage.
                val nuevoAnalisis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .build()
                nuevoAnalisis.setAnalyzer(backgroundExecutor) { imageProxy: ImageProxy ->
                    procesarFrame(imageProxy, esFrontal)
                }

                cameraProvider = provider
                preview = nuevoPreview
                imageAnalysis = nuevoAnalisis

                // Se reutiliza el provider: libera enlaces previos (por ejemplo
                // si se reabre la pantalla) antes de enlazar los use cases.
                provider.unbindAll()
                provider.bindToLifecycle(
                    lifecycleOwner,
                    selector,
                    nuevoPreview,
                    nuevoAnalisis,
                )
            } catch (error: Throwable) {
                Log.e(TAG, "No se pudo iniciar la cámara con CameraX", error)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    /**
     * Entrega el frame a MediaPipe. El cierre del `ImageProxy` está garantizado
     * por el manager (`finally`), incluso si MediaPipe aún no está listo.
     */
    private fun procesarFrame(imageProxy: ImageProxy, esCamaraFrontal: Boolean) {
        if (liberada) {
            // Callback que llega después del dispose: se descarta con seguridad.
            imageProxy.close()
            return
        }
        manager.detectLiveStream(imageProxy, esCamaraFrontal)
    }

    override fun getView(): View = previewView

    /** Libera CameraX y el analizador al destruirse la vista. */
    override fun dispose() {
        liberada = true
        try {
            // Deja de recibir frames antes de desenlazar la cámara.
            imageAnalysis?.clearAnalyzer()
        } catch (error: Throwable) {
            Log.w(TAG, "No se pudo limpiar el analizador de CameraX", error)
        }
        imageAnalysis = null
        // El hilo de análisis ya no acepta más trabajo.
        backgroundExecutor.shutdown()
        try {
            cameraProvider?.unbindAll()
        } catch (error: Throwable) {
            Log.w(TAG, "No se pudo desenlazar CameraX", error)
        }
        cameraProvider = null
        preview?.setSurfaceProvider(null)
        preview = null
    }

    companion object {
        private const val TAG = "PoseCameraPlatformView"
    }
}
