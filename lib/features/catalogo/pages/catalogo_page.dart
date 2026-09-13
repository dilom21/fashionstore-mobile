import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/catalogo_filtros_model.dart';
import '../models/producto_model.dart';
import '../services/catalogo_service.dart';
import '../widgets/catalogo_filtros_sheet.dart';
import '../widgets/producto_card.dart';
import 'producto_detalle_page.dart';

/// Pantalla de catálogo del cliente (CU09).
///
/// Lista productos activos con búsqueda, filtros en bottom sheet y navegación
/// al detalle. Consume el catálogo público (sin autenticación).
class CatalogoPage extends StatefulWidget {
  const CatalogoPage({super.key, this.service});

  /// Servicio inyectable (facilita pruebas).
  final CatalogoService? service;

  @override
  State<CatalogoPage> createState() => _CatalogoPageState();
}

class _CatalogoPageState extends State<CatalogoPage> {
  static const Duration _debounce = Duration(milliseconds: 350);

  late final CatalogoService _service;
  final TextEditingController _busquedaController = TextEditingController();

  Timer? _debounceTimer;
  CatalogoFiltros? _filtros;
  CatalogoFiltrosSeleccion _seleccion = const CatalogoFiltrosSeleccion();

  List<Producto> _productos = <Producto>[];
  bool _cargando = true;
  bool _cargandoFiltros = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CatalogoService();
    _cargarFiltros();
    _cargarProductos();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _cargarFiltros() async {
    setState(() => _cargandoFiltros = true);
    try {
      final CatalogoFiltros filtros = await _service.obtenerFiltros();
      if (!mounted) return;
      setState(() => _filtros = filtros);
    } catch (_) {
      // Los filtros son opcionales: el listado sigue siendo usable sin ellos.
    } finally {
      if (mounted) setState(() => _cargandoFiltros = false);
    }
  }

  Future<void> _cargarProductos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final List<Producto> productos = await _service.listarProductos(
        buscar: _busquedaController.text,
        categoriaId: _seleccion.categoriaId,
        tallaId: _seleccion.tallaId,
        colorId: _seleccion.colorId,
        temporadaId: _seleccion.temporadaId,
        coleccionId: _seleccion.coleccionId,
        sucursalId: _seleccion.sucursalId,
        conStock: _seleccion.soloConStock ? true : null,
      );
      if (!mounted) return;
      setState(() {
        _productos = productos;
        _cargando = false;
      });
    } on CatalogException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar el catálogo. Inténtalo nuevamente.';
        _cargando = false;
      });
    }
  }

  void _onBuscarCambio(String _) {
    setState(() {});
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _cargarProductos);
  }

  Future<void> _abrirFiltros() async {
    final CatalogoFiltros? filtros = _filtros;
    if (filtros == null) return;

    final CatalogoFiltrosSeleccion? resultado =
        await CatalogoFiltrosSheet.mostrar(
      context,
      filtros: filtros,
      seleccion: _seleccion,
    );

    if (resultado == null) return;
    setState(() => _seleccion = resultado);
    await _cargarProductos();
  }

  Future<void> _limpiarFiltros() async {
    if (_seleccion.estaVacio) return;
    setState(() => _seleccion = const CatalogoFiltrosSeleccion());
    await _cargarProductos();
  }

  Future<void> _abrirDetalle(Producto producto) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductoDetallePage(
          productoId: producto.id,
          filtros: _filtros,
          service: _service,
        ),
      ),
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
          'CATÁLOGO',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        actions: [
          _BotonFiltros(
            cantidad: _seleccion.activos,
            cargando: _cargandoFiltros,
            onTap: _cargandoFiltros ? null : _abrirFiltros,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildBuscador(),
            if (!_seleccion.estaVacio) _buildBarraFiltrosActivos(),
            Expanded(child: _buildContenido()),
          ],
        ),
      ),
    );
  }

  Widget _buildBuscador() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      child: TextField(
        controller: _busquedaController,
        onChanged: _onBuscarCambio,
        onSubmitted: (_) {
          _debounceTimer?.cancel();
          _cargarProductos();
        },
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          hintText: 'Buscar productos...',
          hintStyle: const TextStyle(color: AppColors.inactive, fontSize: 14),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textMuted,
            size: 20,
          ),
          suffixIcon: _busquedaController.text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: () {
                    _busquedaController.clear();
                    _debounceTimer?.cancel();
                    setState(() {});
                    _cargarProductos();
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                ),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: _borde(AppColors.border),
          enabledBorder: _borde(AppColors.border),
          focusedBorder: _borde(AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildBarraFiltrosActivos() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
            child: Text(
              '${_seleccion.activos} filtro(s) activo(s)',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _limpiarFiltros,
            icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
            label: const Text('Limpiar'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
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
      return _EstadoCentrado(
        icon: Icons.wifi_off_rounded,
        titulo: 'No pudimos cargar el catálogo',
        mensaje: _error!,
        accionLabel: 'Reintentar',
        onAccion: _cargarProductos,
      );
    }

    if (_productos.isEmpty) {
      return _EstadoCentrado(
        icon: Icons.checkroom_rounded,
        titulo: 'Sin resultados',
        mensaje: _seleccion.estaVacio &&
                _busquedaController.text.trim().isEmpty
            ? 'Todavía no hay productos disponibles en el catálogo.'
            : 'Prueba con otra búsqueda o ajusta los filtros.',
        accionLabel: _seleccion.estaVacio ? null : 'Limpiar filtros',
        onAccion: _seleccion.estaVacio ? null : _limpiarFiltros,
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _cargarProductos,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.48,
        ),
        itemCount: _productos.length,
        itemBuilder: (BuildContext context, int index) {
          final Producto producto = _productos[index];
          return ProductoCard(
            producto: producto,
            onTap: () => _abrirDetalle(producto),
          );
        },
      ),
    );
  }

  OutlineInputBorder _borde(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color),
      );
}

/// Botón de filtros con contador de filtros activos.
class _BotonFiltros extends StatelessWidget {
  const _BotonFiltros({
    required this.cantidad,
    required this.cargando,
    required this.onTap,
  });

  final int cantidad;
  final bool cargando;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Filtros',
      onPressed: onTap,
      icon: cargando
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.textMuted),
              ),
            )
          : Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.tune_rounded),
                if (cantidad > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        gradient: AppColors.accentGradient,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 17,
                        minHeight: 17,
                      ),
                      child: Text(
                        '$cantidad',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Estado centrado reutilizable (error o vacío).
class _EstadoCentrado extends StatelessWidget {
  const _EstadoCentrado({
    required this.icon,
    required this.titulo,
    required this.mensaje,
    this.accionLabel,
    this.onAccion,
  });

  final IconData icon;
  final String titulo;
  final String mensaje;
  final String? accionLabel;
  final VoidCallback? onAccion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
            if (accionLabel != null && onAccion != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onAccion,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(accionLabel!),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
