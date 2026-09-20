import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatters.dart';
import '../models/reserva_model.dart';
import '../services/reserva_service.dart';
import '../widgets/reserva_estado_badge.dart';
import '../widgets/reserva_item_card.dart';
import 'reservas_page.dart';

/// CU16 – Detalle de una reserva (`GET /reservas/{reserva_id}`).
///
/// El contenido es READ-ONLY: no se editan prendas, cantidades ni fechas. La
/// única acción posible es cancelar, y solo si el estado lo permite.
class ReservaDetallePage extends StatefulWidget {
  const ReservaDetallePage({
    super.key,
    required this.reservaId,
    this.mostrarMisReservas = true,
    this.service,
  });

  /// Identificador real de la reserva.
  final int reservaId;

  /// Muestra el acceso "VER MIS RESERVAS" (por ejemplo tras crearla).
  final bool mostrarMisReservas;

  /// Servicio inyectable (facilita pruebas).
  final ReservaService? service;

  @override
  State<ReservaDetallePage> createState() => _ReservaDetallePageState();
}

class _ReservaDetallePageState extends State<ReservaDetallePage> {
  late final ReservaService _service;

  ReservaDetalle? _reserva;
  bool _cargando = true;
  bool _cancelando = false;
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
      final ReservaDetalle reserva = await _service.obtenerReserva(
        widget.reservaId,
      );
      if (!mounted) return;
      setState(() {
        _reserva = reserva;
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
        _error = 'No pudimos cargar la reserva. Inténtalo nuevamente.';
        _cargando = false;
      });
    }
  }

  // -------------------------------------------------------------------------
  // Cancelación
  // -------------------------------------------------------------------------

  Future<void> _cancelar() async {
    if (_reserva == null || _cancelando) return;

    final String? motivo = await _pedirMotivo();
    if (motivo == null || !mounted) {
      return; // `null`: el cliente cerró el modal.
    }

    setState(() => _cancelando = true);
    try {
      final ReservaDetalle actualizada = await _service.cancelarReserva(
        reservaId: widget.reservaId,
        observacion: motivo,
      );
      if (!mounted) return;
      setState(() {
        _reserva = actualizada;
        _cancelando = false;
      });
      _mostrarMensaje('Reserva cancelada correctamente.');
    } on ReservaException catch (error) {
      if (!mounted) return;
      setState(() => _cancelando = false);
      if (error.unauthorized) {
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      _mostrarMensaje(error.message);
      // Estado inesperado o reserva inexistente: el backend es la autoridad.
      if (error.conflicto || error.statusCode == 404) await _cargar();
    } catch (_) {
      if (!mounted) return;
      setState(() => _cancelando = false);
      _mostrarMensaje('No pudimos cancelar la reserva. Inténtalo nuevamente.');
    }
  }

  /// Confirma la cancelación y devuelve el motivo opcional (máximo 500).
  ///
  /// Devuelve `null` si el cliente cierra el modal sin confirmar.
  ///
  /// El modal SOLO confirma y se cierra: no hace HTTP, ni `setState`, ni
  /// navegación. El texto se captura con `onChanged` para no crear ningún
  /// `TextEditingController` que hubiera que liberar mientras la ruta del
  /// modal todavía se está desmontando (eso dejaba elementos dependientes
  /// registrados en un `InheritedElement` y rompía con `_dependents.isEmpty`).
  Future<String?> _pedirMotivo() async {
    String motivo = '';

    final bool? confirmado = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          '¿Cancelar esta reserva?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Las prendas reservadas serán liberadas y esta acción no podrá '
                'revertirse.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                maxLines: 3,
                maxLength: 500,
                onChanged: (String valor) => motivo = valor,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                cursorColor: AppColors.primary,
                decoration: InputDecoration(
                  hintText: 'Motivo de cancelación (opcional)',
                  hintStyle: const TextStyle(
                    color: AppColors.inactive,
                    fontSize: 13.5,
                  ),
                  counterStyle: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  border: _bordeInput(AppColors.border),
                  enabledBorder: _bordeInput(AppColors.border),
                  focusedBorder: _bordeInput(AppColors.primary),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Volver',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Cancelar reserva',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmado != true) return null;
    return motivo;
  }

  void _verMisReservas() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ReservasPage()));
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
    final ReservaDetalle? reserva = _reserva;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'DETALLE DE RESERVA',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        actions: [
          if (reserva != null)
            IconButton(
              onPressed: _cancelando ? null : _cargar,
              tooltip: 'Actualizar',
              icon: const Icon(
                Icons.refresh_rounded,
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

    final ReservaDetalle? reserva = _reserva;
    if (reserva == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'No encontramos esta reserva.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
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
            _InfoReserva(reserva: reserva),
            const SizedBox(height: 22),
            const _Subtitulo('PRENDAS RESERVADAS'),
            const SizedBox(height: 12),
            if (!reserva.tieneItems)
              const _SinPrendas()
            else
              ...reserva.items.map(
                (ReservaItem item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ReservaItemCard(
                    item: item,
                    cantidadEtiqueta: 'Reservadas',
                  ),
                ),
              ),
            const SizedBox(height: 10),
            if (widget.mostrarMisReservas) ...[
              OutlinedButton.icon(
                onPressed: _verMisReservas,
                icon: const Icon(Icons.list_alt_rounded, size: 18),
                label: const Text(
                  'VER MIS RESERVAS',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Solo PENDIENTE y CONFIRMADA pueden cancelarse (CU16).
            if (reserva.esCancelable)
              OutlinedButton.icon(
                onPressed: _cancelando ? null : _cancelar,
                icon: _cancelando
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.error,
                          ),
                        ),
                      )
                    : const Icon(Icons.cancel_outlined, size: 18),
                label: const Text(
                  'CANCELAR RESERVA',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              )
            else
              _AvisoNoEditable(estado: reserva.estadoReserva),
          ],
        ),
      ),
    );
  }
}

