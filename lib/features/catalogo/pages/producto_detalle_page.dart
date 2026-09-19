import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../carrito/widgets/agregar_al_carrito_section.dart';
import '../models/catalogo_filtros_model.dart';
import '../models/producto_model.dart';
import '../services/catalogo_service.dart';
import '../widgets/disponibilidad_section.dart';
import '../widgets/producto_media.dart';

/// Detalle de producto (CU09).
///
/// Consume `GET /productos/{id}` para recursos y variantes, y delega la
/// disponibilidad por sucursal a [DisponibilidadSection].
class ProductoDetallePage extends StatefulWidget {
  const ProductoDetallePage({
    super.key,
    required this.productoId,
    this.filtros,
    this.service,
  });

  final int productoId;

  /// Filtros del catálogo ya cargados (opcional, evita una petición extra).
  final CatalogoFiltros? filtros;

  /// Servicio inyectable (facilita pruebas).
  final CatalogoService? service;

  @override
  State<ProductoDetallePage> createState() => _ProductoDetallePageState();
}

class _ProductoDetallePageState extends State<ProductoDetallePage> {
  late final CatalogoService _service;
  bool _cargando = true;
  String? _error;
  ProductoDetalle? _producto;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CatalogoService();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final ProductoDetalle producto =
          await _service.obtenerProducto(widget.productoId);
      if (!mounted) return;
      setState(() {
        _producto = producto;
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
        _error = 'No pudimos cargar el producto. Inténtalo nuevamente.';
        _cargando = false;
      });
    }
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
          'DETALLE',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
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
      return Center(
        child: Padding(
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
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _cargar,
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
        ),
      );
    }

    final ProductoDetalle? producto = _producto;
    if (producto == null) {
      return const Center(
        child: Text(
          'Producto no disponible.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductoMedia(
            recursos: producto.recursosUtilizables,
            nombre: producto.nombre,
          ),
          const SizedBox(height: 20),
          if (producto.categoriaNombre.trim().isNotEmpty)
            Text(
              producto.categoriaNombre.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            producto.nombre,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            producto.precioFormateado,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          AgregarAlCarritoSection(producto: producto, onRecargar: _cargar),
          const SizedBox(height: 24),
          if ((producto.descripcion?.trim() ?? '').isNotEmpty) ...[
            const _Subtitulo('DESCRIPCIÓN'),
            const SizedBox(height: 8),
            Text(
              producto.descripcion!.trim(),
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (producto.tallas.isNotEmpty) ...[
            const _Subtitulo('TALLAS'),
            const SizedBox(height: 8),
            _Chips(valores: producto.tallas),
            const SizedBox(height: 20),
          ],
          if (producto.colores.isNotEmpty) ...[
            const _Subtitulo('COLORES'),
            const SizedBox(height: 8),
            _Chips(valores: producto.colores),
            const SizedBox(height: 20),
          ],
          DisponibilidadSection(
            productoId: producto.id,
            tallas: producto.tallasOpciones,
            colores: producto.coloresOpciones,
            filtros: widget.filtros,
            service: _service,
          ),
        ],
      ),
    );
  }
}

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

class _Chips extends StatelessWidget {
  const _Chips({required this.valores});

  final List<String> valores;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: valores
          .map(
            (String valor) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                valor,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
