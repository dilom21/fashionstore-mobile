import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../../catalogo/models/producto_model.dart';
import '../models/carrito_model.dart';
import '../pages/carrito_detalle_page.dart';
import '../services/carrito_service.dart';
import 'boton_gradiente.dart';
import 'cantidad_stepper.dart';

/// Sección "Agregar al carrito" dentro del detalle de producto (CU15).
///
/// La combinación seleccionable (sucursal, talla, color y temporada) se deriva
/// de los INVENTARIOS REALES que el backend entrega en `GET /productos/{id}`
/// (`variantes[].inventarios`). Nunca se inventan ids: el `inventario_id` que
/// consume `POST /carritos/items` sale de la combinación elegida.
class AgregarAlCarritoSection extends StatefulWidget {
  const AgregarAlCarritoSection({
    super.key,
    required this.producto,
    this.onRecargar,
    this.service,
  });

  /// Producto con sus variantes e inventarios reales.
  final ProductoDetalle producto;

  /// Recarga el producto (por ejemplo, tras un 409 por stock insuficiente).
  final VoidCallback? onRecargar;

  /// Servicio inyectable (facilita pruebas).
  final CarritoService? service;

  @override
  State<AgregarAlCarritoSection> createState() =>
      _AgregarAlCarritoSectionState();
}

class _AgregarAlCarritoSectionState extends State<AgregarAlCarritoSection> {
  late final CarritoService _service;
  late List<_Combinacion> _combinaciones;

  int? _sucursalId;
  String? _talla;
  String? _color;
  String? _temporada;
  int _cantidad = 1;

