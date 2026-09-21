import 'package:flutter/services.dart';

/// Error de inicialización de MediaPipe que conserva la causa nativa.
class PoseLandmarkerException implements Exception {
  const PoseLandmarkerException(this.message, {this.code, this.details});

  /// Mensaje legible para desarrollo.
  final String message;

  /// Código reportado por Kotlin (`PlatformException.code`).
  final String? code;

  /// Detalle técnico original (mensaje/traza de MediaPipe).
  final String? details;

  @override
  String toString() => 'PoseLandmarkerException($code): $message';
}

/// Puente Flutter -> Kotlin (`com.vantermen/pose_landmarker`) del CU26 (Etapa 2A).
///
/// Su única responsabilidad es comprobar que MediaPipe Tasks Vision inicializa
/// y carga `pose_landmarker_lite.task`. **Nunca** transporta imágenes, frames
/// ni landmarks: no hay `startImageStream()` ni envío de datos por el canal.
class PoseLandmarkerService {
  PoseLandmarkerService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// Nombre del canal (debe coincidir con `PoseLandmarkerChannel.CHANNEL_NAME`).
  static const String channelName = 'com.vantermen/pose_landmarker';

  static const String _methodInitialize = 'initializePoseLandmarker';
  static const String _methodClose = 'closePoseLandmarker';

  final MethodChannel _channel;

  /// Inicializa MediaPipe y carga el modelo de pose.
  ///
  /// Devuelve `true` cuando el PoseLandmarker quedó listo. Si falla, lanza
  /// [PoseLandmarkerException] con el mensaje real del lado nativo.
  Future<bool> initialize() async {
    try {
      final bool? listo = await _channel.invokeMethod<bool>(_methodInitialize);
      return listo ?? false;
    } on PlatformException catch (error) {
      throw PoseLandmarkerException(
        'No se pudo inicializar MediaPipe: ${error.message ?? error.code}',
        code: error.code,
        details: error.details?.toString(),
      );
    } on MissingPluginException {
      throw const PoseLandmarkerException(
        'MediaPipe no está disponible en esta plataforma.',
        code: 'MISSING_PLUGIN',
      );
    }
  }

  /// Libera el PoseLandmarker nativo. Cerrar es "best effort": un fallo aquí no
  /// debe interrumpir la navegación.
  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>(_methodClose);
    } on PlatformException {
      // Sin acción: la liberación es best effort.
    } on MissingPluginException {
      // Plataforma sin implementación nativa.
    }
  }
}
