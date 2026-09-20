import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../models/carrito_model.dart';
import '../services/carrito_service.dart';
import '../widgets/aviso_vigencia.dart';
import '../widgets/carrito_card.dart';
import '../widgets/carrito_empty_state.dart';
import 'carrito_detalle_page.dart';

/// CU15 – "Tus carritos": lista los carritos ACTIVOS reales del cliente.
///
/// Consume `GET /carritos`. Un cliente puede tener varios carritos activos:
/// uno por sucursal, por eso el listado no asume un carrito único.
class CarritosPage extends StatefulWidget {
  const CarritosPage({super.key, this.onExplorarCatalogo, this.service});

  /// Lleva al cliente a la pestaña Catálogo (estado vacío y "Buscar más").
  final VoidCallback? onExplorarCatalogo;

  /// Servicio inyectable (facilita pruebas).
  final CarritoService? service;

  @override
  State<CarritosPage> createState() => CarritosPageState();
}

/// Estado público para que [MainNavigationPage] pueda refrescar la pestaña.
///
/// El `IndexedStack` mantiene viva esta página entre cambios de pestaña, por lo
/// que no basta con `initState`: al volver a Carrito se llama a [recargar].
class CarritosPageState extends State<CarritosPage> {
  late final CarritoService _service;

  List<CarritoResumen> _carritos = <CarritoResumen>[];
  bool _cargando = true;
  String? _error;
  int? _eliminandoId;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CarritoService();
    _cargar();
  }

  /// Recarga el listado sin mostrar el loader de pantalla completa.
  Future<void> recargar() => _cargar(mostrarLoader: false);

  Future<void> _cargar({bool mostrarLoader = true}) async {
    setState(() {
      if (mostrarLoader) _cargando = true;
      _error = null;
    });

    try {
      final CarritoListaResponse respuesta = await _service.listarCarritos();
      if (!mounted) return;
      setState(() {
        _carritos = respuesta.items;
        _cargando = false;
      });
    } on CarritoException catch (error) {
      if (!mounted) return;
      if (error.unauthorized) {
        setState(() => _cargando = false);
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      _aplicarError(error.message, mostrarLoader: mostrarLoader);
    } catch (_) {
      if (!mounted) return;
      _aplicarError(
        'No pudimos cargar tus carritos. Inténtalo nuevamente.',
        mostrarLoader: mostrarLoader,
      );
    }
  }

  /// Muestra el error como pantalla completa solo si no hay datos en pantalla.
  void _aplicarError(String mensaje, {required bool mostrarLoader}) {
    if (mostrarLoader || _carritos.isEmpty) {
      setState(() {
        _error = mensaje;
        _cargando = false;
      });
      return;
    }
    setState(() => _cargando = false);
    _mostrarMensaje(mensaje);
  }

  // -------------------------------------------------------------------------
  // Acciones
  // -------------------------------------------------------------------------

  Future<void> _verCarrito(CarritoResumen carrito) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CarritoDetallePage(
          carritoId: carrito.carritoId,
          onBuscarMas: widget.onExplorarCatalogo,
        ),
      ),
    );
    // El detalle pudo modificar o eliminar el carrito: el backend es la verdad.
    if (mounted) await _cargar(mostrarLoader: false);
  }

  Future<void> _eliminarCarrito(CarritoResumen carrito) async {
    final bool confirmado = await _confirmarEliminacion(carrito);
    if (!confirmado || !mounted) return;

    setState(() => _eliminandoId = carrito.carritoId);
    try {
      await _service.eliminarCarrito(carrito.carritoId);
      if (!mounted) return;
      setState(() => _eliminandoId = null);
      _mostrarMensaje('Carrito eliminado.');
      await _cargar(mostrarLoader: false);
    } on CarritoException catch (error) {
      if (!mounted) return;
      setState(() => _eliminandoId = null);
      if (error.unauthorized) {
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      _mostrarMensaje(error.message);
      // Si el carrito ya no existía, el listado debe refrescarse.
      if (error.statusCode == 404 || error.conflicto) {
        await _cargar(mostrarLoader: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _eliminandoId = null);
      _mostrarMensaje('No pudimos eliminar el carrito. Inténtalo nuevamente.');
    }
  }

  Future<bool> _confirmarEliminacion(CarritoResumen carrito) async {
    final bool? respuesta = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Eliminar carrito',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '¿Eliminar el carrito de ${carrito.sucursalEtiqueta}?',
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
          'CARRITO',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
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

    if (_carritos.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.62,
              child: CarritoEmptyState(
                onExplorarCatalogo: widget.onExplorarCatalogo,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _cargar,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            itemCount: _carritos.length + 1,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 16),
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _EncabezadoCarritos(cantidad: _carritos.length),
                );
              }
              final CarritoResumen carrito = _carritos[index - 1];
              return CarritoCard(
                carrito: carrito,
                eliminando: _eliminandoId == carrito.carritoId,
                onVerCarrito: () => _verCarrito(carrito),
                onEliminar: () => _eliminarCarrito(carrito),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Encabezado del listado: título, subtítulo, contador y aviso de vigencia.
class _EncabezadoCarritos extends StatelessWidget {
  const _EncabezadoCarritos({required this.cantidad});

  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Tus carritos',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            _ContadorCarritos(cantidad: cantidad),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Revisa tus carritos activos por sucursal y continúa tu compra.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 18),
        const AvisoVigencia(),
      ],
    );
  }
}

/// Indicador visual de la cantidad de carritos activos.
class _ContadorCarritos extends StatelessWidget {
  const _ContadorCarritos({required this.cantidad});

  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        cantidad == 1 ? '1 activo' : '$cantidad activos',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Estado de error del listado, con opción de reintentar.
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