  bool _agregando = false;
  CarritoDetalle? _agregado;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CarritoService();
    _combinaciones = _construirCombinaciones(widget.producto);
    _seleccionarOpcionesUnicas();
  }

  @override
  void didUpdateWidget(AgregarAlCarritoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si el producto se recarga (por ejemplo tras un conflicto de stock) se
    // reconstruyen las combinaciones reales y se limpia lo inválido.
    if (!identical(oldWidget.producto, widget.producto)) {
      _combinaciones = _construirCombinaciones(widget.producto);
      _limpiarSeleccionInvalida();
      _seleccionarOpcionesUnicas();
    }
  }

  /// Construye las combinaciones reales (variante × inventario).
  static List<_Combinacion> _construirCombinaciones(ProductoDetalle producto) {
    final List<_Combinacion> resultado = <_Combinacion>[];
    for (final VarianteProducto variante in producto.variantes) {
      for (final InventarioProducto inventario in variante.inventarios) {
        final int? sucursalId = inventario.sucursalId;
        if (sucursalId == null || sucursalId <= 0 || inventario.id <= 0) {
          continue;
        }
        resultado.add(
          _Combinacion(
            sucursalId: sucursalId,
            sucursalNombre: inventario.sucursalEtiqueta,
            talla: variante.tallaNombre.trim(),
            color: variante.colorNombre.trim(),
            temporada: inventario.temporadaNombre.trim(),
            inventarioId: inventario.id,
            stockDisponible: inventario.stockDisponible,
          ),
        );
      }
    }
    return resultado;
  }

  // -------------------------------------------------------------------------
  // Opciones disponibles (filtradas por la selección previa)
  // -------------------------------------------------------------------------

  /// Combinaciones de la sucursal elegida (o todas si aún no hay selección).
  List<_Combinacion> get _deSucursal => _sucursalId == null
      ? _combinaciones
      : _combinaciones
            .where((_Combinacion c) => c.sucursalId == _sucursalId)
            .toList();

  List<_Combinacion> get _deSucursalTalla {
    if (_talla == null) return _deSucursal;
    return _deSucursal.where((_Combinacion c) => c.talla == _talla).toList();
  }

  List<_Combinacion> get _deSucursalTallaColor {
    if (_color == null) return _deSucursalTalla;
    return _deSucursalTalla
        .where((_Combinacion c) => c.color == _color)
        .toList();
  }

  List<_Opcion<int>> get _opcionesSucursal => _opcionesDe<int>(
    _combinaciones,
    (_Combinacion c) => c.sucursalId,
    (_Combinacion c) => c.sucursalNombre,
  );

  List<_Opcion<String>> get _opcionesTalla => _opcionesDe<String>(
    _deSucursal,
    (_Combinacion c) => c.talla,
    (_Combinacion c) => c.talla,
  );

  List<_Opcion<String>> get _opcionesColor => _opcionesDe<String>(
    _deSucursalTalla,
    (_Combinacion c) => c.color,
    (_Combinacion c) => c.color,
  );

  List<_Opcion<String>> get _opcionesTemporada => _opcionesDe<String>(
    _deSucursalTallaColor,
    (_Combinacion c) => c.temporada,
    (_Combinacion c) => c.temporada,
  );

  /// Opciones únicas (valor → etiqueta), ignorando etiquetas vacías.
  static List<_Opcion<T>> _opcionesDe<T>(
    List<_Combinacion> combinaciones,
    T Function(_Combinacion) valorDe,
    String Function(_Combinacion) etiquetaDe,
  ) {
    final Map<T, String> mapa = <T, String>{};
    for (final _Combinacion c in combinaciones) {
      final String etiqueta = etiquetaDe(c).trim();
      if (etiqueta.isEmpty) continue;
      mapa.putIfAbsent(valorDe(c), () => etiqueta);
    }
    return mapa.entries
        .map(
          (MapEntry<T, String> e) =>
              _Opcion<T>(valor: e.key, etiqueta: e.value),
        )
        .toList();
  }

  /// Combinación real seleccionada: de aquí sale el `inventario_id`.
  _Combinacion? get _seleccion {
    final int? sucursalId = _sucursalId;
    if (sucursalId == null) return null;
    if (_opcionesTalla.isNotEmpty && _talla == null) return null;
    if (_opcionesColor.isNotEmpty && _color == null) return null;
    if (_opcionesTemporada.isNotEmpty && _temporada == null) return null;

    for (final _Combinacion c in _combinaciones) {
      if (c.sucursalId != sucursalId) continue;
      if (_opcionesTalla.isNotEmpty && c.talla != _talla) continue;
      if (_opcionesColor.isNotEmpty && c.color != _color) continue;
      if (_opcionesTemporada.isNotEmpty && c.temporada != _temporada) continue;
      return c;
    }
    return null;
  }

  int get _stockDisponible => _seleccion?.stockDisponible ?? 0;

  bool get _puedeAgregar =>
      !_agregando &&
      _seleccion != null &&
      _stockDisponible > 0 &&
      _cantidad >= 1;

  // -------------------------------------------------------------------------
  // Selección
  // -------------------------------------------------------------------------

  /// Preselecciona las opciones que son únicas (mejora la experiencia).
  void _seleccionarOpcionesUnicas() {
    if (_sucursalId == null && _opcionesSucursal.length == 1) {
      _sucursalId = _opcionesSucursal.first.valor;
    }
    if (_talla == null && _opcionesTalla.length == 1) {
      _talla = _opcionesTalla.first.valor;
    }
    if (_color == null && _opcionesColor.length == 1) {
      _color = _opcionesColor.first.valor;
    }
    if (_temporada == null && _opcionesTemporada.length == 1) {
      _temporada = _opcionesTemporada.first.valor;
    }
    _cantidad = 1;
  }

  /// Evita combinaciones imposibles: si un cambio deja inválida una selección
  /// posterior, esa selección se limpia.
  void _limpiarSeleccionInvalida() {
    final Set<String> tallas = _deSucursal
        .map((_Combinacion c) => c.talla)
        .where((String valor) => valor.isNotEmpty)
        .toSet();
    if (_talla != null && !tallas.contains(_talla)) _talla = null;

    final Set<String> colores = _deSucursalTalla
        .map((_Combinacion c) => c.color)
        .where((String valor) => valor.isNotEmpty)
        .toSet();
    if (_color != null && !colores.contains(_color)) _color = null;

    final Set<String> temporadas = _deSucursalTallaColor
        .map((_Combinacion c) => c.temporada)
        .where((String valor) => valor.isNotEmpty)
        .toSet();
    if (_temporada != null && !temporadas.contains(_temporada)) {
      _temporada = null;
    }
  }

  void _onSucursal(int valor) {
    setState(() {
      _sucursalId = valor;
      _limpiarSeleccionInvalida();
      _seleccionarOpcionesUnicas();
    });
  }

  void _onTalla(String valor) {
    setState(() {
      _talla = valor;
      _limpiarSeleccionInvalida();
      _seleccionarOpcionesUnicas();
    });
  }

  void _onColor(String valor) {
    setState(() {
      _color = valor;
      _limpiarSeleccionInvalida();
      _seleccionarOpcionesUnicas();
    });
  }

  void _onTemporada(String valor) {
    setState(() {
      _temporada = valor;
      _limpiarSeleccionInvalida();
    });
  }

  void _cambiarCantidad(int delta) {
    setState(() {
      final int siguiente = _cantidad + delta;
      if (siguiente < 1) return;
      // El backend sigue siendo la autoridad final del stock.
      if (_stockDisponible > 0 && siguiente > _stockDisponible) return;
      _cantidad = siguiente;
    });
  }

  // -------------------------------------------------------------------------
  // Agregar al carrito
  // -------------------------------------------------------------------------

  Future<void> _agregar() async {
    final _Combinacion? seleccion = _seleccion;
    if (seleccion == null || !_puedeAgregar) return;

    setState(() {
      _agregando = true;
      _agregado = null;
    });

    try {
      final CarritoDetalle carrito = await _service.agregarItem(
        sucursalId: seleccion.sucursalId,
        inventarioId: seleccion.inventarioId,
        cantidad: _cantidad,
      );
      if (!mounted) return;
      setState(() {
        _agregando = false;
        _agregado = carrito;
        _cantidad = 1;
      });
    } on CarritoException catch (error) {
      if (!mounted) return;
      setState(() => _agregando = false);
      if (error.unauthorized) {
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      _mostrarMensaje(error.message);
      // El stock pudo cambiar: se recarga el producto con inventarios reales.
      if (error.conflicto) widget.onRecargar?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _agregando = false);
      _mostrarMensaje('No pudimos agregar la prenda. Inténtalo nuevamente.');
    }
  }

  void _verCarrito() {
    final CarritoDetalle? carrito = _agregado;
    if (carrito == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CarritoDetallePage(carritoId: carrito.carritoId),
      ),
    );
  }

  void _seguirComprando() {
    setState(() => _agregado = null);
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
    if (_combinaciones.isEmpty) {
      return const _SinInventario();
    }

    final _Combinacion? seleccion = _seleccion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Subtitulo('AGREGAR AL CARRITO'),
        const SizedBox(height: 6),
        const Text(
          'Elige sucursal, talla, color y temporada para agregar la prenda.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: AppColors.textMuted,
          ),
        ),
        _Grupo<int>(
          titulo: 'Sucursal',
          opciones: _opcionesSucursal,
          seleccionado: _sucursalId,
          onSeleccion: _onSucursal,
        ),
        _Grupo<String>(
          titulo: 'Talla',
          opciones: _opcionesTalla,
          seleccionado: _talla,
          onSeleccion: _onTalla,
        ),
        _Grupo<String>(
          titulo: 'Color',
          opciones: _opcionesColor,
          seleccionado: _color,
          onSeleccion: _onColor,
        ),
        _Grupo<String>(
          titulo: 'Temporada',
          opciones: _opcionesTemporada,
          seleccionado: _temporada,
          onSeleccion: _onTemporada,
        ),
        const SizedBox(height: 16),
        _StockYCantidad(
          seleccion: seleccion,
          cantidad: _cantidad,
          onCambiarCantidad: _cambiarCantidad,
        ),
        const SizedBox(height: 18),
        BotonGradiente(
          label: 'AGREGAR AL CARRITO',
          icon: Icons.shopping_bag_outlined,
          isLoading: _agregando,
          onPressed: _puedeAgregar ? _agregar : null,
        ),
        if (_agregado != null) ...[
          const SizedBox(height: 14),
          _ConfirmacionAgregado(
            onVerCarrito: _verCarrito,
            onSeguirComprando: _seguirComprando,
          ),
        ],
      ],
    );
  }
}

