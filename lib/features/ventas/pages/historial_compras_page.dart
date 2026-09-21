import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatters.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../models/historial_compras_model.dart';
import '../services/historial_compras_service.dart';
import '../widgets/historial_compra_card.dart';
import 'comprobante_venta_page.dart';
import 'historial_compra_detalle_page.dart';

/// CU24 – Historial de compras del CLIENTE autenticado (solo lectura).
///
/// Flujo: Perfil -> HistorialComprasPage -> HistorialComprasService ->
/// `GET /ventas/historial` (el backend identifica al cliente por el JWT).
///
/// La pantalla permite filtrar (estado, canal, rango de fechas) y navegar
/// páginas con la metadata real del backend. No modifica ventas, no busca por
/// código (el endpoint no tiene ese filtro) y no descarga todo el historial.
class HistorialComprasPage extends StatefulWidget {
  /// Crea la pantalla del historial de compras.
  const HistorialComprasPage({super.key, this.service});

  /// Servicio inyectable (mismo patrón que CU19/CU22/CU23).
  final HistorialComprasService? service;

  @override
  State<HistorialComprasPage> createState() => _HistorialComprasPageState();
}

class _HistorialComprasPageState extends State<HistorialComprasPage> {
  late final HistorialComprasService _service;

  bool _cargando = true;
  String? _error;
  int? _statusError;
  HistorialComprasResponse? _historial;

  // Filtros activos (null = sin filtro).
  EstadoHistorial? _estado;
  CanalHistorial? _canal;
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  int _pagina = 1;

  /// Tamaño de página por defecto del backend (20).
  static const int _tamanoPagina =
      HistorialComprasService.tamanoPaginaPorDefecto;

