import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatters.dart';
import '../../carrito/models/carrito_model.dart';
import '../../carrito/services/carrito_service.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../../catalogo/widgets/producto_media.dart';
import '../models/reserva_model.dart';
import '../services/reserva_service.dart';
import 'reserva_detalle_page.dart';

/// CU16 – Crear reserva a partir de un carrito ACTIVO.
///
/// Revalida el carrito con `GET /carritos/{carrito_id}` (fuente de verdad) y
/// solo envía al backend `carrito_id`, `fecha_atencion` y `observacion`: la
/// sucursal, las prendas y las cantidades las deriva el backend del carrito.
class CrearReservaPage extends StatefulWidget {
  const CrearReservaPage({
    super.key,
    required this.carritoId,
    this.service,
    this.carritoService,
  });

  /// Carrito ACTIVO que se convertirá en reserva.
  final int carritoId;

  /// Servicio de reservas inyectable (facilita pruebas).
  final ReservaService? service;

  /// Servicio de carrito inyectable (revalidación previa).
  final CarritoService? carritoService;

  @override
  State<CrearReservaPage> createState() => _CrearReservaPageState();
}

class _CrearReservaPageState extends State<CrearReservaPage> {
  static const int _maxObservacion = 500;

  late final ReservaService _service;
  late final CarritoService _carritoService;
  final TextEditingController _observacionController = TextEditingController();

  CarritoDetalle? _carrito;
  bool _cargando = true;
  bool _enviando = false;
  String? _error;