/// Mensaje cuando el producto no expone inventarios reales.
class _SinInventario extends StatelessWidget {
  const _SinInventario();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: AppColors.textMuted,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'No hay inventario disponible para agregar este producto al '
              'carrito.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Título de sección dentro del detalle de producto.
class _Subtitulo extends StatelessWidget {
  const _Subtitulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

/// Cantidad a agregar y stock real de la combinación seleccionada.
class _StockYCantidad extends StatelessWidget {
  const _StockYCantidad({
    required this.seleccion,
    required this.cantidad,
    required this.onCambiarCantidad,
  });

  final _Combinacion? seleccion;
  final int cantidad;
  final ValueChanged<int> onCambiarCantidad;

  @override
  Widget build(BuildContext context) {
    final _Combinacion? actual = seleccion;
    final bool hayStock = (actual?.stockDisponible ?? 0) > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CANTIDAD',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            CantidadStepper(
              cantidad: cantidad,
              habilitado: hayStock,
              maximo: hayStock ? actual!.stockDisponible : null,
              onIncrementar: () => onCambiarCantidad(1),
              onDecrementar: () => onCambiarCantidad(-1),
            ),
            const SizedBox(width: 12),
            Expanded(child: _TextoStock(seleccion: actual)),
          ],
        ),
      ],
    );
  }
}

