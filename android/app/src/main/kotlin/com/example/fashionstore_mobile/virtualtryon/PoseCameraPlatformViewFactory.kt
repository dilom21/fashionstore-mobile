package com.example.fashionstore_mobile.virtualtryon

import android.content.Context
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * CU26 - Vestidor Virtual (Etapas 2B/2C).
 *
 * Fábrica de [PoseCameraPlatformView]: crea una instancia nueva por cada
 * `AndroidView` de Flutter (es decir, cada vez que se abre la pantalla).
 *
 * @param lifecycleOwner ciclo de vida al que CameraX enlaza la cámara. Se pasa
 *        `MainActivity`, que al extender `FlutterActivity` implementa
 *        `LifecycleOwner`.
 * @param manager PoseLandmarker COMPARTIDO (lo posee `MainActivity`): la vista
 *        no crea instancias propias de MediaPipe.
 */
class PoseCameraPlatformViewFactory(
    private val lifecycleOwner: LifecycleOwner,
    private val manager: PoseLandmarkerManager,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        PoseCameraPlatformView(context, lifecycleOwner, manager)

    companion object {
        /** Identificador usado por `AndroidView(viewType: ...)` en Flutter. */
        const val VIEW_TYPE = "com.vantermen/pose_camera_view"
    }
}

