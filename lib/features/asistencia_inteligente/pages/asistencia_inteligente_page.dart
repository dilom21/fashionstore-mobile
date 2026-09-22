import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../../carrito/services/carrito_service.dart';
import '../../catalogo/pages/producto_detalle_page.dart';
import '../../vestidor_virtual/services/vestidor_flow_service.dart';
import '../models/asistencia_models.dart';
import '../services/asistencia_service.dart';
import '../widgets/recomendacion_card.dart';

/// Pantalla de Asistencia Inteligente (recomendaciones con IA).
///
/// El cliente describe estilo, ocasión, talla y presupuesto; el backend obtiene
/// el catálogo e inventario REALES, la IA solo selecciona/rankea candidatos y
/// el backend revalida y reconstruye la respuesta desde PostgreSQL.
///
/// Acciones por tarjeta:
/// - Agregar: usa CU15 (`CarritoService.agregarItem`) solo si hay inventario y
///   sucursal resueltos; si no, abre el detalle para elegir talla.
/// - Ver detalle: reutiliza `ProductoDetallePage`.
/// - Probar en vestidor: usa el flujo real del CU26 (`VestidorFlowService`).
class AsistenciaInteligentePage extends StatefulWidget {
  const AsistenciaInteligentePage({
    super.key,
    this.service,
    this.carritoService,
    this.vestidorFlow,
  });

  /// Servicio inyectable (facilita pruebas).
  final AsistenciaService? service;

  /// Servicio de carrito inyectable (facilita pruebas).
  final CarritoService? carritoService;

  /// Servicio inyectable del flujo del vestidor virtual (facilita pruebas).
  final VestidorFlowService? vestidorFlow;

  @override
  State<AsistenciaInteligentePage> createState() =>
      _AsistenciaInteligentePageState();
}

class _AsistenciaInteligentePageState extends State<AsistenciaInteligentePage> {
  static const List<String> _sugerencias = <String>[
    'Oficina',
    'Casual',
    'Evento',
    'Polo negro',
    'Talla M',
  ];

  late final AsistenciaService _service;
  late final CarritoService _carritoService;
  late final VestidorFlowService _vestidorFlow;
  final TextEditingController _consultaController = TextEditingController();

  String? _talla;
  bool _cargando = false;
  String? _error;
  RecomendacionesResponse? _respuesta;
  int? _agregandoProductoId;

