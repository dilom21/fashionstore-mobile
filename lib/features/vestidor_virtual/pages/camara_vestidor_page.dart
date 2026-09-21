import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/pose_detection_result.dart';
import '../models/pose_landmark.dart';
import '../services/pose_landmark_stream_service.dart';
import '../services/pose_smoothing_service.dart';
import '../services/pose_validator.dart';
import '../widgets/pose_camera_view.dart';
import '../widgets/pose_overlay.dart';

/// Índices mostrados en el diagnóstico temporal (11 y 12 = hombros).
const int _hombroIzquierdo = 11;
const int _hombroDerecho = 12;

/// Color usado para indicar detección correcta.
const Color _verdeOk = Color(0xFF32C48D);

/// CU26 – Vestidor Virtual (Etapa 4): pose validada y estabilizada.
///
/// La cámara (CameraX) y la inferencia (MediaPipe LIVE_STREAM) viven en la vista
/// nativa. Aquí los landmarks crudos pasan por `PoseValidator` (¿sirve para
/// prendas?) y, solo si la pose es válida, por `PoseSmoothingService` (EMA); el
/// resultado estabilizado es lo que dibuja `PoseOverlay`. Todavía NO hay prendas.
class CamaraVestidorPage extends StatefulWidget {
  const CamaraVestidorPage({super.key});

  @override
  State<CamaraVestidorPage> createState() => _CamaraVestidorPageState();
}

class _CamaraVestidorPageState extends State<CamaraVestidorPage> {
  final PoseLandmarkStreamService _streamService = PoseLandmarkStreamService();
  final PoseValidator _validador = const PoseValidator();
  final PoseSmoothingService _suavizado = PoseSmoothingService();

  StreamSubscription<PoseDetectionResult>? _suscripcion;

  /// Resultado ya VALIDADO y ESTABILIZADO: es lo único que dibuja el overlay.
  PoseDetectionResult? _resultado;

  /// Estado de la pose para el vestidor.
  EstadoPose _estadoPose = EstadoPose.sinPose;

  bool _streamConError = false;

  @override
  void initState() {
    super.initState();
    _suscripcion = _streamService.resultados().listen(
      _procesarResultado,
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _streamConError = true);
        debugPrint('Stream de landmarks con error: $error');
      },
    );
  }

  /// Frame crudo → validación → suavizado → overlay.
  ///
  /// Si la pose no es válida para el vestidor NO se suaviza ni se dibuja: el
  /// esqueleto desaparece para representar exactamente lo que el vestidor
  /// considerará utilizable cuando lleguen las prendas.
  void _procesarResultado(PoseDetectionResult crudo) {
    final PoseValidation validacion = _validador.validar(crudo);
    if (!mounted) return;

    if (!validacion.esValida) {
      // Un frame no utilizable también cuenta como "pose perdida" para el
      // reset del filtro de suavizado.
      _suavizado.perderPose();
      if (validacion.motivo != null) {
        debugPrint('Pose no válida: ${validacion.motivo}');
      }
      setState(() {
        _resultado = null;
        _estadoPose = validacion.estado;
        _streamConError = false;
      });
      return;
    }

    final PoseDetectionResult estabilizado = _suavizado.filtrar(crudo);
    setState(() {
      _resultado = estabilizado;
      _estadoPose = EstadoPose.valida;
      _streamConError = false;
    });
  }

  @override
  void dispose() {
    // Al salir se cancela la suscripción; la cámara y el analizador los libera
    // la PlatformView en su propio dispose (Navigator.pop).
    _suscripcion?.cancel();
    _suscripcion = null;
    super.dispose();
  }

  void _volver() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final PoseDetectionResult? resultado = _resultado;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'VESTIDOR VIRTUAL',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: PoseCameraView()),
            // Esqueleto encima del preview y por debajo de los controles.
            // Cuando no hay pose desaparece (no se conserva el último).
            if (resultado != null && resultado.poseDetected)
              Positioned.fill(child: PoseOverlay(resultado: resultado)),
            Positioned(
              left: 20,
              right: 20,
              top: 16,
              child: Align(
                alignment: Alignment.topLeft,
                child: _DiagnosticoPose(
                  resultado: _resultado,
                  estado: _estadoPose,
                  conError: _streamConError,
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Row(
                children: [
                  const _EtiquetaCamara(),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _volver,
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('VOLVER'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black.withValues(alpha: 0.45),
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta discreta de la vista de cámara en uso.
///
/// La lente real la elige CameraX en la vista nativa (frontal y, si el
/// dispositivo no tiene, trasera). El canal de retorno actual solo transporta
/// landmarks, así que la etiqueta muestra la lente prevista por defecto.
class _EtiquetaCamara extends StatelessWidget {
  const _EtiquetaCamara();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Cámara frontal',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Diagnóstico temporal (desarrollo) del estado de la detección de pose.
///
/// Muestra si MediaPipe encontró una persona y las coordenadas de dos puntos
/// importantes, que deben cambiar en tiempo real al moverse. NO dibuja nada
/// sobre el vídeo.
class _DiagnosticoPose extends StatelessWidget {
  const _DiagnosticoPose({
    required this.resultado,
    required this.estado,
    this.conError = false,
  });

  final PoseDetectionResult? resultado;
  final EstadoPose estado;
  final bool conError;

  static const TextStyle _estiloDetalle = TextStyle(
    fontSize: 11,
    height: 1.35,
    color: Colors.white70,
  );

  /// Mensaje simple según el estado que ve el vestidor.
  String get _titulo {
    switch (estado) {
      case EstadoPose.valida:
        return 'Pose lista · ${resultado?.landmarkCount ?? 0} puntos';
      case EstadoPose.insuficiente:
        return 'Colócate frente a la cámara';
      case EstadoPose.sinPose:
        return 'Buscando persona...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final PoseDetectionResult? datos = resultado;
    final bool detectada = estado == EstadoPose.valida;
    final PoseLandmark? hombroIzq = datos?.porIndice(_hombroIzquierdo);
    final PoseLandmark? hombroDer = datos?.porIndice(_hombroDerecho);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: detectada ? _verdeOk.withValues(alpha: 0.55) : AppColors.border,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (detectada)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: _verdeOk,
                )
              else
                const SizedBox(
                  height: 12,
                  width: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                _titulo,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: detectada ? _verdeOk : Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_linea('H11', 'hombro izq', hombroIzq), style: _estiloDetalle),
          const SizedBox(height: 2),
          Text(_linea('H12', 'hombro der', hombroDer), style: _estiloDetalle),
          if (conError) ...[
            const SizedBox(height: 6),
            const Text(
              'Sin datos de MediaPipe todavía.',
              style: TextStyle(fontSize: 10.5, color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  /// Formato: `H11 (hombro izq)  x 0.31 | y 0.28 | z -0.14`.
  static String _linea(String etiqueta, String nombre, PoseLandmark? punto) {
    final String prefijo = '$etiqueta ($nombre)';
    if (punto == null) return '$prefijo  sin datos';
    return '$prefijo  x ${punto.x.toStringAsFixed(2)} | '
        'y ${punto.y.toStringAsFixed(2)} | '
        'z ${punto.z.toStringAsFixed(2)}';
  }
}