  DateTime? _fecha;
  TimeOfDay? _hora;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ReservaService();
    _carritoService = widget.carritoService ?? CarritoService();
    _cargarCarrito();
  }

  @override
  void dispose() {
    _observacionController.dispose();
    super.dispose();
  }

  Future<void> _cargarCarrito() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final CarritoDetalle carrito = await _carritoService.obtenerCarrito(
        widget.carritoId,
      );
      if (!mounted) return;
      setState(() {
        _carrito = carrito;
        _cargando = false;
      });
    } on CarritoException catch (error) {
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
        _error = 'No pudimos cargar el carrito. Inténtalo nuevamente.';
        _cargando = false;
      });
    }
  }

  /// Fecha + hora combinadas en un `DateTime` local.
  DateTime? get _fechaAtencion {
    final DateTime? fecha = _fecha;
    final TimeOfDay? hora = _hora;
    if (fecha == null || hora == null) return null;
    return DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute);
  }

  /// La fecha/hora debe ser futura. El backend sigue siendo la autoridad final.
  bool get _fechaHoraValida {
    final DateTime? atencion = _fechaAtencion;
    if (atencion == null) return false;
    return atencion.isAfter(DateTime.now());
  }

  bool get _puedeConfirmar {
    final CarritoDetalle? carrito = _carrito;
    return !_enviando &&
        carrito != null &&
        carrito.estaActivo &&
        carrito.tieneItems &&
        carrito.cantidadTotalUnidades > 0 &&
        _fechaHoraValida;
  }

  // -------------------------------------------------------------------------
  // Fecha y hora de atención
  // -------------------------------------------------------------------------

  Future<void> _seleccionarFecha() async {
    final DateTime ahora = DateTime.now();
    final DateTime inicial = _fecha ?? ahora.add(const Duration(days: 1));

    final DateTime? elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      // No se permiten fechas anteriores a hoy (el backend valida igualmente).
      firstDate: DateTime(ahora.year, ahora.month, ahora.day),
      lastDate: ahora.add(const Duration(days: 90)),
      builder: _temaPicker,
    );

    if (elegida == null) return;
    setState(() => _fecha = elegida);
  }

  Future<void> _seleccionarHora() async {
    final TimeOfDay? elegida = await showTimePicker(
      context: context,
      initialTime: _hora ?? const TimeOfDay(hour: 10, minute: 0),
      builder: _temaPicker,
    );

    if (elegida == null) return;
    setState(() => _hora = elegida);
  }

  /// Aplica el tema oscuro de VANTER MEN a los pickers nativos.
  Widget _temaPicker(BuildContext context, Widget? child) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        datePickerTheme: const DatePickerThemeData(
          backgroundColor: AppColors.surface,
        ),
        timePickerTheme: const TimePickerThemeData(
          backgroundColor: AppColors.surface,
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  // -------------------------------------------------------------------------
  // Confirmación
  // -------------------------------------------------------------------------

  Future<void> _confirmar() async {
    final DateTime? fechaAtencion = _fechaAtencion;
    if (!_puedeConfirmar || fechaAtencion == null) return;

    setState(() => _enviando = true);
    try {
      final ReservaDetalle reserva = await _service.crearReserva(
        carritoId: widget.carritoId,
        fechaAtencion: fechaAtencion,
        observacion: _observacionController.text,
      );
      if (!mounted) return;
      setState(() => _enviando = false);
      _mostrarMensaje('Reserva creada correctamente.');

      // Se muestra el detalle real de la reserva creada; al volver, esta
      // pantalla se cierra con `true` para que CU15 refresque el carrito.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReservaDetallePage(reservaId: reserva.reservaId),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ReservaException catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      if (error.unauthorized) {
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      _mostrarMensaje(error.message);
      // 409/404: el stock o el carrito cambiaron → revalidar contra el backend.
      if (error.conflicto || error.statusCode == 404) await _cargarCarrito();
    } catch (_) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _mostrarMensaje('No pudimos crear la reserva. Inténtalo nuevamente.');
    }
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
          'RESERVAR PRENDAS',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
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
      return _EstadoError(mensaje: _error!, onReintentar: _cargarCarrito);
    }

    final CarritoDetalle? carrito = _carrito;
    if (carrito == null || !carrito.tieneItems) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Este carrito ya no tiene prendas para reservar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ),
      );
    }

    // Solo un carrito ACTIVO puede convertirse en reserva.
    if (!carrito.estaActivo) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Este carrito ya no está activo: no es posible crear una reserva.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textMuted,
            ),
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
            const _Subtitulo('RESERVAR PRENDAS'),
            const SizedBox(height: 8),
            const Text(
              'Selecciona cuándo deseas visitar la sucursal.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            _InfoCarrito(carrito: carrito),
            const SizedBox(height: 20),
            const _Subtitulo('FECHA DE ATENCIÓN'),
            const SizedBox(height: 10),
            _CampoSeleccion(
              icon: Icons.event_available_rounded,
              texto: _fecha == null
                  ? 'Selecciona una fecha'
                  : formatearFecha(_fecha),
              seleccionado: _fecha != null,
              onTap: _enviando ? null : _seleccionarFecha,
            ),
            const SizedBox(height: 12),
            _CampoSeleccion(
              icon: Icons.schedule_rounded,
              texto: _hora == null ? 'Selecciona una hora' : _textoHora(_hora!),
              seleccionado: _hora != null,
              onTap: _enviando ? null : _seleccionarHora,
            ),
            if (_fecha != null && _hora != null && !_fechaHoraValida) ...[
              const SizedBox(height: 12),
              const Text(
                'La fecha y hora deben ser posteriores al momento actual.',
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
            const SizedBox(height: 20),
            const _Subtitulo('OBSERVACIÓN (OPCIONAL)'),
            const SizedBox(height: 10),
            TextField(
              controller: _observacionController,
              enabled: !_enviando,
              maxLines: 4,
              maxLength: _maxObservacion,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              cursorColor: AppColors.primary,
              decoration: InputDecoration(
                hintText: 'Agrega una observación para la sucursal (opcional)',
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
                contentPadding: const EdgeInsets.all(14),
                border: _bordeInput(AppColors.border),
                enabledBorder: _bordeInput(AppColors.border),
                focusedBorder: _bordeInput(AppColors.primary),
              ),
            ),
            const SizedBox(height: 4),
            _ResumenReserva(carrito: carrito, fecha: _fecha, hora: _hora),
            const SizedBox(height: 22),
            BotonGradiente(
              label: 'CONFIRMAR RESERVA',
              icon: Icons.event_available_rounded,
              isLoading: _enviando,
              onPressed: _puedeConfirmar ? _confirmar : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Título de sección dentro de la pantalla.
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

/// Información READ-ONLY del carrito (sucursal y prendas).
class _InfoCarrito extends StatelessWidget {
  const _InfoCarrito({required this.carrito});

  final CarritoDetalle carrito;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.32),
                  ),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sucursal',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.6,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      carrito.sucursalEtiqueta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _Subtitulo('PRENDAS DEL CARRITO'),
        const SizedBox(height: 12),
        ...carrito.items.map(
          (CarritoItem item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ItemCarritoReadOnly(item: item),
          ),
        ),
      ],
    );
  }
}

