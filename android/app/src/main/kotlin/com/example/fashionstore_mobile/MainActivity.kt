package com.example.fashionstore_mobile

import com.example.fashionstore_mobile.virtualtryon.PoseCameraPlatformViewFactory
import com.example.fashionstore_mobile.virtualtryon.PoseLandmarkEventChannel
import com.example.fashionstore_mobile.virtualtryon.PoseLandmarkerChannel
import com.example.fashionstore_mobile.virtualtryon.PoseLandmarkerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * CU26 (Etapas 2A-2C).
 *
 * Es la dueña de la ÚNICA instancia de [PoseLandmarkerManager] y la comparte
 * con el MethodChannel de diagnóstico, el EventChannel de landmarks y la
 * PlatformView de cámara. Así se evita tener un PoseLandmarker por frame.
 */
class MainActivity : FlutterActivity() {

    private var poseLandmarkerManager: PoseLandmarkerManager? = null
    private var poseLandmarkerChannel: PoseLandmarkerChannel? = null
    private var poseLandmarkEventChannel: PoseLandmarkEventChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Instancia única compartida (sin singletons globales).
        val manager = PoseLandmarkerManager(applicationContext)
        poseLandmarkerManager = manager

        // Etapa 2A: inicialización/liberación de MediaPipe bajo demanda.
        poseLandmarkerChannel = PoseLandmarkerChannel(flutterEngine, manager)

        // Etapa 2C: resultados de landmarks hacia Flutter (solo números).
        poseLandmarkEventChannel = PoseLandmarkEventChannel(flutterEngine, manager)

        // Etapa 2B: vista nativa de cámara (CameraX + PreviewView) con análisis.
        // `this` (MainActivity) es el LifecycleOwner al que CameraX se enlaza.
        flutterEngine.platformViewsController.registry.registerViewFactory(
            PoseCameraPlatformViewFactory.VIEW_TYPE,
            PoseCameraPlatformViewFactory(this, manager),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Orden: primero los canales, al final MediaPipe.
        poseLandmarkEventChannel?.dispose()
        poseLandmarkEventChannel = null
        poseLandmarkerChannel?.dispose()
        poseLandmarkerChannel = null
        poseLandmarkerManager?.close()
        poseLandmarkerManager = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}


