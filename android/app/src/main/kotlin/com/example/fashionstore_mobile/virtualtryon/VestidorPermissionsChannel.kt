package com.example.fashionstore_mobile.virtualtryon

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * CU26 - Permiso de cámara en runtime para el Vestidor Virtual.
 *
 * Se resuelve en nativo (sin plugins externos) porque el proyecto compila con
 * `compileSdk = 36` y las versiones actuales de `permission_handler` exigen 37.
 *
 * Flutter NUNCA crea la vista de cámara antes de que este canal confirme
 * `granted`: así CameraX jamás intenta abrir la cámara sin permiso y no se
 * produce `CameraError(ERROR_SECURITY_EXCEPTION)`.
 *
 * El permiso sigue declarado en `AndroidManifest.xml`; esto solo gestiona la
 * concesión en tiempo de ejecución.
 */
class VestidorPermissionsChannel(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {

    /** Petición en curso: el `Result` que se responde en el callback. */
    private var pendingResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_HAS -> result.success(estadoActual())
            METHOD_REQUEST -> solicitar(result)
            METHOD_OPEN_SETTINGS -> result.success(abrirAjustes())
            else -> result.notImplemented()
        }
    }

    /**
     * Entrega el resultado del diálogo del sistema (lo llama MainActivity).
     *
     * Traduce el rechazo a `denied` o `permanentlyDenied` según si el sistema
     * permitiría volver a mostrar el diálogo.
     */
    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != REQUEST_CODE_CAMERA) return

        val concedido = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

        val estado = when {
            concedido -> ESTADO_CONCEDIDO
            !debeMostrarRacional() -> ESTADO_BLOQUEADO
            else -> ESTADO_DENEGADO
        }

        pendingResult?.success(estado)
        pendingResult = null
    }

    /** Libera el callback pendiente al destruir el motor de Flutter. */
    fun dispose() {
        pendingResult = null
    }

    /** Solicita el permiso (el sistema decide si muestra el diálogo). */
    private fun solicitar(result: MethodChannel.Result) {
        if (estadoActual() == ESTADO_CONCEDIDO) {
            result.success(ESTADO_CONCEDIDO)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            // Antes de Android 6 el permiso se concede al instalar.
            result.success(ESTADO_CONCEDIDO)
            return
        }

        // Una solicitud a la vez: la anterior se resuelve como denegada.
        pendingResult?.success(ESTADO_DENEGADO)
        pendingResult = result
        marcarSolicitado()
        activity.requestPermissions(
            arrayOf(Manifest.permission.CAMERA),
            REQUEST_CODE_CAMERA,
        )
    }

    /** Estado real del permiso sin mostrar ningún diálogo. */
    private fun estadoActual(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return ESTADO_CONCEDIDO

        val concedido = activity.checkSelfPermission(Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        if (concedido) return ESTADO_CONCEDIDO

        // Ya se pidió antes y el sistema no permite volver a preguntar:
        // solo se puede corregir desde Ajustes.
        if (yaSolicitado() && !debeMostrarRacional()) return ESTADO_BLOQUEADO

        return ESTADO_DENEGADO
    }

    /** `true` si el sistema permite volver a mostrar el diálogo. */
    private fun debeMostrarRacional(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return activity.shouldShowRequestPermissionRationale(
            Manifest.permission.CAMERA,
        )
    }

    /** Abre la pantalla de Ajustes de la aplicación. */
    private fun abrirAjustes(): Boolean = try {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", activity.packageName, null),
        )
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }

    private fun prefs() = activity.getSharedPreferences(
        PREFS_NAME,
        Activity.MODE_PRIVATE,
    )

    private fun yaSolicitado(): Boolean = prefs().getBoolean(KEY_SOLICITADO, false)

    private fun marcarSolicitado() {
        prefs().edit().putBoolean(KEY_SOLICITADO, true).apply()
    }

    companion object {
        /** Nombre del canal (debe coincidir con el servicio Dart). */
        const val CHANNEL_NAME = "com.vantermen/vestidor_permissions"

        private const val METHOD_HAS = "hasCameraPermission"
        private const val METHOD_REQUEST = "requestCameraPermission"
        private const val METHOD_OPEN_SETTINGS = "openAppSettings"

        private const val ESTADO_CONCEDIDO = "granted"
        private const val ESTADO_DENEGADO = "denied"
        private const val ESTADO_BLOQUEADO = "permanentlyDenied"

        private const val PREFS_NAME = "vestidor_permisos"
        private const val KEY_SOLICITADO = "camera_solicitado"

        /** Código propio para no chocar con otros permisos de la app. */
        const val REQUEST_CODE_CAMERA = 26_001
    }
}
