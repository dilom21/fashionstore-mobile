import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../models/pose_detection_result.dart';
import '../models/pose_landmark.dart';
import '../models/torso_anchor.dart';
import '../models/vestidor_config_model.dart';
import '../services/camera_permission_service.dart';
import '../services/pose_landmark_stream_service.dart';
import '../services/pose_smoothing_service.dart';
import '../services/pose_validator.dart';
import '../services/torso_anchor_service.dart';
import '../widgets/pose_camera_view.dart';
import '../widgets/pose_overlay.dart';
import '../widgets/prenda_overlay.dart';
import '../widgets/torso_anchor_overlay.dart';

/// Índices mostrados en el diagnóstico temporal (11 y 12 = hombros).
const int _hombroIzquierdo = 11;
const int _hombroDerecho = 12;

/// Color usado para indicar detección correcta.
const Color _verdeOk = Color(0xFF32C48D);

/// CU26 – Vestidor Virtual (Etapas 4-6): cámara + pose + prenda 2D.
///
/// La cámara (CameraX) y la inferencia (MediaPipe LIVE_STREAM) viven en la vista
/// nativa. Aquí los landmarks crudos pasan por `PoseValidator` (¿sirve para
/// prendas?) y, solo si la pose es válida, por `PoseSmoothingService` (EMA); con
/// el resultado estabilizado se calcula el `TorsoAnchor` y, a partir de él y de
/// la `VestidorConfig`, la geometría de la prenda.
///
/// El motor NO hace requests de negocio: la configuración ya llega resuelta y la
/// única red es la descarga visual del PNG del asset.
class CamaraVestidorPage extends StatefulWidget {
  /// Crea la pantalla del vestidor con la configuración AR del producto.
  const CamaraVestidorPage({super.key, required this.configuracion});

  /// Configuración AR del producto (contrato CU26): `assetUrl`, factores,
  /// offsets, rotación y opacidad. Nunca se hardcodea aquí.
  final VestidorConfig configuracion;

  @override
  State<CamaraVestidorPage> createState() => _CamaraVestidorPageState();
}

