import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/catalogo_filtros_model.dart';
import '../models/disponibilidad_model.dart';
import '../models/producto_model.dart';
import '../services/catalogo_service.dart';

/// Sección de disponibilidad por sucursal dentro del detalle de producto.
///
/// Consume `GET /productos/{id}/disponibilidad` y muestra el `stock_disponible`
/// exactamente como lo entrega el backend (nunca se recalcula).
class DisponibilidadSection extends StatefulWidget {
  const DisponibilidadSection({
    super.key,
    required this.productoId,
    required this.tallas,
    required this.colores,
    required this.filtros,
    this.service,
  });

  final int productoId;
  final List<OpcionVariante> tallas;
  final List<OpcionVariante> colores;

  /// Filtros del catálogo (temporadas y sucursales). Puede ser null.
  final CatalogoFiltros? filtros;

  /// Servicio inyectable (facilita pruebas).
  final CatalogoService? service;

  @override
  State<DisponibilidadSection> createState() => _DisponibilidadSectionState();
}

class _DisponibilidadSectionState extends State<DisponibilidadSection> {
  late final CatalogoService _service;
  late CatalogoFiltros _filtros;

  int? _sucursalId;
  int? _tallaId;
  int? _colorId;
  int? _temporadaId;

  bool _cargando = true;
  bool _cargandoFiltros = false;
  String? _error;
  DisponibilidadProducto? _disponibilidad;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CatalogoService();
    _filtros = widget.filtros ?? const CatalogoFiltros(
      categorias: <OpcionFiltro>[],
      tallas: <OpcionFiltro>[],
      colores: <OpcionFiltro>[],
      temporadas: <OpcionFiltro>[],
      colecciones: <ColeccionFiltro>[],
      sucursales: <SucursalFiltro>[],
    );
    _cargar();
    if (widget.filtros == null) _cargarFiltros();
  }

  int get _filtrosActivos {
    int total = 0;
    if (_sucursalId != null) total++;
    if (_tallaId != null) total++;
    if (_colorId != null) total++;
    if (_temporadaId != null) total++;
    return total;
  }

  Future<void> _cargarFiltros() async {
    setState(() => _cargandoFiltros = true);
    try {
      final CatalogoFiltros filtros = await _service.obtenerFiltros();
      if (!mounted) return;
      setState(() => _filtros = filtros);
    } catch (_) {
      // Los filtros son opcionales: si fallan, se muestran los que ya existan.
    } finally {
      if (mounted) setState(() => _cargandoFiltros = false);
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final DisponibilidadProducto resultado =
          await _service.obtenerDisponibilidad(
        widget.productoId,
        sucursalId: _sucursalId,
        tallaId: _tallaId,
        colorId: _colorId,
        temporadaId: _temporadaId,
      );
      if (!mounted) return;
      setState(() {
        _disponibilidad = resultado;
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
        _error = 'No pudimos cargar la disponibilidad. Inténtalo nuevamente.';
        _cargando = false;
      });
    }
  }

  Future<void> _abrirFiltros() async {
    final _FiltrosDisponibilidad? resultado =
        await showModalBottomSheet<_FiltrosDisponibilidad>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FiltrosDisponibilidadSheet(
        filtros: _filtros,
        tallas: widget.tallas,
        colores: widget.colores,
        seleccion: _FiltrosDisponibilidad(
          sucursalId: _sucursalId,
          tallaId: _tallaId,
          colorId: _colorId,
          temporadaId: _temporadaId,
        ),
      ),
    );

    if (resultado == null) return;
    setState(() {
      _sucursalId = resultado.sucursalId;
      _tallaId = resultado.tallaId;
      _colorId = resultado.colorId;
      _temporadaId = resultado.temporadaId;
    });
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'DISPONIBILIDAD',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _cargandoFiltros ? null : _abrirFiltros,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: Text(
                _filtrosActivos == 0
                    ? 'Filtrar'
                    : 'Filtrar ($_filtrosActivos)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildContenido(),
      ],
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return _MensajeEstado(
        icon: Icons.wifi_off_rounded,
        message: _error!,
        accionLabel: 'Reintentar',
        onAccion: _cargar,
      );
    }

    final DisponibilidadProducto? disponibilidad = _disponibilidad;
    if (disponibilidad == null || disponibilidad.estaVacio) {
      return const _MensajeEstado(
        icon: Icons.inventory_2_outlined,
        message: 'No hay disponibilidad registrada para estos filtros.',
      );
    }

    return Column(
      children: disponibilidad.sucursales
          .map((DisponibilidadSucursal sucursal) =>
              _SucursalDisponibilidad(sucursal: sucursal))
          .toList(),
    );
  }
}

class _SucursalDisponibilidad extends StatelessWidget {
  const _SucursalDisponibilidad({required this.sucursal});

  final DisponibilidadSucursal sucursal;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sucursal.sucursal,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${sucursal.variantesConStock} con stock',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (sucursal.variantes.isEmpty)
            const Text(
              'Sin variantes.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            )
          else
            ...sucursal.variantes.map(
              (DisponibilidadVariante variante) =>
                  _VarianteDisponibilidad(variante: variante),
            ),
        ],
      ),
    );
  }
}

