package com.example.fashionstore_mobile

import com.example.fashionstore_mobile.virtualtryon.PoseCameraPlatformViewFactory
import com.example.fashionstore_mobile.virtualtryon.PoseLandmarkEventChannel
import com.example.fashionstore_mobile.virtualtryon.PoseLandmarkerChannel
import com.example.fashionstore_mobile.virtualtryon.PoseLandmarkerManager
import com.example.fashionstore_mobile.virtualtryon.VestidorPermissionsChannel
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * CU26 (Etapas 2A-2C).
 *
 * Es la dueña de la ÚNICA instancia de [PoseLandmarkerManager] y la comparte
 * con el MethodChannel de diagnóstico, el EventChannel de landmarks y la
 * PlatformView de cámara. Así se evita tener un PoseLandmarker por frame.
 */
class MainActivity : FlutterFragmentActivity() {

    private var poseLandmarkerManager: PoseLandmarkerManager? = null
    private var poseLandmarkerChannel: PoseLandmarkerChannel? = null
    private var poseLandmarkEventChannel: PoseLandmarkEventChannel? = null

    /** Permiso de cámara en runtime del Vestidor Virtual (CU26). */
    private var vestidorPermissionsChannel: VestidorPermissionsChannel? = null
    private var vestidorPermissionsMethodChannel: MethodChannel? = null

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

        // CU26 - Permiso de cámara en runtime: Flutter consulta/solicita el
        // permiso aquí ANTES de crear la vista de cámara. `this` recibe además
        // el resultado del diálogo del sistema (onRequestPermissionsResult).
        val permisos = VestidorPermissionsChannel(this)
        vestidorPermissionsChannel = permisos
        vestidorPermissionsMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VestidorPermissionsChannel.CHANNEL_NAME,
        ).also { it.setMethodCallHandler(permisos) }
    }

    /** Resultado del diálogo de permisos del sistema. */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        vestidorPermissionsChannel?.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Orden: primero los canales, al final MediaPipe.
        vestidorPermissionsMethodChannel?.setMethodCallHandler(null)
        vestidorPermissionsMethodChannel = null
        vestidorPermissionsChannel?.dispose()
        vestidorPermissionsChannel = null
        poseLandmarkEventChannel?.dispose()
        poseLandmarkEventChannel = null
        poseLandmarkerChannel?.dispose()
        poseLandmarkerChannel = null
        poseLandmarkerManager?.close()
        poseLandmarkerManager = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}


