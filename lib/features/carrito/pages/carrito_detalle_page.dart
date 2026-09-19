import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../../reservas/pages/crear_reserva_page.dart';
import '../models/carrito_model.dart';
import '../services/carrito_service.dart';
import '../widgets/aviso_vigencia.dart';
import '../widgets/carrito_item_card.dart';
import '../widgets/carrito_resumen_card.dart';

/// CU15 – Detalle del carrito: prendas reales, cantidades y resumen.
///
/// Consume `GET /carritos/{carrito_id}` como fuente de verdad: tras cada
/// operación (PATCH/DELETE) el estado se reemplaza con el detalle devuelto por
/// el backend, no con cálculos locales.
class CarritoDetallePage extends StatefulWidget {
  const CarritoDetallePage({
    super.key,
    required this.carritoId,
    this.onBuscarMas,
    this.service,
  });

  /// Identificador real del carrito.
  final int carritoId;

  /// Acción para "Buscar más productos" (cambiar a la pestaña Catálogo).
  final VoidCallback? onBuscarMas;

  /// Servicio inyectable (facilita pruebas).
  final CarritoService? service;

  @override
  State<CarritoDetallePage> createState() => _CarritoDetallePageState();
}

class _CarritoDetallePageState extends State<CarritoDetallePage> {
  late final CarritoService _service;

  CarritoDetalle? _carrito;
  bool _cargando = true;
  String? _error;

  /// Línea con una petición en curso (PATCH o DELETE).
  int? _lineaOcupadaId;

