import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/catalogo_filtros_model.dart';

/// Bottom sheet móvil de filtros del catálogo.
///
/// Todas las opciones provienen de `GET /catalogo/filtros`. Al cambiar la
/// temporada se recalculan las colecciones compatibles y se descarta una
/// colección que ya no corresponda.
class CatalogoFiltrosSheet extends StatefulWidget {
  const CatalogoFiltrosSheet({
    super.key,
    required this.filtros,
    required this.seleccion,
  });

  final CatalogoFiltros filtros;
  final CatalogoFiltrosSeleccion seleccion;

  /// Presenta el sheet y devuelve la selección aplicada, o `null` si se cierra.
  static Future<CatalogoFiltrosSeleccion?> mostrar(
    BuildContext context, {
    required CatalogoFiltros filtros,
    required CatalogoFiltrosSeleccion seleccion,
  }) {
    return showModalBottomSheet<CatalogoFiltrosSeleccion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          CatalogoFiltrosSheet(filtros: filtros, seleccion: seleccion),
    );
  }

  @override
  State<CatalogoFiltrosSheet> createState() => _CatalogoFiltrosSheetState();
}

class _CatalogoFiltrosSheetState extends State<CatalogoFiltrosSheet> {
  late CatalogoFiltrosSeleccion _seleccion;

  @override
  void initState() {
    super.initState();
    _seleccion = widget.seleccion;
  }

  void _seleccionarTemporada(int? temporadaId) {
    setState(() {
      _seleccion = _seleccion.copyWith(temporadaId: temporadaId);
      if (!widget.filtros.coleccionCompatible(
        _seleccion.coleccionId,
        temporadaId,
      )) {
        _seleccion = _seleccion.copyWith(coleccionId: null);
      }
    });
  }

  void _limpiar() {
    setState(() => _seleccion = const CatalogoFiltrosSeleccion());
  }

  @override
  Widget build(BuildContext context) {
    final List<ColeccionFiltro> colecciones = widget.filtros.coleccionesDe(
      _seleccion.temporadaId,
    );

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
              Row(
                children: [
                  const Text(
                    'FILTROS',
                    style: TextStyle(
                      fontSize: 14,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (_seleccion.activos > 0)
                    Text(
                      '${_seleccion.activos} activo(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GrupoOpciones(
                        titulo: 'Categoría',
                        opciones: widget.filtros.categorias,
                        seleccionado: _seleccion.categoriaId,
                        onSeleccion: (id) => setState(
                          () =>
                              _seleccion = _seleccion.copyWith(categoriaId: id),
                        ),
                      ),
                      _GrupoOpciones(
                        titulo: 'Talla',
                        opciones: widget.filtros.tallas,
                        seleccionado: _seleccion.tallaId,
                        onSeleccion: (id) => setState(
                          () => _seleccion = _seleccion.copyWith(tallaId: id),
                        ),
                      ),
                      _GrupoOpciones(
                        titulo: 'Color',
                        opciones: widget.filtros.colores,
                        seleccionado: _seleccion.colorId,
                        onSeleccion: (id) => setState(
                          () => _seleccion = _seleccion.copyWith(colorId: id),
                        ),
                      ),
                      _GrupoOpciones(
                        titulo: 'Temporada',
                        opciones: widget.filtros.temporadas,
                        seleccionado: _seleccion.temporadaId,
                        onSeleccion: _seleccionarTemporada,
                      ),
                      _GrupoColecciones(
                        colecciones: colecciones,
                        seleccionado: _seleccion.coleccionId,
                        onSeleccion: (id) => setState(
                          () =>
                              _seleccion = _seleccion.copyWith(coleccionId: id),
                        ),
                      ),
                      _GrupoSucursales(
                        sucursales: widget.filtros.sucursales,
                        seleccionado: _seleccion.sucursalId,
                        onSeleccion: (id) => setState(
                          () =>
                              _seleccion = _seleccion.copyWith(sucursalId: id),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppColors.primary,
                        title: const Text(
                          'Solo con stock disponible',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        value: _seleccion.soloConStock,
                        onChanged: (bool value) => setState(
                          () => _seleccion = _seleccion.copyWith(
                            soloConStock: value,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _limpiar,
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
                          onTap: () => Navigator.of(context).pop(_seleccion),
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

class _TituloGrupo extends StatelessWidget {
  const _TituloGrupo(this.titulo);

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
    );
  }
}

class _GrupoOpciones extends StatelessWidget {
  const _GrupoOpciones({
    required this.titulo,
    required this.opciones,
    required this.seleccionado,
    required this.onSeleccion,
  });

  final String titulo;
  final List<OpcionFiltro> opciones;
  final int? seleccionado;
  final ValueChanged<int?> onSeleccion;

  @override
  Widget build(BuildContext context) {
    if (opciones.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TituloGrupo(titulo),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opciones
              .map(
                (OpcionFiltro opcion) => _ChipFiltro(
                  label: opcion.nombre,
                  seleccionado: seleccionado == opcion.id,
                  onTap: () =>
                      onSeleccion(seleccionado == opcion.id ? null : opcion.id),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _GrupoColecciones extends StatelessWidget {
  const _GrupoColecciones({
    required this.colecciones,
    required this.seleccionado,
    required this.onSeleccion,
  });

  final List<ColeccionFiltro> colecciones;
  final int? seleccionado;
  final ValueChanged<int?> onSeleccion;

  @override
  Widget build(BuildContext context) {
    if (colecciones.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TituloGrupo('Colección'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colecciones
              .map(
                (ColeccionFiltro coleccion) => _ChipFiltro(
                  label: coleccion.nombre,
                  seleccionado: seleccionado == coleccion.id,
                  onTap: () => onSeleccion(
                    seleccionado == coleccion.id ? null : coleccion.id,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _GrupoSucursales extends StatelessWidget {
  const _GrupoSucursales({
    required this.sucursales,
    required this.seleccionado,
    required this.onSeleccion,
  });

  final List<SucursalFiltro> sucursales;
  final int? seleccionado;
  final ValueChanged<int?> onSeleccion;

  @override
  Widget build(BuildContext context) {
    if (sucursales.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TituloGrupo('Sucursal'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sucursales
              .map(
                (SucursalFiltro sucursal) => _ChipFiltro(
                  label: sucursal.etiqueta,
                  seleccionado: seleccionado == sucursal.id,
                  onTap: () => onSeleccion(
                    seleccionado == sucursal.id ? null : sucursal.id,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ChipFiltro extends StatelessWidget {
  const _ChipFiltro({
    required this.label,
    required this.seleccionado,
    required this.onTap,
  });

  final String label;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: seleccionado
          ? AppColors.primary.withValues(alpha: 0.22)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: seleccionado ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: seleccionado ? FontWeight.w700 : FontWeight.w500,
              color: seleccionado ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