  static const String _errorRed =
      'No pudimos cargar tu historial.\n'
      'Verifica tu conexión e inténtalo nuevamente.';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? HistorialComprasService();
    // Primera carga: página 1 y sin filtros.
    _cargar();
  }

  /// Consulta el historial con los filtros y la página actuales.
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _statusError = null;
    });

    try {
      final HistorialComprasResponse resultado = await _service.obtenerHistorial(
        estado: _estado,
        canal: _canal,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
        pagina: _pagina,
        tamanoPagina: _tamanoPagina,
      );
      if (!mounted) return;
      setState(() {
        _historial = resultado;
        _cargando = false;
      });
    } on HistorialComprasException catch (error) {
      if (!mounted) return;
      if (error.unauthorized) {
        setState(() => _cargando = false);
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      setState(() {
        _cargando = false;
        _statusError = error.statusCode;
        // Sin status = fallo de red/servidor: mensaje propio de CU24.
        _error = error.statusCode == null ? _errorRed : error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _statusError = null;
        _error = _errorRed;
      });
    }
  }

  /// `true` si hay algún filtro activo.
  bool get _hayFiltros =>
      _estado != null ||
      _canal != null ||
      _fechaDesde != null ||
      _fechaHasta != null;

  /// Cantidad de filtros activos (se muestra en el botón FILTROS).
  int get _cantidadFiltros {
    int total = 0;
    if (_estado != null) total++;
    if (_canal != null) total++;
    if (_fechaDesde != null) total++;
    if (_fechaHasta != null) total++;
    return total;
  }

  /// Abre el bottom sheet de filtros y aplica la selección.
  Future<void> _abrirFiltros() async {
    if (_cargando) return;

    final _FiltrosSeleccion? seleccion =
        await showModalBottomSheet<_FiltrosSeleccion>(
          context: context,
          backgroundColor: AppColors.surface,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => _FiltrosSheet(
            estado: _estado,
            canal: _canal,
            fechaDesde: _fechaDesde,
            fechaHasta: _fechaHasta,
          ),
        );

    // CANCELAR: sin cambios y sin peticiones.
    if (seleccion == null || !mounted) return;
    _aplicarFiltros(seleccion);
  }

  /// Aplica los filtros elegidos y vuelve a la página 1.
  void _aplicarFiltros(_FiltrosSeleccion seleccion) {
    // Evita doble petición mientras hay una consulta en curso.
    if (_cargando) return;
    setState(() {
      _estado = seleccion.estado;
      _canal = seleccion.canal;
      _fechaDesde = seleccion.fechaDesde;
      _fechaHasta = seleccion.fechaHasta;
      _pagina = 1;
    });
    _cargar();
  }

  /// Limpia los filtros y recarga desde la página 1.
  void _limpiarFiltros() {
    if (_cargando) return;
    setState(() {
      _estado = null;
      _canal = null;
      _fechaDesde = null;
      _fechaHasta = null;
      _pagina = 1;
    });
    _cargar();
  }

  /// Cambia de página conservando los filtros activos.
  void _irAPagina(int pagina) {
    final HistorialComprasResponse? actual = _historial;
    if (actual == null || _cargando) return;
    if (pagina < 1) return;
    if (actual.totalPaginas > 0 && pagina > actual.totalPaginas) return;
    setState(() => _pagina = pagina);
    _cargar();
  }

  /// Abre el detalle. El detalle vuelve a consultar el backend porque es el
  /// backend quien valida la propiedad de la venta.
  void _verDetalle(int ventaId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistorialCompraDetallePage(ventaId: ventaId),
      ),
    );
  }

  /// Reutiliza CU23 tal cual: no duplica modelo, service, PDF ni impresión.
  void _verComprobante(int ventaId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComprobanteVentaPage(ventaId: ventaId),
      ),
    );
  }

  void _volver() => Navigator.of(context).pop();

  /// REINTENTAR solo si el fallo puede resolverse repitiendo la consulta.
  bool get _permiteReintentar {
    final int? status = _statusError;
    if (status == null) return true;
    return status >= 500;
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
          'MIS COMPRAS',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            // Recarga de página/filtros sin desmontar el contenido actual.
            if (_cargando && _historial != null)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: AppColors.surface,
                color: AppColors.primary,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                children: <Widget>[
                  const Text(
                    'Historial de compras',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Revisa tus compras, consulta su estado y accede a tus '
                    'comprobantes.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ResumenHistorial(
                    historial: _historial,
                    cantidadFiltros: _cantidadFiltros,
                    habilitado: !_cargando,
                    onFiltros: _abrirFiltros,
                    onLimpiar: _limpiarFiltros,
                  ),
                  const SizedBox(height: 18),
                  _contenido(),
                ],
              ),
            ),
            if (_mostrarPaginador)
              _PaginadorHistorial(
                pagina: _historial?.pagina ?? 1,
                totalPaginas: _historial?.totalPaginas ?? 0,
                habilitado: !_cargando,
                onAnterior: () => _irAPagina((_historial?.pagina ?? 1) - 1),
                onSiguiente: () => _irAPagina((_historial?.pagina ?? 1) + 1),
              ),
          ],
        ),
      ),
    );
  }

  /// El paginador solo se muestra cuando hay un historial consultado con
  /// resultados (o con más de una página por recorrer).
  bool get _mostrarPaginador {
    final HistorialComprasResponse? historial = _historial;
    if (historial == null || _error != null) return false;
    return historial.items.isNotEmpty;
  }

  /// Listado, estados vacíos y error, según el resultado de la consulta.
  Widget _contenido() {
    if (_cargando && _historial == null) return const _CargandoHistorial();

    final String? error = _error;
    if (error != null) {
      return _MensajeEstado(
        icono: Icons.history_toggle_off_rounded,
        titulo: 'No pudimos mostrar tu historial',
        mensaje: error,
        principal: _permiteReintentar
            ? ('REINTENTAR', Icons.refresh_rounded, _cargar)
            : null,
        secundaria: _hayFiltros
            ? ('LIMPIAR FILTROS', Icons.filter_alt_off_rounded, _limpiarFiltros)
            : ('VOLVER', Icons.arrow_back_rounded, _volver),
      );
    }

    final HistorialComprasResponse historial =
        _historial ?? HistorialComprasResponse.vacio;

    if (historial.items.isEmpty) {
      // Filtros sin resultados se distingue del historial realmente vacío.
      if (_hayFiltros) {
        return _MensajeEstado(
          icono: Icons.filter_alt_off_rounded,
          titulo: 'No encontramos compras con estos filtros.',
          mensaje: 'Prueba con otro estado, canal o rango de fechas.',
          principal: (
            'LIMPIAR FILTROS',
            Icons.filter_alt_off_rounded,
            _limpiarFiltros,
          ),
          secundaria: ('VOLVER', Icons.arrow_back_rounded, _volver),
        );
      }

      return _MensajeEstado(
        icono: Icons.shopping_bag_rounded,
        titulo: 'Aún no tienes compras registradas.',
        mensaje: 'Explora nuestro catálogo y encuentra tu próximo look.',
        principal: ('VOLVER', Icons.arrow_back_rounded, _volver),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final HistorialCompraResumen compra in historial.items) ...<Widget>[
          HistorialCompraCard(
            compra: compra,
            onVerDetalle: _cargando ? null : () => _verDetalle(compra.ventaId),
            // Solo las COMPLETADA tienen comprobante en CU23.
            onVerComprobante: compra.permiteComprobante && !_cargando
                ? () => _verComprobante(compra.ventaId)
                : null,
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

/// Resumen superior: solo metadata real del backend.
///
/// CU24 no devuelve estadísticas globales (monto acumulado, completadas
/// totales, etc.), así que aquí solo se muestran los registros encontrados y la
/// posición de la página.
class _ResumenHistorial extends StatelessWidget {
  const _ResumenHistorial({
    required this.historial,
    required this.cantidadFiltros,
    required this.habilitado,
    required this.onFiltros,
    required this.onLimpiar,
  });

  final HistorialComprasResponse? historial;
  final int cantidadFiltros;
  final bool habilitado;
  final VoidCallback onFiltros;
  final VoidCallback onLimpiar;

  @override
  Widget build(BuildContext context) {
    final HistorialComprasResponse? datos = historial;
    final bool hayFiltros = cantidadFiltros > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'COMPRAS ENCONTRADAS',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const Icon(
                Icons.receipt_long_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            datos == null ? '...' : '${datos.totalRegistros}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            datos == null
                ? 'Consultando tu historial...'
                : 'Página ${datos.pagina} de ${datos.totalPaginas} · '
                      'Mostrando ${datos.items.length} resultados',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: habilitado ? onFiltros : null,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(
                    cantidadFiltros == 0
                        ? 'FILTROS'
                        : 'FILTROS ($cantidadFiltros)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  style: _estiloBotonSecundario,
                ),
              ),
              if (hayFiltros) ...<Widget>[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: habilitado ? onLimpiar : null,
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                    label: const Text(
                      'LIMPIAR',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    style: _estiloBotonSecundario,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Estilo compartido de los botones secundarios de CU24.
ButtonStyle get _estiloBotonSecundario => OutlinedButton.styleFrom(
  foregroundColor: AppColors.textPrimary,
  side: const BorderSide(color: AppColors.border),
  minimumSize: const Size.fromHeight(46),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
);

/// Indicador de la primera carga del historial.
class _CargandoHistorial extends StatelessWidget {
  const _CargandoHistorial();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 28,
            width: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Cargando tus compras...',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Estado de la pantalla: historial vacío, filtros sin resultados o error.
class _MensajeEstado extends StatelessWidget {
  const _MensajeEstado({
    required this.icono,
    required this.titulo,
    required this.mensaje,
    this.principal,
    this.secundaria,
  });

  final IconData icono;
  final String titulo;
  final String mensaje;

  /// Acción principal y secundaria como `(texto, icono, acción)`.
  final (String, IconData, VoidCallback)? principal;
  final (String, IconData, VoidCallback)? secundaria;

  @override
  Widget build(BuildContext context) {
    final (String, IconData, VoidCallback)? accionPrincipal = principal;
    final (String, IconData, VoidCallback)? accionSecundaria = secundaria;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: <Widget>[
          Icon(icono, size: 34, color: AppColors.primary),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 18),
          if (accionPrincipal != null)
            BotonGradiente(
              label: accionPrincipal.$1,
              icon: accionPrincipal.$2,
              onPressed: accionPrincipal.$3,
            ),
          if (accionPrincipal != null && accionSecundaria != null)
            const SizedBox(height: 10),
          if (accionSecundaria != null)
            OutlinedButton.icon(
              onPressed: accionSecundaria.$3,
              icon: Icon(accionSecundaria.$2, size: 18),
              label: Text(
                accionSecundaria.$1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              style: _estiloBotonSecundario,
            ),
        ],
      ),
    );
  }
}

/// Paginación explícita ANTERIOR / SIGUIENTE con la metadata real del backend.
class _PaginadorHistorial extends StatelessWidget {
  const _PaginadorHistorial({
    required this.pagina,
    required this.totalPaginas,
    required this.habilitado,
    required this.onAnterior,
    required this.onSiguiente,
  });

  final int pagina;
  final int totalPaginas;
  final bool habilitado;
  final VoidCallback onAnterior;
  final VoidCallback onSiguiente;

  @override
  Widget build(BuildContext context) {
    final bool hayAnterior = habilitado && pagina > 1;
    final bool haySiguiente =
        habilitado && totalPaginas > 0 && pagina < totalPaginas;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Página $pagina de ${totalPaginas == 0 ? 1 : totalPaginas}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hayAnterior ? onAnterior : null,
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    label: const Text(
                      'ANTERIOR',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    style: _estiloBotonSecundario,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: haySiguiente ? onSiguiente : null,
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    label: const Text(
                      'SIGUIENTE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    style: _estiloBotonSecundario,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Selección de filtros devuelta por el bottom sheet.
class _FiltrosSeleccion {
  const _FiltrosSeleccion({
    this.estado,
    this.canal,
    this.fechaDesde,
    this.fechaHasta,
  });

  final EstadoHistorial? estado;
  final CanalHistorial? canal;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;
}

/// Bottom sheet de filtros de CU24 (ESTADO, CANAL, DESDE, HASTA).
///
/// Los filtros se aplican con un botón (sin debounce ni consultas mientras se
/// elige) y el rango de fechas se valida antes de llamar al backend.
class _FiltrosSheet extends StatefulWidget {
  const _FiltrosSheet({
    this.estado,
    this.canal,
    this.fechaDesde,
    this.fechaHasta,
  });

  final EstadoHistorial? estado;
  final CanalHistorial? canal;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;

  @override
  State<_FiltrosSheet> createState() => _FiltrosSheetState();
}

class _FiltrosSheetState extends State<_FiltrosSheet> {
  EstadoHistorial? _estado;
  CanalHistorial? _canal;
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  static const String _errorRango =
      'La fecha desde no puede ser posterior a la fecha hasta.';

  @override
  void initState() {
    super.initState();
    // Los filtros activos se mantienen visibles al reabrir el sheet.
    _estado = widget.estado;
    _canal = widget.canal;
    _fechaDesde = widget.fechaDesde;
    _fechaHasta = widget.fechaHasta;
  }

  /// `showDatePicker`: solo se conserva día/mes/año (se envía `YYYY-MM-DD`).
  Future<void> _elegirFecha({required bool desde}) async {
    final DateTime hoy = DateTime.now();
    final DateTime? elegida = await showDatePicker(
      context: context,
      initialDate: (desde ? _fechaDesde : _fechaHasta) ?? hoy,
      firstDate: DateTime(2020),
      lastDate: DateTime(hoy.year + 1, 12, 31),
      helpText: desde ? 'FECHA DESDE' : 'FECHA HASTA',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
    );
    if (elegida == null || !mounted) return;

    final DateTime soloFecha = DateTime(
      elegida.year,
      elegida.month,
      elegida.day,
    );
    setState(() {
      if (desde) {
        _fechaDesde = soloFecha;
      } else {
        _fechaHasta = soloFecha;
      }
    });
  }

  /// Valida el rango y devuelve la selección (no consulta el backend aquí).
  void _aplicar() {
    final DateTime? desde = _fechaDesde;
    final DateTime? hasta = _fechaHasta;

    if (desde != null && hasta != null && desde.isAfter(hasta)) {
      // Se avisa sin llamar al backend: el backend sigue siendo la autoridad.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(_errorRango),
            duration: Duration(seconds: 3),
          ),
        );
      return;
    }

    Navigator.of(context).pop(
      _FiltrosSeleccion(
        estado: _estado,
        canal: _canal,
        fechaDesde: desde,
        fechaHasta: hasta,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'FILTROS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cerrar',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _EtiquetaFiltro('Estado'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _chipFiltro(
                  label: 'Todos',
                  seleccionado: _estado == null,
                  onTap: () => setState(() => _estado = null),
                ),
                for (final EstadoHistorial estado in EstadoHistorial.values)
                  _chipFiltro(
                    label: estado.etiqueta,
                    seleccionado: _estado == estado,
                    onTap: () => setState(() => _estado = estado),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const _EtiquetaFiltro('Canal'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _chipFiltro(
                  label: 'Todos',
                  seleccionado: _canal == null,
                  onTap: () => setState(() => _canal = null),
                ),
                for (final CanalHistorial canal in CanalHistorial.values)
                  _chipFiltro(
                    label: canal.etiqueta,
                    seleccionado: _canal == canal,
                    onTap: () => setState(() => _canal = canal),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const _EtiquetaFiltro('Desde'),
            _CampoFecha(
              valor: _fechaDesde,
              onTap: () => _elegirFecha(desde: true),
              onLimpiar: _fechaDesde == null
                  ? null
                  : () => setState(() => _fechaDesde = null),
            ),
            const SizedBox(height: 14),
            const _EtiquetaFiltro('Hasta'),
            _CampoFecha(
              valor: _fechaHasta,
              onTap: () => _elegirFecha(desde: false),
              onLimpiar: _fechaHasta == null
                  ? null
                  : () => setState(() => _fechaHasta = null),
            ),
            const SizedBox(height: 22),
            BotonGradiente(
              label: 'APLICAR FILTROS',
              icon: Icons.check_rounded,
              onPressed: _aplicar,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _limpiar,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text(
                'LIMPIAR',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              style: _estiloBotonSecundario,
            ),
          ],
        ),
      ),
    );
  }

  /// LIMPIAR: deja todos los filtros vacíos y aplica la selección vacía.
  void _limpiar() => Navigator.of(context).pop(const _FiltrosSeleccion());

  Widget _chipFiltro({
    required String label,
    required bool seleccionado,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: seleccionado ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
      selected: seleccionado,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      backgroundColor: AppColors.surfaceVariant,
      selectedColor: AppColors.primary.withValues(alpha: 0.20),
      side: BorderSide(
        color: seleccionado ? AppColors.primary : AppColors.border,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  // ==CU24_LISTA_PARTE_F==
}

/// Etiqueta de sección del bottom sheet de filtros.
class _EtiquetaFiltro extends StatelessWidget {
  const _EtiquetaFiltro(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto,
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

/// Campo de fecha que abre `showDatePicker` y muestra `dd/MM/yyyy`.
class _CampoFecha extends StatelessWidget {
  const _CampoFecha({required this.valor, required this.onTap, this.onLimpiar});

  final DateTime? valor;
  final VoidCallback onTap;

  /// Quita la fecha elegida; `null` cuando no hay nada que quitar.
  final VoidCallback? onLimpiar;

  @override
  Widget build(BuildContext context) {
    final DateTime? fecha = valor;
    final bool vacio = fecha == null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    vacio ? 'Sin definir' : formatearFecha(fecha),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: vacio
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (onLimpiar != null)
                  GestureDetector(
                    onTap: onLimpiar,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