/// Stock disponible de la combinación elegida (dato del backend).
class _TextoStock extends StatelessWidget {
  const _TextoStock({required this.seleccion});

  final _Combinacion? seleccion;

  @override
  Widget build(BuildContext context) {
    final _Combinacion? actual = seleccion;
    if (actual == null) {
      return const Text(
        'Elige una combinación',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      );
    }

    final int stock = actual.stockDisponible;
    final Color color = stock > 0 ? AppColors.primary : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        stock > 0
            ? 'Stock disponible: $stock'
            : 'Sin stock en esta combinación',
        maxLines: 2,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Confirmación tras agregar, con las dos acciones solicitadas.
class _ConfirmacionAgregado extends StatelessWidget {
  const _ConfirmacionAgregado({
    required this.onVerCarrito,
    required this.onSeguirComprando,
  });

  final VoidCallback onVerCarrito;
  final VoidCallback onSeguirComprando;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Prenda agregada al carrito',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onVerCarrito,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Ver carrito',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onSeguirComprando,
            child: const Text(
              'Seguir comprando',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grupo de opciones seleccionables (chips) con el estilo VANTER MEN.
class _Grupo<T> extends StatelessWidget {
  const _Grupo({
    required this.titulo,
    required this.opciones,
    required this.seleccionado,
    required this.onSeleccion,
  });

  final String titulo;
  final List<_Opcion<T>> opciones;
  final T? seleccionado;
  final ValueChanged<T> onSeleccion;

  @override
  Widget build(BuildContext context) {
    if (opciones.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          child: Text(
            titulo.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opciones.map((_Opcion<T> opcion) {
            final bool activo = seleccionado == opcion.valor;
            return Material(
              color: activo
                  ? AppColors.primary.withValues(alpha: 0.22)
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onSeleccion(opcion.valor),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: activo ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Text(
                    opcion.etiqueta,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                      color: activo
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Opción seleccionable de un grupo (valor real + etiqueta visible).
class _Opcion<T> {
  const _Opcion({required this.valor, required this.etiqueta});

  final T valor;
  final String etiqueta;
}

/// Combinación real (variante + inventario) lista para el backend.
class _Combinacion {
  const _Combinacion({
    required this.sucursalId,
    required this.sucursalNombre,
    required this.talla,
    required this.color,
    required this.temporada,
    required this.inventarioId,
    required this.stockDisponible,
  });

  final int sucursalId;
  final String sucursalNombre;
  final String talla;
  final String color;
  final String temporada;

  /// `inventario_id` real que consume `POST /carritos/items`.
  final int inventarioId;

  final int stockDisponible;
}
