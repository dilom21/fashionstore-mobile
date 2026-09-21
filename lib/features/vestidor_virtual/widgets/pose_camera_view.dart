import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// CU26 – Vestidor Virtual (Etapa 2B): vista de cámara nativa (CameraX).
///
/// En Android embebe la PlatformView `com.vantermen/pose_camera_view`, que
/// muestra la cámara frontal con CameraX + `PreviewView` (o la trasera como
/// respaldo). No analiza frames, no captura imágenes y no usa MediaPipe.
class PoseCameraView extends StatelessWidget {
  const PoseCameraView({super.key, this.onPlatformViewCreated});

  /// Identificador de la vista nativa; debe coincidir con
  /// `PoseCameraPlatformViewFactory.VIEW_TYPE` del lado Kotlin.
  static const String viewType = 'com.vantermen/pose_camera_view';

  /// Notificación opcional cuando la vista nativa terminó de crearse.
  final void Function(int id)? onPlatformViewCreated;

  @override
  Widget build(BuildContext context) {
    final bool esAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (!esAndroid) {
      return const _PoseCameraViewNoDisponible();
    }

    return AndroidView(
      viewType: viewType,
      layoutDirection: TextDirection.ltr,
      onPlatformViewCreated: onPlatformViewCreated,
    );
  }
}

/// Mensaje controlado en plataformas sin PlatformView nativa.
class _PoseCameraViewNoDisponible extends StatelessWidget {
  const _PoseCameraViewNoDisponible();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          'La vista de cámara del Vestidor Virtual solo está disponible '
          'en Android.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