  /// Hay un DELETE del carrito completo en curso.
  bool _eliminandoCarrito = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CarritoService();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final CarritoDetalle carrito =
          await _service.obtenerCarrito(widget.carritoId);
      if (!mounted) return;
      setState(() {
        _carrito = carrito;
        _cargando = false;
      });
    } on CarritoException catch (error) {
      if (!mounted) return;
      if (error.unauthorized) {
        setState(() => _cargando = false);
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
        _error = 'No pudimos cargar el carrito. Inténtalo nuevamente.';
        _cargando = false;
      });
    }
  }

  /// Aplica el detalle devuelto por el backend (fuente de verdad).
  void _aplicar(CarritoDetalle carrito) {
    if (!mounted) return;
    setState(() {
      _carrito = carrito;
      _lineaOcupadaId = null;
    });

    // El backend puede cerrar el carrito cuando se queda sin líneas.
    if (!carrito.tieneItems || !carrito.estaActivo) {
      _volverAlListado('El carrito ya no tiene prendas disponibles.');
    }
  }

  Future<void> _cambiarCantidad(CarritoItem item, int nuevaCantidad) async {
    // Nunca se envía cantidad <= 0: para eso existe eliminate (DELETE).
    if (_lineaOcupadaId != null || nuevaCantidad < 1) return;

    setState(() => _lineaOcupadaId = item.detalleId);
    try {
      final CarritoDetalle carrito = await _service.actualizarCantidad(
        carritoId: widget.carritoId,
        detalleId: item.detalleId,
        cantidad: nuevaCantidad,
      );
      _aplicar(carrito);
    } on CarritoException catch (error) {
      _manejarErrorLinea(error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _lineaOcupadaId = null);
      _mostrarMensaje(
        'No pudimos actualizar la cantidad. Inténtalo nuevamente.',
      );
    }
  }

  /// Error común de las operaciones sobre una línea del carrito.
  Future<void> _manejarErrorLinea(CarritoException error) async {
    if (!mounted) return;
    setState(() => _lineaOcupadaId = null);

    if (error.unauthorized) {
      await SessionExpired.manejar(context, mensaje: error.message);
      return;
    }

    _mostrarMensaje(error.message);

    // Stock insuficiente, carrito no activo o línea inexistente: el backend
    // es la autoridad, así que se recarga el detalle.
    if (error.conflicto || error.statusCode == 404) await _cargar();
  }

  Future<void> _eliminarItem(CarritoItem item) async {
    if (_lineaOcupadaId != null) return;

    final bool confirmado = await _confirmar(
      titulo: 'Eliminar prenda',
      mensaje: '¿Eliminar ${item.productoNombre} del carrito?',
    );
    if (!confirmado || !mounted) return;

    setState(() => _lineaOcupadaId = item.detalleId);
    try {
      final CarritoDetalle carrito = await _service.eliminarItem(
        carritoId: widget.carritoId,
        detalleId: item.detalleId,
      );
      _aplicar(carrito);
    } on CarritoException catch (error) {
      await _manejarErrorLinea(error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _lineaOcupadaId = null);
      _mostrarMensaje('No pudimos quitar la prenda. Inténtalo nuevamente.');
    }
  }

  Future<void> _eliminarCarrito() async {
    final bool confirmado = await _confirmar(
      titulo: 'Eliminar carrito',
      mensaje: '¿Eliminar este carrito completo?',
    );
    if (!confirmado || !mounted) return;

    setState(() => _eliminandoCarrito = true);
    try {
      await _service.eliminarCarrito(widget.carritoId);
      if (!mounted) return;
      setState(() => _eliminandoCarrito = false);
      _volverAlListado('Carrito eliminado.');
    } on CarritoException catch (error) {
      if (!mounted) return;
      setState(() => _eliminandoCarrito = false);
      if (error.unauthorized) {
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      _mostrarMensaje(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _eliminandoCarrito = false);
      _mostrarMensaje('No pudimos eliminar el carrito. Inténtalo nuevamente.');
    }
  }

  Future<bool> _confirmar({
    required String titulo,
    required String mensaje,
  }) async {
    final bool? respuesta = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          titulo,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          mensaje,
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Eliminar',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return respuesta ?? false;
  }

  /// Cierra el detalle avisando al listado (que recargará `GET /carritos`).
  void _volverAlListado(String mensaje) {
    if (!mounted) return;
    _mostrarMensaje(mensaje);
    Navigator.of(context).pop();
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
      );
  }

  /// CU16: abre la creación de reserva sobre este carrito.
  ///
  /// Si la reserva se crea, el backend deja el carrito en CONVERTIDO, así que
  /// esta pantalla vuelve al listado (que se recarga con `GET /carritos`).
  Future<void> _reservar() async {
    final bool? reservada = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CrearReservaPage(carritoId: widget.carritoId),
      ),
    );
    if (!mounted) return;

    if (reservada == true) {
      _volverAlListado('Tu carrito pasó a reserva.');
      return;
    }

    // Se revalida el carrito por si cambió mientras el cliente reservaba.
    await _cargar();
  }

  void _buscarMas() {
    final VoidCallback? callback = widget.onBuscarMas;
    if (callback != null) callback();
    Navigator.of(context).maybePop();
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final CarritoDetalle? carrito = _carrito;
    final bool tieneItems = carrito?.tieneItems ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'TU CARRITO',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        actions: [
          if (tieneItems)
            if (_eliminandoCarrito)
              const Padding(
                padding: EdgeInsets.only(right: 20),
                child: Center(
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              )
            else
              IconButton(
                onPressed: _eliminarCarrito,
                tooltip: 'Eliminar carrito',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.textMuted,
                ),
              ),
        ],
      ),
      body: SafeArea(top: false, child: _buildContenido()),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Center(
        child: SizedBox(
          height: 28,
          width: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    if (_error != null) {
      return _EstadoError(mensaje: _error!, onReintentar: _cargar);
    }

    final CarritoDetalle? carrito = _carrito;
    if (carrito == null || !carrito.tieneItems) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Este carrito ya no tiene prendas.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ),
      );
    }

    // CU16: un carrito CONVERTIDO ya no es ACTIVO, así que no se reserva ni se
    // edita desde aquí: el contenido ya vive en una reserva.
    if (!carrito.estaActivo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.event_available_rounded,
                color: AppColors.primary,
                size: 34,
              ),
              const SizedBox(height: 14),
              const Text(
                'Este carrito ya no está activo: sus prendas pasaron a una '
                'reserva.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => _volverAlListado('Volviendo a tus carritos.'),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('VOLVER A MIS CARRITOS'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
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
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
          children: [
            _EncabezadoDetalle(carrito: carrito),
            const SizedBox(height: 16),
            const AvisoVigencia(),
            const SizedBox(height: 18),
            ...carrito.items.map(
              (CarritoItem item) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: CarritoItemCard(
                  item: item,
                  // Una sola operación por línea: el mismo indicador cubre el
                  // PATCH de cantidad y el DELETE de la prenda.
                  actualizando: _lineaOcupadaId == item.detalleId,
                  onIncrementar: () =>
                      _cambiarCantidad(item, item.cantidad + 1),
                  onDecrementar: () =>
                      _cambiarCantidad(item, item.cantidad - 1),
                  onEliminar: () => _eliminarItem(item),
                ),
              ),
            ),
            const SizedBox(height: 6),
            CarritoResumenCard(
              carrito: carrito,
              // CU16: reservar solo con carrito ACTIVO y con unidades.
              onReservar:
                  carrito.estaActivo && carrito.cantidadTotalUnidades > 0
                      ? _reservar
                      : null,
              onIrAPagar: () =>
                  _mostrarMensaje('Proceso de pago disponible próximamente.'),
              onBuscarMas: _buscarMas,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sucursal del carrito y su subtítulo ("Comprando en ...").
class _EncabezadoDetalle extends StatelessWidget {
  const _EncabezadoDetalle({required this.carrito});

  final CarritoDetalle carrito;

  @override
  Widget build(BuildContext context) {
    final int lineas = carrito.cantidadLineas;
    final int unidades = carrito.cantidadTotalUnidades;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.32),
            ),
          ),
          child: const Icon(
            Icons.storefront_rounded,
            size: 19,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Comprando en ${carrito.sucursalEtiqueta}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$lineas ${lineas == 1 ? 'prenda' : 'prendas'} · '
                '$unidades ${unidades == 1 ? 'unidad' : 'unidades'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Estado de error del detalle, con opción de reintentar.
class _EstadoError extends StatelessWidget {
  const _EstadoError({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 34,
            ),
            const SizedBox(height: 14),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
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
    );
  }
}