  /// Producto cuyo vestidor se está abriendo (evita dobles aperturas).
  int? _abriendoVestidorProductoId;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AsistenciaService();
    _carritoService = widget.carritoService ?? CarritoService();
    _vestidorFlow = widget.vestidorFlow ?? VestidorFlowService();
  }

  @override
  void dispose() {
    _consultaController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Acciones
  // -------------------------------------------------------------------------

  void _aplicarSugerencia(String sugerencia) {
    if (sugerencia == 'Talla M') {
      setState(() => _talla = 'M');
    }
    final String actual = _consultaController.text.trim();
    if (actual.toLowerCase().contains(sugerencia.toLowerCase())) return;
    final String nuevo = actual.isEmpty ? sugerencia : '$actual $sugerencia';
    _consultaController.text = nuevo;
    _consultaController.selection = TextSelection.fromPosition(
      TextPosition(offset: nuevo.length),
    );
  }

  Future<void> _buscar() async {
    final String consulta = _consultaController.text.trim();
    if (consulta.isEmpty) {
      _mostrarMensaje('Cuéntanos qué estilo buscas.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final RecomendacionesResponse respuesta = await _service.recomendar(
        consulta: consulta,
        talla: _talla,
        limite: 4,
      );
      if (!mounted) return;
      setState(() {
        _respuesta = respuesta;
        _cargando = false;
      });
    } on AsistenciaException catch (error) {
      if (!mounted) return;
      if (error.unauthorized) {
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      setState(() {
        _error = error.message;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos generar recomendaciones. Inténtalo nuevamente.';
        _cargando = false;
      });
    }
  }

  void _abrirDetalle(int productoId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductoDetallePage(productoId: productoId),
      ),
    );
  }

  Future<void> _agregar(RecomendacionProducto recomendacion) async {
    // Sin inventario/sucursal resueltos no se elige talla: se abre el detalle.
    if (!recomendacion.puedeAgregarDirecto) {
      _abrirDetalle(recomendacion.productoId);
      return;
    }

    setState(() => _agregandoProductoId = recomendacion.productoId);
    try {
      await _carritoService.agregarItem(
        sucursalId: recomendacion.sucursalId!,
        inventarioId: recomendacion.inventarioId!,
        cantidad: 1,
      );
      if (!mounted) return;
      setState(() => _agregandoProductoId = null);
      _mostrarMensaje('Prenda agregada al carrito.');
    } on CarritoException catch (error) {
      if (!mounted) return;
      setState(() => _agregandoProductoId = null);
      if (error.unauthorized) {
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      _mostrarMensaje(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _agregandoProductoId = null);
      _mostrarMensaje('No pudimos agregar la prenda. Inténtalo nuevamente.');
    }
  }

  /// Abre el flujo real del vestidor virtual (CU26) para la recomendación.
  ///
  /// Reenvía `varianteId` cuando la recomendación lo trae resuelto; si no, el
  /// flujo decide (y pide elegir color si hay varias configuraciones).
  Future<void> _probarVestidor(RecomendacionProducto recomendacion) async {
    if (_abriendoVestidorProductoId != null) return;
    setState(() => _abriendoVestidorProductoId = recomendacion.productoId);
    try {
      await _vestidorFlow.abrirVestidor(
        context,
        productoId: recomendacion.productoId,
        varianteId: recomendacion.varianteId,
      );
    } finally {
      if (mounted) setState(() => _abriendoVestidorProductoId = null);
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
      );
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

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
          'ASISTENCIA INTELIGENTE',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const _Encabezado(),
            const SizedBox(height: 20),
            _Buscador(controller: _consultaController, onEnviar: _buscar),
            const SizedBox(height: 14),
            _Sugerencias(
              sugerencias: _sugerencias,
              onSeleccion: _aplicarSugerencia,
            ),
            const SizedBox(height: 22),
            ..._seccionEstado(),
          ],
        ),
      ),
    );
  }

  List<Widget> _seccionEstado() {
    if (_cargando) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(
            child: SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
        ),
      ];
    }

    if (_error != null) {
      return <Widget>[_BloqueError(mensaje: _error!, onReintentar: _buscar)];
    }

    final RecomendacionesResponse? respuesta = _respuesta;
    if (respuesta == null) {
      return const <Widget>[_BloqueInicial()];
    }

    if (respuesta.estaVacio) {
      return <Widget>[_BloqueVacio(mensaje: respuesta.descripcion)];
    }

    return <Widget>[
      _BloqueRecomendacion(
        titulo: respuesta.titulo,
        descripcion: respuesta.descripcion,
      ),
      const SizedBox(height: 18),
      for (final RecomendacionProducto recomendacion
          in respuesta.recomendaciones)
        RecomendacionCard(
          recomendacion: recomendacion,
          agregando: _agregandoProductoId == recomendacion.productoId,
          onAgregar: () => _agregar(recomendacion),
          onVerDetalle: () => _abrirDetalle(recomendacion.productoId),
          onProbarVestidor: () => _probarVestidor(recomendacion),
        ),
    ];
  }
}

// -----------------------------------------------------------------------------
// Widgets de la página
// -----------------------------------------------------------------------------

class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'VANTER MEN',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Encuentra tu look ideal',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.15,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Cuéntanos la ocasión, el estilo o el color que buscas y te '
          'recomendamos prendas reales de nuestro catálogo.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _Buscador extends StatelessWidget {
  const _Buscador({required this.controller, required this.onEnviar});

  final TextEditingController controller;
  final Future<void> Function() onEnviar;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onEnviar(),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Ej. algo casual premium para oficina, negro, talla M',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        suffixIcon: IconButton(
          tooltip: 'Enviar',
          onPressed: onEnviar,
          icon: const Icon(Icons.send_rounded, color: AppColors.primary),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}

class _Sugerencias extends StatelessWidget {
  const _Sugerencias({required this.sugerencias, required this.onSeleccion});

  final List<String> sugerencias;
  final ValueChanged<String> onSeleccion;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sugerencias
          .map(
            (String sugerencia) => Material(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onSeleccion(sugerencia),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    sugerencia,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _BloqueRecomendacion extends StatelessWidget {
  const _BloqueRecomendacion({required this.titulo, required this.descripcion});

  final String titulo;
  final String descripcion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titulo.trim().isEmpty ? 'Tu selección' : titulo.trim(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (descripcion.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              descripcion.trim(),
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BloqueInicial extends StatelessWidget {
  const _BloqueInicial();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 28),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            color: AppColors.inactive,
            size: 34,
          ),
          SizedBox(height: 12),
          Text(
            'Describe tu look y toca enviar para ver recomendaciones.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _BloqueVacio extends StatelessWidget {
  const _BloqueVacio({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            color: AppColors.textMuted,
            size: 30,
          ),
          const SizedBox(height: 12),
          Text(
            mensaje.trim().isEmpty
                ? 'No encontramos recomendaciones para tu búsqueda.'
                : mensaje.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _BloqueError extends StatelessWidget {
  const _BloqueError({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final Future<void> Function() onReintentar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 30,
          ),
          const SizedBox(height: 12),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onReintentar,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
