import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../models/prenda_tecnica_e2e.dart';
import '../models/vestidor_config_model.dart';
import '../services/camera_permission_service.dart';
import '../services/pose_landmarker_service.dart';
import '../services/vestidor_api_service.dart';
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

  /// Permiso de cámara en runtime (CU26): la cámara no se abre sin él.
  final CameraPermissionService _permisos = const CameraPermissionService();

  bool _solicitandoPermiso = false;
  String? _mensajePermiso;
  bool _permisoBloqueado = false;

  // ---------------------------------------------------------------------------
  // SELECTOR TÉCNICO E2E CU26 (Etapas 6 y 7) - TEMPORAL
  //
  // Mientras no exista la integración con ProductoDetalle/Asistencia, esta
  // pantalla permite elegir a mano QUÉ prenda probar y consigue su configuración
  // real del backend. NO es el comportamiento definitivo del negocio.
  //
  // Solo se fijan aquí `productoId` y `configuracionId` (validación física):
  // assetUrl, factores, offsets, rotación y opacidad SIEMPRE vienen del backend.
  // ---------------------------------------------------------------------------

  /// Servicio HTTP del contrato de Josías. SOLO se usa FUERA del motor AR.
  final VestidorApiService _vestidorApi = VestidorApiService();

  /// Prenda elegida en el selector técnico (índice del catálogo E2E).
  int _indicePrendaE2E = 0;

  /// Prenda vigente del selector técnico.
  PrendaTecnicaE2E get _prendaE2E =>
      PrendaTecnicaE2E.catalogoTecnico[_indicePrendaE2E];

  bool _cargandoConfig = false;
  String? _resumenConfig;

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

  /// `true` solo en Android, donde existe la vista nativa de cámara (CameraX).
  bool get _esAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Abre el vestidor SOLO cuando el permiso de cámara está concedido.
  ///
  /// Si no lo está, se solicita en este punto; si el cliente rechaza, la cámara
  /// NO se abre y se muestra un mensaje controlado (con acceso a los Ajustes
  /// cuando el rechazo es permanente).
  Future<void> _abrirCamara() async {
    if (_solicitandoPermiso) return;

    // Sin vista nativa (iOS/escritorio/web) no hace falta permiso: la propia
    // pantalla de cámara explica que solo está disponible en Android.
    if (!_esAndroid) {
      await _cargarConfiguracionE2E();
      return;
    }

    setState(() {
      _solicitandoPermiso = true;
      _mensajePermiso = null;
      _permisoBloqueado = false;
    });

    EstadoPermisoCamara estado = await _permisos.verificar();
    if (!CameraPermissionService.estaConcedido(estado)) {
      estado = await _permisos.solicitar();
    }
    if (!mounted) return;
    setState(() => _solicitandoPermiso = false);

    if (CameraPermissionService.estaConcedido(estado)) {
      await _cargarConfiguracionE2E();
      return;
    }

    setState(() {
      _mensajePermiso =
          'Se necesita permiso de cámara para utilizar el vestidor virtual.';
      _permisoBloqueado = estado == EstadoPermisoCamara.denegadoPermanente;
    });
  }

  /// LAUNCHER TEMPORAL E2E (Etapa 7): pide al backend la configuración EXACTA
  /// elegida en el selector técnico y abre el motor AR con ella.
  ///
  /// El motor (`CamaraVestidorPage`) NO hace requests: recibe el DTO ya resuelto.
  /// Esta llamada puede hacer HTTP porque está FUERA del motor.
  Future<void> _cargarConfiguracionE2E() async {
    if (_cargandoConfig) return;
    final PrendaTecnicaE2E prenda = _prendaE2E;
    setState(() {
      _cargandoConfig = true;
      _resumenConfig = null;
    });

    try {
      final VestidorConfiguracionesResponse respuesta = await _vestidorApi
          .obtenerConfiguraciones(productoId: prenda.productoId);

      // Selección ESTRICTA: si la configuración pedida no existe o no es
      // compatible se muestra el error y NUNCA se prueba otra prenda.
      final SeleccionConfigE2E seleccion = seleccionarConfiguracionE2E(
        configuraciones: respuesta.configuraciones,
        configuracionId: prenda.configuracionId,
        productoId: prenda.productoId,
      );
      if (!mounted) return;

      if (!seleccion.esExito) {
        setState(() => _cargandoConfig = false);
        _mostrarAviso(seleccion.error ?? 'Prenda de prueba no disponible.');
        return;
      }

      final VestidorConfig config = seleccion.configuracion!;
      setState(() {
        _cargandoConfig = false;
        _resumenConfig =
            'E2E: ${prenda.etiqueta} · ${config.colorEtiqueta} · '
            'producto ${config.productoId} · config '
            '${config.configuracionId}';
      });
      _irACamara(config);
    } on VestidorApiException catch (error) {
      if (!mounted) return;
      setState(() => _cargandoConfig = false);
      _mostrarAviso(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoConfig = false);
      _mostrarAviso('No pudimos preparar la prenda de prueba.');
    }
  }

  /// Aviso discreto (SnackBar) para los errores del launcher de prueba.
  void _mostrarAviso(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 4)),
      );
  }

  void _irACamara(VestidorConfig configuracion) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CamaraVestidorPage(configuracion: configuracion),
      ),
    );
  }

  /// Abre los Ajustes del sistema para desbloquear el permiso.
  Future<void> _abrirAjustesPermiso() async {
    await _permisos.abrirAjustes();
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
                _DiagnosticoMediaPipe(estado: _estado, detalle: _detalleError),
                const SizedBox(height: 24),
                // SELECTOR TÉCNICO E2E CU26 (TEMPORAL): permite validar en el
                // teléfono varias prendas con el MISMO motor 2D. No es diseño
                // definitivo ni navegación real de catálogo.
                _SelectorTecnicoE2E(
                  indice: _indicePrendaE2E,
                  habilitado: !_cargandoConfig,
                  onCambiar: (int indice) {
                    setState(() {
                      _indicePrendaE2E = indice;
                      _resumenConfig = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                BotonGradiente(
                  label: 'INICIAR VESTIDOR',
                  icon: Icons.camera_alt_rounded,
                  isLoading: _solicitandoPermiso || _cargandoConfig,
                  onPressed: (_solicitandoPermiso || _cargandoConfig)
                      ? null
                      : _abrirCamara,
                ),
                if (_resumenConfig != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _resumenConfig!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                if (_mensajePermiso != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _MensajePermiso(
                    mensaje: _mensajePermiso!,
                    mostrarAjustes: _permisoBloqueado,
                    onAbrirAjustes: _abrirAjustesPermiso,
                  ),
                ],
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

/// Selector técnico TEMPORAL de prendas (CU26 – Etapa 7).
///
/// Solo elige QUÉ producto/configuración se pide al backend; no conoce assets ni
/// factores. Se elimina cuando exista la navegación real desde el detalle del
/// producto.
class _SelectorTecnicoE2E extends StatelessWidget {
  const _SelectorTecnicoE2E({
    required this.indice,
    required this.habilitado,
    required this.onCambiar,
  });

  /// Índice vigente dentro de [PrendaTecnicaE2E.catalogoTecnico].
  final int indice;

  /// `false` mientras hay una carga en curso (evita cambios a medio camino).
  final bool habilitado;

  final ValueChanged<int> onCambiar;

  @override
  Widget build(BuildContext context) {
    final List<PrendaTecnicaE2E> catalogo = PrendaTecnicaE2E.catalogoTecnico;
    final PrendaTecnicaE2E prenda = catalogo[indice];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'SELECTOR TÉCNICO E2E CU26',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButton<int>(
            value: indice,
            isExpanded: true,
            dropdownColor: AppColors.surface,
            underline: const SizedBox.shrink(),
            iconEnabledColor: AppColors.textMuted,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            items: <DropdownMenuItem<int>>[
              for (int i = 0; i < catalogo.length; i++)
                DropdownMenuItem<int>(
                  value: i,
                  child: Text(catalogo[i].etiqueta),
                ),
            ],
            onChanged: habilitado
                ? (int? valor) {
                    if (valor != null) onCambiar(valor);
                  }
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            '${prenda.resumen} · la configuración, los factores y el asset '
            'vienen del backend (solo validación).',
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mensaje controlado cuando el permiso de cámara fue rechazado.
///
/// No abre la cámara: solo explica la situación y, si el permiso quedó
/// bloqueado, ofrece ir a los Ajustes de la aplicación.
class _MensajePermiso extends StatelessWidget {
  const _MensajePermiso({
    required this.mensaje,
    required this.mostrarAjustes,
    required this.onAbrirAjustes,
  });

  final String mensaje;

  /// `true` cuando el permiso quedó bloqueado (solo se corrige en Ajustes).
  final bool mostrarAjustes;

  final VoidCallback onAbrirAjustes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.no_photography_rounded,
                color: AppColors.error,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mensaje,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (mostrarAjustes) ...<Widget>[
            const SizedBox(height: 10),
            const Text(
              'El permiso está bloqueado: actívalo desde los Ajustes de la '
              'aplicación.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAbrirAjustes,
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('ABRIR AJUSTES'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