/// Información principal de la reserva (read-only).
class _InfoReserva extends StatelessWidget {
  const _InfoReserva({required this.reserva});

  final ReservaDetalle reserva;

  @override
  Widget build(BuildContext context) {
    final String observacion = reserva.observacion?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 26,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reserva.codigo,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              ReservaEstadoBadge(estado: reserva.estadoReserva),
            ],
          ),
          const SizedBox(height: 18),
          _FilaInfo(
            icon: Icons.storefront_rounded,
            etiqueta: 'Sucursal',
            valor: reserva.sucursalEtiqueta,
          ),
          const SizedBox(height: 12),
          _FilaInfo(
            icon: Icons.event_available_rounded,
            etiqueta: 'Fecha de reserva',
            valor: formatearFechaHora(reserva.fechaReserva),
          ),
          const SizedBox(height: 12),
          _FilaInfo(
            icon: Icons.schedule_rounded,
            etiqueta: 'Fecha de atención',
            valor: formatearFechaHora(reserva.fechaAtencion),
          ),
          const SizedBox(height: 12),
          _FilaInfo(
            icon: Icons.inventory_2_outlined,
            etiqueta: 'Unidades reservadas',
            valor: '${reserva.cantidadTotalUnidades}',
          ),
          if (observacion.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 14),
            const _Subtitulo('OBSERVACIÓN'),
            const SizedBox(height: 8),
            Text(
              observacion,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fila etiqueta/valor con icono.
class _FilaInfo extends StatelessWidget {
  const _FilaInfo({
    required this.icon,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icon;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiqueta,
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Título de sección dentro del detalle.
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

/// Mensaje cuando la reserva no tiene prendas registradas (caso borde).
class _SinPrendas extends StatelessWidget {
  const _SinPrendas();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 28, color: AppColors.inactive),
          SizedBox(height: 12),
          Text(
            'Esta reserva no tiene prendas registradas.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Aviso cuando la reserva está en un estado final (no editable).
class _AvisoNoEditable extends StatelessWidget {
  const _AvisoNoEditable({required this.estado});

  final EstadoReserva estado;

  @override
  Widget build(BuildContext context) {
    final String mensaje = switch (estado) {
      EstadoReserva.atendida =>
        'Esta reserva ya fue atendida y no admite cambios.',
      EstadoReserva.cancelada =>
        'Esta reserva está cancelada y no admite cambios.',
      EstadoReserva.vencida => 'Esta reserva venció y no admite cambios.',
      EstadoReserva.pendiente ||
      EstadoReserva.confirmada ||
      EstadoReserva.desconocido => 'Esta reserva no admite cambios.',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
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

/// Estado de error del detalle con opción de reintentar.
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

/// Borde redondeado de los campos de texto de la feature.
OutlineInputBorder _bordeInput(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(14),
  borderSide: BorderSide(color: color),
);