class _VarianteDisponibilidad extends StatelessWidget {
  const _VarianteDisponibilidad({required this.variante});

  final DisponibilidadVariante variante;

  @override
  Widget build(BuildContext context) {
    final bool conStock = variante.tieneStock;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Talla ${variante.talla} · ${variante.color}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'SKU ${variante.sku} · ${variante.temporada}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: conStock
                  ? AppColors.primary.withValues(alpha: 0.16)
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: conStock ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Text(
              '${variante.stockDisponible} disp.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color:
                    conStock ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MensajeEstado extends StatelessWidget {
  const _MensajeEstado({
    required this.icon,
    required this.message,
    this.accionLabel,
    this.onAccion,
  });

  final IconData icon;
  final String message;
  final String? accionLabel;
  final VoidCallback? onAccion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 26),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
          if (accionLabel != null && onAccion != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onAccion,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(accionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Estado de filtros de disponibilidad.
class _FiltrosDisponibilidad {
  const _FiltrosDisponibilidad({
    this.sucursalId,
    this.tallaId,
    this.colorId,
    this.temporadaId,
  });

  final int? sucursalId;
  final int? tallaId;
  final int? colorId;
  final int? temporadaId;

  int get activos {
    int total = 0;
    if (sucursalId != null) total++;
    if (tallaId != null) total++;
    if (colorId != null) total++;
    if (temporadaId != null) total++;
    return total;
  }
}

/// Bottom sheet de filtros de disponibilidad.
class _FiltrosDisponibilidadSheet extends StatefulWidget {
  const _FiltrosDisponibilidadSheet({
    required this.filtros,
    required this.tallas,
    required this.colores,
    required this.seleccion,
  });

  final CatalogoFiltros filtros;
  final List<OpcionVariante> tallas;
  final List<OpcionVariante> colores;
  final _FiltrosDisponibilidad seleccion;

  @override
  State<_FiltrosDisponibilidadSheet> createState() =>
      _FiltrosDisponibilidadSheetState();
}

class _FiltrosDisponibilidadSheetState
    extends State<_FiltrosDisponibilidadSheet> {
  int? _sucursalId;
  int? _tallaId;
  int? _colorId;
  int? _temporadaId;

  @override
  void initState() {
    super.initState();
    _sucursalId = widget.seleccion.sucursalId;
    _tallaId = widget.seleccion.tallaId;
    _colorId = widget.seleccion.colorId;
    _temporadaId = widget.seleccion.temporadaId;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 44,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'FILTRAR DISPONIBILIDAD',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Grupo(
                        titulo: 'Sucursal',
                        opciones: widget.filtros.sucursales
                            .map((SucursalFiltro s) =>
                                _Opcion(id: s.id, nombre: s.etiqueta))
                            .toList(),
                        seleccionado: _sucursalId,
                        onSeleccion: (id) => setState(() => _sucursalId = id),
                      ),
                      _Grupo(
                        titulo: 'Talla',
                        opciones: widget.tallas
                            .map((OpcionVariante o) =>
                                _Opcion(id: o.id, nombre: o.nombre))
                            .toList(),
                        seleccionado: _tallaId,
                        onSeleccion: (id) => setState(() => _tallaId = id),
                      ),
                      _Grupo(
                        titulo: 'Color',
                        opciones: widget.colores
                            .map((OpcionVariante o) =>
                                _Opcion(id: o.id, nombre: o.nombre))
                            .toList(),
                        seleccionado: _colorId,
                        onSeleccion: (id) => setState(() => _colorId = id),
                      ),
                      _Grupo(
                        titulo: 'Temporada',
                        opciones: widget.filtros.temporadas
                            .map((OpcionFiltro o) =>
                                _Opcion(id: o.id, nombre: o.nombre))
                            .toList(),
                        seleccionado: _temporadaId,
                        onSeleccion: (id) => setState(() => _temporadaId = id),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _sucursalId = null;
                        _tallaId = null;
                        _colorId = null;
                        _temporadaId = null;
                      }),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Limpiar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(context).pop(
                            _FiltrosDisponibilidad(
                              sucursalId: _sucursalId,
                              tallaId: _tallaId,
                              colorId: _colorId,
                              temporadaId: _temporadaId,
                            ),
                          ),
                          child: const SizedBox(
                            height: 50,
                            child: Center(
                              child: Text(
                                'Aplicar',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Opcion {
  const _Opcion({required this.id, required this.nombre});

  final int id;
  final String nombre;
}

class _Grupo extends StatelessWidget {
  const _Grupo({
    required this.titulo,
    required this.opciones,
    required this.seleccionado,
    required this.onSeleccion,
  });

  final String titulo;
  final List<_Opcion> opciones;
  final int? seleccionado;
  final ValueChanged<int?> onSeleccion;

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
          children: opciones
              .map(
                (_Opcion opcion) => Material(
                  color: seleccionado == opcion.id
                      ? AppColors.primary.withValues(alpha: 0.22)
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => onSeleccion(
                      seleccionado == opcion.id ? null : opcion.id,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: seleccionado == opcion.id
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        opcion.nombre,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: seleccionado == opcion.id
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: seleccionado == opcion.id
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