/// Fila READ-ONLY de una prenda del carrito (sin controles de edición).
class _ItemCarritoReadOnly extends StatelessWidget {
  const _ItemCarritoReadOnly({required this.item});

  final CarritoItem item;

  @override
  Widget build(BuildContext context) {
    final List<String> detalles = <String>[
      if (item.tallaNombre.trim().isNotEmpty) 'Talla ${item.tallaNombre}',
      if (item.colorNombre.trim().isNotEmpty) item.colorNombre,
      if (item.temporadaNombre.trim().isNotEmpty) item.temporadaNombre,
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 72,
            width: 58,
            child: ProductImage(
              url: item.imagenPrincipal,
              semanticLabel: item.productoNombre,
              borderRadius: BorderRadius.circular(12),
              compactFallback: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productoNombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (detalles.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    detalles.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'x${item.cantidad}',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo táctil de selección (fecha/hora) con el estilo de la app.
class _CampoSeleccion extends StatelessWidget {
  const _CampoSeleccion({
    required this.icon,
    required this.texto,
    required this.seleccionado,
    required this.onTap,
  });

  final IconData icon;
  final String texto;
  final bool seleccionado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: seleccionado ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: seleccionado ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: seleccionado
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: seleccionado
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                  ),
                ),
              ),
              const Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resumen READ-ONLY de la reserva que se va a crear.
///
/// El importe se muestra como "Total referencial": reservar no significa
/// comprar, por lo que la reserva no genera ningún cobro.
class _ResumenReserva extends StatelessWidget {
  const _ResumenReserva({
    required this.carrito,
    required this.fecha,
    required this.hora,
  });

  final CarritoDetalle carrito;
  final DateTime? fecha;
  final TimeOfDay? hora;

  @override
  Widget build(BuildContext context) {
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
              Container(
                height: 34,
                width: 4,
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'RESUMEN DE RESERVA',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _FilaResumen(etiqueta: 'Sucursal', valor: carrito.sucursalEtiqueta),
          const SizedBox(height: 10),
          _FilaResumen(etiqueta: 'Prendas', valor: '${carrito.cantidadLineas}'),
          const SizedBox(height: 10),
          _FilaResumen(
            etiqueta: 'Unidades',
            valor: '${carrito.cantidadTotalUnidades}',
          ),
          const SizedBox(height: 10),
          _FilaResumen(
            etiqueta: 'Fecha',
            valor: fecha == null ? 'Por definir' : formatearFecha(fecha),
          ),
          const SizedBox(height: 10),
          _FilaResumen(
            etiqueta: 'Hora',
            valor: hora == null ? 'Por definir' : _textoHora(hora!),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),
          _FilaResumen(
            etiqueta: 'Total referencial',
            valor: carrito.subtotalFormateado,
            destacado: true,
          ),
          const SizedBox(height: 8),
          const Text(
            'La reserva no genera ningún cobro.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila etiqueta/valor del resumen.
class _FilaResumen extends StatelessWidget {
  const _FilaResumen({
    required this.etiqueta,
    required this.valor,
    this.destacado = false,
  });

  final String etiqueta;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: destacado ? 14 : 13,
            fontWeight: destacado ? FontWeight.w700 : FontWeight.w500,
            color: destacado ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: destacado ? 18 : 13.5,
              fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Hora en formato `HH:mm`.
String _textoHora(TimeOfDay hora) =>
    '${hora.hour.toString().padLeft(2, '0')}:'
    '${hora.minute.toString().padLeft(2, '0')}';

/// Borde redondeado de los campos de texto.
OutlineInputBorder _bordeInput(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(14),
  borderSide: BorderSide(color: color),
);

/// Estado de error con opción de reintentar.
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