class _CamaraVestidorPageState extends State<CamaraVestidorPage>
    with WidgetsBindingObserver {
  final PoseLandmarkStreamService _streamService = PoseLandmarkStreamService();
  final PoseValidator _validador = const PoseValidator();
  final PoseSmoothingService _suavizado = PoseSmoothingService();

  /// Etapa 5: geometría del torso. Se alimenta SIEMPRE con el resultado ya
  /// suavizado (nunca con los landmarks crudos).
  final TorsoAnchorService _torsoService = const TorsoAnchorService();

  /// Ancla del torso vigente; `null` cuando la pose no es utilizable.
  TorsoAnchor? _torso;

  StreamSubscription<PoseDetectionResult>? _suscripcion;

  /// Esqueleto de DIAGNÓSTICO: refleja lo que DETECTA MediaPipe (ya suavizado).
  /// No depende de que el vestidor lo considere utilizable.
  PoseDetectionResult? _resultado;

  /// Estado de la pose para el vestidor ("Pose lista" / "Ajusta tu posición").
  EstadoPose _estadoPose = EstadoPose.sinPose;

  /// Motivo técnico del último rechazo del validador (solo diagnóstico).
  String? _motivoPose;

  bool _streamConError = false;

  /// Histéresis de DETECCIÓN: frames consecutivos sin pose que se toleran antes
  /// de borrar el esqueleto (≈0,4 s a 12 fps). Evita el parpadeo por un frame
  /// perdido, pero NO conserva una pose vieja durante segundos.
  static const int _framesSinDeteccionParaLimpiar = 5;

  /// Histéresis de VALIDACIÓN: frames consecutivos no utilizables antes de
  /// degradar "Pose lista"; un único frame marginal no la quita.
  static const int _framesInvalidosParaDegradar = 3;

  /// Espaciado mínimo entre mensajes de diagnóstico por consola (throttle).
  static const Duration _intervaloMinimoEntreLogs = Duration(
    milliseconds: 1500,
  );

  int _framesSinDeteccion = 0;
  int _framesInvalidos = 0;
  DateTime _ultimoLog = DateTime.fromMillisecondsSinceEpoch(0);
  String? _ultimoLogTexto;

  /// Permiso de cámara en runtime (CU26): la vista nativa —y con ella
  /// CameraX— solo se construye cuando el permiso está CONCEDIDO.
  final CameraPermissionService _permisos = const CameraPermissionService();

  EstadoPermisoCamara _permiso = EstadoPermisoCamara.desconocido;
  bool _consultandoPermiso = true;
  bool _solicitandoPermiso = false;

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

    // El permiso se consulta ANTES de construir la vista de cámara.
    WidgetsBinding.instance.addObserver(this);
    _verificarPermiso();
  }

  /// Frame crudo → (A) DETECCIÓN estable + (B) VALIDACIÓN para el vestidor.
  ///
  /// Las dos cosas van SEPARADAS a propósito (corrección de la Etapa 4):
  /// - **(A) MediaPipe manda sobre la detección**: si hay pose, el resultado se
  ///   suaviza y el esqueleto de diagnóstico se dibuja, aunque el vestidor aún
  ///   no la considere utilizable.
  /// - **(B) `PoseValidator` solo calcula el estado del vestidor**: decide si la
  ///   pose sirve para colocar una prenda ("Pose lista"), con histéresis para
  ///   no parpadear por un único frame marginal.
  void _procesarResultado(PoseDetectionResult crudo) {
    if (!mounted) return;

    // (B) Validación en paralelo: nunca destruye el esqueleto.
    final PoseValidation validacion = _validador.validar(crudo);

    // (A) Detección: lo que MediaPipe dice en este frame.
    final bool detectada = crudo.poseDetected && crudo.landmarks.isNotEmpty;
    if (!detectada) {
      _framesSinDeteccion++;
      _framesInvalidos++;
      _suavizado.perderPose();

      // Gracia corta: se conserva el esqueleto unos frames antes de limpiarlo.
      if (_framesSinDeteccion < _framesSinDeteccionParaLimpiar) return;

      _registrarLog('MediaPipe sin pose ($_framesSinDeteccion frames)');
      setState(() {
        _resultado = null;
        // Sin pose utilizable la geometría se descarta: el rectángulo no queda
        // flotando sobre el video.
        _torso = null;
        _estadoPose = EstadoPose.sinPose;
        _motivoPose = validacion.motivo;
        _streamConError = false;
      });
      return;
    }

    _framesSinDeteccion = 0;
    final PoseDetectionResult estabilizado = _suavizado.filtrar(crudo);

    if (validacion.esValida) {
      _framesInvalidos = 0;
    } else {
      _framesInvalidos++;
      _registrarLog('Pose detectada, no lista: ${validacion.motivo}');
    }

    // Histéresis: "Pose lista" solo se pierde tras varios frames seguidos.
    final bool sigueLista =
        validacion.esValida || _framesInvalidos < _framesInvalidosParaDegradar;

    // Etapa 5: el ancla del torso se calcula SIEMPRE después del smoothing.
    final TorsoAnchor? ancla = _torsoService.calcular(estabilizado);

    setState(() {
      // El esqueleto SIEMPRE refleja lo detectado por MediaPipe.
      _resultado = estabilizado;
      _estadoPose = sigueLista ? EstadoPose.valida : EstadoPose.insuficiente;
      _motivoPose = validacion.esValida ? null : validacion.motivo;
      // La geometría sigue la misma histéresis que "Pose lista": durante la
      // gracia se conserva el último ancla válido y después desaparece.
      _torso = sigueLista ? (ancla ?? _torso) : null;
      _streamConError = false;
    });
  }

  /// Log de diagnóstico con throttle: ni una línea por frame ni repeticiones
  /// idénticas seguidas. El detalle real se ve en el panel de la pantalla.
  void _registrarLog(String mensaje) {
    final DateTime ahora = DateTime.now();
    final bool repetido = mensaje == _ultimoLogTexto;
    if (repetido && ahora.difference(_ultimoLog) < _intervaloMinimoEntreLogs) {
      return;
    }
    _ultimoLog = ahora;
    _ultimoLogTexto = mensaje;
    debugPrint('[CU26] $mensaje');
  }

  @override
  void dispose() {
    // Al salir se cancela la suscripción; la cámara y el analizador los libera
    // la PlatformView en su propio dispose (Navigator.pop).
    _suscripcion?.cancel();
    _suscripcion = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// `true` solo en Android, donde existe la PlatformView nativa de cámara.
  bool get _esAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// La cámara solo se construye en Android y con el permiso CONCEDIDO.
  bool get _mostrarCamara =>
      !_esAndroid || CameraPermissionService.estaConcedido(_permiso);

  /// `true` cuando la configuración permite renderizar la prenda.
  ///
  /// Se valida ANTES de renderizar: si no es utilizable se muestra un estado
  /// controlado y no se rompe la cámara.
  bool get _configuracionUsable {
    final VestidorConfig config = widget.configuracion;
    return config.tieneAsset && config.esPng2d && config.esTorso;
  }

  /// Motor operativo: configuración usable + cámara construida.
  bool get _operativo => _configuracionUsable && _mostrarCamara;

  /// Consulta el permiso sin abrir diálogos (initState y regreso de Ajustes).
  Future<void> _verificarPermiso() async {
    if (!_esAndroid) {
      // Otras plataformas no tienen vista nativa: la pantalla ya lo explica.
      if (mounted) setState(() => _consultandoPermiso = false);
      return;
    }

    final EstadoPermisoCamara estado = await _permisos.verificar();
    if (!mounted) return;
    setState(() {
      _permiso = estado;
      _consultandoPermiso = false;
    });
  }

  /// Solicita el permiso SOLO cuando el cliente lo pide explícitamente.
  Future<void> _solicitarPermiso() async {
    if (_solicitandoPermiso) return;
    setState(() => _solicitandoPermiso = true);

    final EstadoPermisoCamara estado = await _permisos.solicitar();
    if (!mounted) return;
    setState(() {
      _permiso = estado;
      _solicitandoPermiso = false;
      _consultandoPermiso = false;
    });
  }

  /// Abre los Ajustes del sistema (caso "denegado permanentemente").
  Future<void> _abrirAjustesPermiso() async {
    await _permisos.abrirAjustes();
  }

  /// Al volver a la app (por ejemplo desde Ajustes) se reconsulta el permiso:
  /// si allí se concedió, recién entonces se crea la cámara.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (CameraPermissionService.estaConcedido(_permiso)) return;
    _verificarPermiso();
  }

  void _volver() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final PoseDetectionResult? resultado = _resultado;
    // Con el permiso concedido (o en plataformas sin vista nativa) se muestra
    // el vestidor; si falta el permiso NO se construye ninguna vista de cámara.
    final bool mostrarCamara = _mostrarCamara;
    final bool operativo = _operativo;

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
            // La vista nativa (CameraX + MediaPipe) SOLO se construye cuando el
            // permiso de cámara está concedido: CameraX nunca intenta abrir la
            // cámara sin permiso.
            // Configuración no usable: estado controlado, jamás se construye la
            // cámara (no se rompe CameraX).
            if (!_configuracionUsable)
              Positioned.fill(child: _buildConfiguracionNoUsable())
            else if (mostrarCamara)
              const Positioned.fill(child: PoseCameraView())
            else
              Positioned.fill(child: _buildPermisoPendiente()),
            // ETAPA 6: PRENDA PNG sobre el torso. Se mantiene MONTADA aunque se
            // pierda la pose (con `anchor: null`) para conservar la imagen ya
            // descargada: al recuperar la pose se dibuja al instante y sin
            // volver a pedir el PNG.
            if (operativo)
              Positioned.fill(
                child: PrendaOverlay(
                  anchor: _torso,
                  configuracion: widget.configuracion,
                  imageWidth: resultado?.imageWidth ?? 0,
                  imageHeight: resultado?.imageHeight ?? 0,
                ),
              ),
            // ---- Overlays de DIAGNÓSTICO (se pueden desactivar sin tocar el
            // motor: basta con no montarlos; el motor no depende de ellos) ----
            // Esqueleto de DIAGNÓSTICO: se dibuja siempre que MediaPipe detecte
            // pose, aunque el vestidor todavía no la considere utilizable. Solo
            // desaparece tras varios frames seguidos sin detección (histéresis).
            if (operativo && resultado != null && resultado.poseDetected)
              Positioned.fill(child: PoseOverlay(resultado: resultado)),
            // Etapa 5: rectángulo de DIAGNÓSTICO del torso (ancla base con su
            // propio margen de 1.15, ajeno a los factores de la configuración).
            if (operativo &&
                resultado != null &&
                resultado.poseDetected &&
                _torso != null)
              Positioned.fill(
                child: TorsoAnchorOverlay(
                  anchor: _torso!,
                  imageWidth: resultado.imageWidth,
                  imageHeight: resultado.imageHeight,
                ),
              ),
            // Diagnóstico de pose y controles: solo con la cámara activa.
            if (operativo)
              Positioned(
                left: 20,
                right: 20,
                top: 16,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _DiagnosticoPose(
                    resultado: _resultado,
                    estado: _estadoPose,
                    configuracion: widget.configuracion,
                    motivo: _motivoPose,
                    anchor: _torso,
                    conError: _streamConError,
                  ),
                ),
              ),
            if (operativo)
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

  /// Estado controlado cuando la configuración AR no es utilizable.
  ///
  /// No se construye la cámara: CameraX/MediaPipe quedan intactos y el cliente
  /// ve un mensaje claro en lugar de una pantalla rota.
  Widget _buildConfiguracionNoUsable() {
    final VestidorConfig config = widget.configuracion;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.checkroom_rounded,
                color: AppColors.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'PRENDA NO DISPONIBLE',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Esta prenda todavía no tiene un recurso de vestidor virtual '
              'compatible (PNG 2D sobre el torso).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Producto ${config.productoId} · Configuración '
              '${config.configuracionId} · ${config.tipoAsset} · '
              '${config.zonaCuerpo}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                height: 1.45,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 24),
            BotonGradiente(
              label: 'VOLVER',
              icon: Icons.arrow_back_rounded,
              onPressed: _volver,
            ),
          ],
        ),
      ),
    );
  }

  /// Mensaje controlado cuando falta el permiso de cámara.
  ///
  /// No se construye ninguna vista nativa: CameraX no intenta abrir la cámara
  /// hasta que el permiso esté concedido.
  Widget _buildPermisoPendiente() {
    if (_consultandoPermiso) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Comprobando permiso de cámara...',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    final bool denegadoPermanente =
        _permiso == EstadoPermisoCamara.denegadoPermanente;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.no_photography_rounded,
                color: AppColors.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'PERMISO DE CÁMARA',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Se necesita permiso de cámara para utilizar el vestidor virtual.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.white70,
              ),
            ),
            if (denegadoPermanente) ...<Widget>[
              const SizedBox(height: 10),
              const Text(
                'El permiso está bloqueado. Actívalo desde los Ajustes de la '
                'aplicación.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: Colors.white60,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (denegadoPermanente)
              BotonGradiente(
                label: 'ABRIR AJUSTES',
                icon: Icons.settings_rounded,
                onPressed: _solicitandoPermiso ? null : _abrirAjustesPermiso,
              )
            else
              BotonGradiente(
                label: 'PERMITIR CÁMARA',
                icon: Icons.camera_alt_rounded,
                isLoading: _solicitandoPermiso,
                onPressed: _solicitandoPermiso ? null : _solicitarPermiso,
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _volver,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('VOLVER'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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
    required this.configuracion,
    this.motivo,
    this.anchor,
    this.conError = false,
  });

  final PoseDetectionResult? resultado;
  final EstadoPose estado;

  /// Configuración AR activa (DEBUG Etapa 7): permite comprobar en el teléfono
  /// que cada prenda usa su producto/configuración y sus factores del backend.
  final VestidorConfig configuracion;

  /// Motivo técnico del último rechazo del validador (solo diagnóstico).
  final String? motivo;

  /// Ancla vigente (DEBUG): permite comparar espalda vs frente en el teléfono.
  final TorsoAnchor? anchor;

  final bool conError;

  static const TextStyle _estiloDetalle = TextStyle(
    fontSize: 11,
    height: 1.35,
    color: Colors.white70,
  );

  /// Ámbar de "detectado pero todavía no utilizable".
  static const Color _ambarAlerta = Color(0xFFFBBF24);

  /// (A) MediaPipe: depende SOLO de la detección.
  bool get _detectadaPorMediaPipe => resultado?.poseDetected == true;

  /// (B) Vestidor: depende SOLO de la validación.
  bool get _listaParaVestidor => estado == EstadoPose.valida;

  /// Texto de MediaPipe (detección).
  String get _textoMediaPipe => _detectadaPorMediaPipe
      ? 'Pose detectada · ${resultado?.landmarkCount ?? 0} puntos'
      : 'Sin pose';

  /// Texto del vestidor (utilizable para una prenda).
  String get _textoVestidor =>
      _listaParaVestidor ? 'Pose lista' : 'Ajusta tu posición';

  @override
  Widget build(BuildContext context) {
    final PoseDetectionResult? datos = resultado;
    final bool detectada = _detectadaPorMediaPipe;
    final bool lista = _listaParaVestidor;
    final PoseLandmark? hombroIzq = datos?.porIndice(_hombroIzquierdo);
    final PoseLandmark? hombroDer = datos?.porIndice(_hombroDerecho);
    final String? tecnico = motivo?.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: lista
              ? _verdeOk.withValues(alpha: 0.55)
              : (detectada
                    ? _ambarAlerta.withValues(alpha: 0.55)
                    : AppColors.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // (A) DETECCIÓN de MediaPipe: no depende del vestidor.
          _filaEstado(
            etiqueta: 'MediaPipe',
            texto: _textoMediaPipe,
            color: detectada ? _verdeOk : Colors.white,
            icono: detectada
                ? Icons.check_circle_rounded
                : Icons.person_search_rounded,
            girando: !detectada,
          ),
          const SizedBox(height: 6),
          // (B) ESTADO del vestidor: solo validación.
          _filaEstado(
            etiqueta: 'Vestidor',
            texto: _textoVestidor,
            color: lista
                ? _verdeOk
                : (detectada ? _ambarAlerta : AppColors.textMuted),
            icono: lista ? Icons.check_circle_rounded : Icons.tune_rounded,
          ),
          if (detectada) ...[
            const SizedBox(height: 6),
            Text(_linea('H11', 'hombro izq', hombroIzq), style: _estiloDetalle),
            const SizedBox(height: 2),
            Text(_linea('H12', 'hombro der', hombroDer), style: _estiloDetalle),
          ],
          // DEBUG Etapa 6: geometría del ancla para comparar espalda vs frente.
          if (detectada && anchor != null) ...[
            const SizedBox(height: 4),
            Text(
              'Anchor: ancho ${anchor!.shoulderWidth.toStringAsFixed(3)} · '
              'alto ${anchor!.torsoHeight.toStringAsFixed(3)} · '
              'rot ${anchor!.rotationGrados.toStringAsFixed(1)}°',
              style: _estiloDetalle,
            ),
          ],
          // DEBUG Etapa 7: qué configuración del backend está renderizando la
          // prenda (producto, configuración y factores reales). El assetUrl no
          // se muestra para no ensuciar la UI.
          const SizedBox(height: 4),
          Text(
            'Prenda: prod ${configuracion.productoId} · '
            'config ${configuracion.configuracionId} · '
            'ancho ${configuracion.factorAncho.toStringAsFixed(2)} · '
            'alto ${configuracion.factorAlto.toStringAsFixed(2)}',
            style: _estiloDetalle,
          ),
          if (detectada && !lista && tecnico != null && tecnico.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _recortarMotivo(tecnico),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _estiloDetalle,
            ),
          ],
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

  /// Fila `etiqueta: estado` del diagnóstico.
  Widget _filaEstado({
    required String etiqueta,
    required String texto,
    required Color color,
    required IconData icono,
    bool girando = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (girando)
          const SizedBox(
            height: 12,
            width: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          )
        else
          Icon(icono, size: 14, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '$etiqueta: ',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                TextSpan(
                  text: texto,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Recorta el motivo técnico para que no ocupe toda la pantalla.
  static String _recortarMotivo(String valor) {
    if (valor.length <= 90) return valor;
    return '${valor.substring(0, 87)}...';
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
