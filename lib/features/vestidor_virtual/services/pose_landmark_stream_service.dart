import 'package:flutter/services.dart';

import '../models/pose_detection_result.dart';

/// Stream de resultados de MediaPipe (CU26 – Etapa 2C).
///
/// Canal `com.vantermen/pose_landmarks` (EventChannel). Solo viajan datos
/// numéricos: las imágenes del frame nunca salen del lado nativo.
class PoseLandmarkStreamService {
  PoseLandmarkStreamService({EventChannel? channel})
      : _channel = channel ?? const EventChannel(channelName);

  /// Nombre del canal; debe coincidir con
  /// `PoseLandmarkEventChannel.NOMBRE_CANAL` del lado Kotlin.
  static const String channelName = 'com.vantermen/pose_landmarks';

  final EventChannel _channel;

  /// Resultados de detección en tiempo real (~10 eventos por segundo).
  ///
  /// El stream es broadcast: se puede escuchar con `listen()` y liberar con
  /// `StreamSubscription.cancel()`. Los eventos inválidos se descartan, así que
  /// el consumidor siempre recibe un [PoseDetectionResult] bien formado.
  Stream<PoseDetectionResult> resultados() {
    return _channel
        .receiveBroadcastStream()
        .map(PoseDetectionResult.desdeMapa)
        .where((PoseDetectionResult? resultado) => resultado != null)
        .cast<PoseDetectionResult>();
  }
}
