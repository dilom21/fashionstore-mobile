import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../models/reserva_model.dart';
import '../services/reserva_service.dart';
import '../widgets/reserva_card.dart';
import '../widgets/reserva_empty_state.dart';
import 'reserva_detalle_page.dart';

/// CU16 – "Mis reservas": reservas reales del cliente (`GET /reservas`).
class ReservasPage extends StatefulWidget {
  const ReservasPage({super.key, this.onVerCarrito, this.service});

  /// Lleva a la pestaña Carrito (usado por el estado vacío).
  final VoidCallback? onVerCarrito;

  /// Servicio inyectable (facilita pruebas).
  final ReservaService? service;

  @override
  State<ReservasPage> createState() => _ReservasPageState();
}

/// Filtros visibles del listado.
///
/// VENCIDA no tiene filtro propio: aparece dentro de "Todas" como estado
/// histórico y la app no ejecuta ninguna lógica sobre ella.
enum _FiltroReserva {
  todas('Todas', null),
  pendientes('Pendientes', 'PENDIENTE'),
  confirmadas('Confirmadas', 'CONFIRMADA'),
  atendidas('Atendidas', 'ATENDIDA'),
  canceladas('Canceladas', 'CANCELADA');

  const _FiltroReserva(this.etiqueta, this.estado);

  final String etiqueta;
  final String? estado;
}

class _ReservasPageState extends State<ReservasPage> {
  late final ReservaService _service;

  _FiltroReserva _filtro = _FiltroReserva.todas;
  List<ReservaResumen> _reservas = <ReservaResumen>[];
  int _total = 0;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ReservaService();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final ReservaListaResponse respuesta = await _service.listarReservas(
        estado: _filtro.estado,
      );
      if (!mounted) return;
      setState(() {
        _reservas = respuesta.items;
        _total = respuesta.totalReservas;
        _cargando = false;
      });
    } on ReservaException catch (error) {
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
        _error = 'No pudimos cargar tus reservas. Inténtalo nuevamente.';
        _cargando = false;
      });
    }
  }

  void _cambiarFiltro(_FiltroReserva filtro) {
    if (_filtro == filtro) return;
    setState(() => _filtro = filtro);
    _cargar();
  }

  Future<void> _verDetalle(ReservaResumen reserva) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReservaDetallePage(reservaId: reserva.reservaId),
      ),
    );
    // La reserva pudo cancelarse desde el detalle.
    if (mounted) await _cargar();
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
          'MIS RESERVAS',
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

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _cargar,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: [
              _EncabezadoReservas(total: _total),
              const SizedBox(height: 16),
              _FiltrosReserva(
                seleccionado: _filtro,
                onSeleccion: _cambiarFiltro,
              ),
              const SizedBox(height: 18),
              if (_reservas.isEmpty)
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.45,
                  child: _filtro == _FiltroReserva.todas
                      ? ReservaEmptyState(onVerCarrito: widget.onVerCarrito)
                      : const _SinResultados(),
                )
              else
                ..._reservas.map(
                  (ReservaResumen reserva) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ReservaCard(
                      reserva: reserva,
                      onVerDetalle: () => _verDetalle(reserva),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

}

/// Encabezado del listado: título, subtítulo y total real de reservas.
class _EncabezadoReservas extends StatelessWidget {
  const _EncabezadoReservas({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Mis reservas',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            _ContadorReservas(total: total),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Consulta las prendas que reservaste para visitar nuestras '
          'sucursales.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Contador de reservas reportado por el backend.
class _ContadorReservas extends StatelessWidget {
  const _ContadorReservas({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        total == 1 ? '1 reserva' : '$total reservas',
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

/// Filtros por estado (VENCIDA solo se ve dentro de "Todas").
class _FiltrosReserva extends StatelessWidget {
  const _FiltrosReserva({
    required this.seleccionado,
    required this.onSeleccion,
  });

  final _FiltroReserva seleccionado;
  final ValueChanged<_FiltroReserva> onSeleccion;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _FiltroReserva.values.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final _FiltroReserva filtro = _FiltroReserva.values[index];
          final bool activo = filtro == seleccionado;

          return Material(
            color: activo
                ? AppColors.primary.withValues(alpha: 0.22)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onSeleccion(filtro),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: activo ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  filtro.etiqueta,
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
        },
      ),
    );
  }
}

/// Mensaje cuando el filtro seleccionado no devuelve reservas.
class _SinResultados extends StatelessWidget {
  const _SinResultados();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No tienes reservas en este estado.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

/// Estado de error del listado con opción de reintentar.
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


