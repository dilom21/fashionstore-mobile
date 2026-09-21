import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../services/pose_landmarker_service.dart';
import 'camara_vestidor_page.dart';

/// CU26 – Vestidor Virtual (Etapa 2A): entrada a la prueba de prendas.
///
/// No abre la cámara automáticamente: `MainNavigationPage` usa `IndexedStack`
/// y las pestañas permanecen vivas, por lo que pedir la cámara al entrar
/// dejaría el dispositivo ocupado sin que el cliente lo haya solicitado.
///
/// Tampoco procesa frames: esta etapa solo comprueba que MediaPipe Tasks Vision
/// inicializa y carga el modelo de pose desde los assets.
class VestidorVirtualPage extends StatefulWidget {
  const VestidorVirtualPage({super.key});

  @override
  State<VestidorVirtualPage> createState() => _VestidorVirtualPageState();
}

/// Estado del diagnóstico temporal de MediaPipe (solo desarrollo).
enum _EstadoMediaPipe { inicializando, listo, error }

class _VestidorVirtualPageState extends State<VestidorVirtualPage> {
  final PoseLandmarkerService _poseService = PoseLandmarkerService();

  _EstadoMediaPipe _estado = _EstadoMediaPipe.inicializando;
  String? _detalleError;

  @override
  void initState() {
    super.initState();
    // Se ejecuta una sola vez por pantalla: el `IndexedStack` mantiene la
    // página viva entre cambios de pestaña, así que no se reinicializa en
    // rebuilds ni se cierra/abre MediaPipe continuamente.
    _inicializarMediaPipe();
  }

  @override
  void dispose() {
    // Salida definitiva de la pantalla (logout/cierre de la app): se libera el
    // PoseLandmarker nativo. No se ejecuta al cambiar de pestaña.
    _poseService.close();
    super.dispose();
  }

  Future<void> _inicializarMediaPipe() async {
    try {
      await _poseService.initialize();
      if (!mounted) return;
      setState(() => _estado = _EstadoMediaPipe.listo);
    } on PoseLandmarkerException catch (error) {
      if (!mounted) return;
      setState(() {
        _estado = _EstadoMediaPipe.error;
        _detalleError = error.details ?? error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estado = _EstadoMediaPipe.error;
        _detalleError = 'Error desconocido al inicializar MediaPipe.';
      });
    }
  }

  void _abrirCamara() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CamaraVestidorPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
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
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              children: [
                Center(
                  child: Container(
                    height: 96,
                    width: 96,
                    decoration: BoxDecoration(
                      gradient: AppColors.accentGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.32),
                          blurRadius: 30,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.checkroom_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Prueba tus prendas',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Usaremos la cámara de tu dispositivo para visualizar las '
                  'prendas en tiempo real.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 20),
                // Diagnóstico temporal (desarrollo): se eliminará cuando la
                // Etapa 2 complete la detección de pose.
                _DiagnosticoMediaPipe(
                  estado: _estado,
                  detalle: _detalleError,
                ),
                const SizedBox(height: 24),
                BotonGradiente(
                  label: 'INICIAR VESTIDOR',
                  icon: Icons.camera_alt_rounded,
                  onPressed: _abrirCamara,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Diagnóstico temporal (desarrollo) del estado de MediaPipe.
///
/// Muestra si el PoseLandmarker se inicializó y, si falló, el detalle técnico
/// para poder depurar. No interviene en el flujo de la cámara.
class _DiagnosticoMediaPipe extends StatelessWidget {
  const _DiagnosticoMediaPipe({required this.estado, this.detalle});

  final _EstadoMediaPipe estado;
  final String? detalle;

  static const Color _verdeOk = Color(0xFF32C48D);

  @override
  Widget build(BuildContext context) {
    final bool cargando = estado == _EstadoMediaPipe.inicializando;
    final bool listo = estado == _EstadoMediaPipe.listo;
    final Color color = cargando
        ? AppColors.textMuted
        : (listo ? _verdeOk : AppColors.error);
    final String texto = cargando
        ? 'Inicializando MediaPipe...'
        : (listo ? 'MediaPipe listo' : 'Error al inicializar MediaPipe');
    final String? tecnico = detalle?.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (cargando)
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                )
              else
                Icon(
                  listo
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 16,
                  color: color,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (!cargando && tecnico != null && tecnico.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _recortar(tecnico),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Recorta el detalle técnico para que sea legible durante el desarrollo.
  static String _recortar(String valor) {
    if (valor.length <= 240) return valor;
    return '${valor.substring(0, 237)}...';
  }
}
