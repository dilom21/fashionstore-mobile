import 'package:flutter/services.dart';

/// Estado del permiso de cámara visto por el Vestidor Virtual (CU26).
///
/// Traduce la respuesta nativa a algo legible para no repartir la lógica del
/// permiso entre las pantallas.
enum EstadoPermisoCamara {
  /// Todavía no se consultó (o la plataforma no lo informa).
  desconocido,

  /// Concedido: es lo ÚNICO que habilita crear la vista de cámara.
  concedido,

  /// Denegado, pero se puede volver a solicitar.
  denegado,

  /// Denegado permanentemente: solo se puede cambiar desde Ajustes.
  denegadoPermanente,

  /// Restringido por el sistema (política del dispositivo).
  restringido,
}

/// Permiso `android.permission.CAMERA` en runtime para el Vestidor Virtual.
///
/// Se resuelve con el canal nativo Kotlin del propio CU26
/// (`com.vantermen/vestidor_permissions`) y **sin plugins externos**: el
/// proyecto compila con `compileSdk = 36` y `permission_handler` 13 exige 37.
///
/// El vestidor NUNCA crea la vista nativa de cámara (CameraX) antes de obtener
/// [EstadoPermisoCamara.concedido]: así CameraX jamás intenta abrir la cámara
/// sin permiso y no se produce `SecurityException` /
/// `CameraError(ERROR_SECURITY_EXCEPTION)`.
///
/// El permiso sigue declarado en `AndroidManifest.xml`; esto solo gestiona la
/// concesión en tiempo de ejecución.
class CameraPermissionService {
  const CameraPermissionService();

  /// Nombre del canal (debe coincidir con `VestidorPermissionsChannel`).
  static const String canalPermisosVestidor =
      'com.vantermen/vestidor_permissions';

  static const MethodChannel _channel = MethodChannel(canalPermisosVestidor);

  static const String _metodoVerificar = 'hasCameraPermission';
  static const String _metodoSolicitar = 'requestCameraPermission';
  static const String _metodoAjustes = 'openAppSettings';

  /// Estados devueltos por Kotlin.
  static const String _estadoConcedido = 'granted';
  static const String _estadoDenegado = 'denied';
  static const String _estadoBloqueado = 'permanentlyDenied';

  /// Consulta el estado actual sin mostrar ningún diálogo del sistema.
  Future<EstadoPermisoCamara> verificar() async {
    try {
      final String? estado = await _channel.invokeMethod<String>(
        _metodoVerificar,
      );
      return _mapear(estado);
    } on MissingPluginException {
      return EstadoPermisoCamara.desconocido;
    } on PlatformException {
      return EstadoPermisoCamara.desconocido;
    } catch (_) {
      return EstadoPermisoCamara.desconocido;
    }
  }

  /// Solicita el permiso (el sistema decide si muestra el diálogo).
  Future<EstadoPermisoCamara> solicitar() async {
    try {
      final String? estado = await _channel.invokeMethod<String>(
        _metodoSolicitar,
      );
      return _mapear(estado);
    } on MissingPluginException {
      return EstadoPermisoCamara.desconocido;
    } on PlatformException {
      return EstadoPermisoCamara.desconocido;
    } catch (_) {
      return EstadoPermisoCamara.desconocido;
    }
  }

  /// Abre los Ajustes de la aplicación (caso "denegado permanentemente").
  ///
  /// Devuelve `true` si el sistema abrió la pantalla de Ajustes.
  Future<bool> abrirAjustes() async {
    try {
      final bool? abierto = await _channel.invokeMethod<bool>(_metodoAjustes);
      return abierto ?? false;
    } catch (_) {
      return false;
    }
  }

  /// `true` solo cuando el permiso está concedido.
  static bool estaConcedido(EstadoPermisoCamara estado) =>
      estado == EstadoPermisoCamara.concedido;

  EstadoPermisoCamara _mapear(String? estado) {
    switch (estado) {
      case _estadoConcedido:
        return EstadoPermisoCamara.concedido;
      case _estadoBloqueado:
        return EstadoPermisoCamara.denegadoPermanente;
      case _estadoDenegado:
        return EstadoPermisoCamara.denegado;
      default:
        return EstadoPermisoCamara.desconocido;
    }
  }
}
