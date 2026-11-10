import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../carrito/widgets/agregar_al_carrito_section.dart';
import '../../vestidor_virtual/services/vestidor_flow_service.dart';
import '../models/catalogo_filtros_model.dart';
import '../models/disponibilidad_model.dart';
import '../models/producto_model.dart';
import '../services/catalogo_service.dart';
import '../services/offline_catalogo_reader.dart';
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
    this.vestidorFlow,
    this.offline = false,
    this.offlineReader,
  });

  final int productoId;

  /// Filtros del catálogo ya cargados (opcional, evita una petición extra).
  final CatalogoFiltros? filtros;

  /// Servicio inyectable (facilita pruebas).
  final CatalogoService? service;

  /// Servicio inyectable del flujo del vestidor virtual (facilita pruebas).
  final VestidorFlowService? vestidorFlow;
  final bool offline;
  final OfflineCatalogoReader? offlineReader;

  @override
  State<ProductoDetallePage> createState() => _ProductoDetallePageState();
}

class _ProductoDetallePageState extends State<ProductoDetallePage> {
  late final CatalogoService _service;
  late final OfflineCatalogoReader _offlineReader;
  bool _cargando = true;
  String? _error;
  ProductoDetalle? _producto;
  CatalogoFiltros? _filtros;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CatalogoService();
    _offlineReader = widget.offlineReader ?? OfflineCatalogoReader();
    _filtros = widget.filtros;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final ProductoDetalle? local = widget.offline
          ? await _offlineReader.detalle(widget.productoId)
          : null;
      if (widget.offline && local == null) {
        throw const CatalogException(
          'Producto no disponible en la descarga local.',
        );
      }
      final ProductoDetalle producto =
          local ?? await _service.obtenerProducto(widget.productoId);
      CatalogoFiltros? filtros = _filtros;
      if (filtros == null && !widget.offline) {
        try {
          filtros = await _service.obtenerFiltros();
        } catch (_) {
          // Sin filtros no se puede resolver temporada_id; el alta se bloquea.
        }
      }
      if (!mounted) return;
      setState(() {
        _producto = producto;
        _filtros = filtros;
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
          if (widget.offline)
            const _AvisoOfflineDetalle()
          else
            AgregarAlCarritoSection(
              producto: producto,
              filtros: _filtros,
              onRecargar: _cargar,
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.checkroom_rounded, size: 18),
              label: const Text(
                'VESTIDOR VIRTUAL · PRÓXIMAMENTE',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.inactive,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
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
          if (widget.offline)
            _DisponibilidadOffline(filas: producto.disponibilidad)
          else
            DisponibilidadSection(
              productoId: producto.id,
              tallas: producto.tallasOpciones,
              colores: producto.coloresOpciones,
              filtros: _filtros,
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

/// Aviso cuando el detalle se consulta desde la copia SQLite CU18.
class _AvisoOfflineDetalle extends StatelessWidget {
  const _AvisoOfflineDetalle();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.offline_bolt_outlined, color: AppColors.primary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Estás consultando la copia local. Agregar al carrito requiere '
              'conexión y stock confirmado por el backend.',
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

/// Disponibilidad del último snapshot local (stock NO confirmado en vivo).
class _DisponibilidadOffline extends StatelessWidget {
  const _DisponibilidadOffline({required this.filas});

  final List<DisponibilidadVariante> filas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DISPONIBILIDAD LOCAL (ÚLTIMO STOCK CONOCIDO)',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (filas.isEmpty)
          const Text(
            'Sin stock registrado en la copia local.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          )
        else
          for (final DisponibilidadVariante fila in filas)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${fila.sucursal} · Talla ${fila.talla} · ${fila.color}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${fila.stockDisponible} disp.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
