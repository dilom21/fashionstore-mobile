import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../models/pago_electronico_model.dart';
import '../payments/flutter_stripe_payment_gateway.dart';
import '../payments/stripe_config.dart';
import '../payments/stripe_payment_gateway.dart';
import '../services/pago_electronico_service.dart';
import 'comprobante_venta_page.dart';

/// CU22 – Pago electrónico de una venta digital PENDIENTE (Stripe PaymentSheet).
///
/// Flujo:
///   validar configuración Stripe
///   -> POST /pagos/stripe/intencion (crear/reutilizar PaymentIntent)
///   -> initPaymentSheet con el client_secret
///   -> PAGAR AHORA -> presentPaymentSheet()
///   -> webhook backend (payment_intent.succeeded)
///   -> polling GET /pagos/stripe/ventas/{venta_id}/estado
///   -> "Compra completada" SOLO cuando el backend marca APROBADO/venta final
///
/// El SDK móvil NO es la autoridad final: `presentPaymentSheet()` exitoso solo
/// habilita el polling. Nunca se muestran datos sensibles ni se persiste el
/// `client_secret`.
class PagoElectronicoPage extends StatefulWidget {
  const PagoElectronicoPage({
    super.key,
    required this.ventaId,
    this.total,
    this.service,
    this.gateway,
    this.pollingInterval = const Duration(milliseconds: 1500),
    this.maxIntentos = 20,
  });

  /// Venta MOVIL PENDIENTE creada por CU19 (autoridad de negocio).
  final int ventaId;

  /// Total de presentación de CU19. El monto real de cobro proviene del backend.
  final double? total;

  /// Servicio HTTP inyectable (facilita pruebas sin red).
  final PagoElectronicoService? service;

  /// Gateway Stripe inyectable (facilita pruebas sin plugin nativo).
  final StripePaymentGateway? gateway;

  /// Intervalo entre consultas de estado. Inyectable para pruebas.
  final Duration pollingInterval;

  /// Máximo de consultas de estado antes de dar el pago por "en confirmación".
  final int maxIntentos;

  @override
  State<PagoElectronicoPage> createState() => _PagoElectronicoPageState();
}

class _PagoElectronicoPageState extends State<PagoElectronicoPage> {
  late final PagoElectronicoService _service;
  late final StripePaymentGateway _gateway;

  IntencionPago? _intencion;

  /// Carga inicial: validación Stripe + creación de intención + sheet.
  bool _cargando = true;

  /// Error fatal que impide iniciar el pago (con opción de reintentar).
  String? _error;

  /// La intención y el PaymentSheet están listos para presentarse.
  bool _listo = false;

  /// Hay un `presentPaymentSheet()` en curso (bloquea doble tap).
  bool _procesando = false;

  /// Polling contra el backend tras una presentación exitosa.
  bool _confirmando = false;

  /// Estados terminales reportados por el backend.
  bool _exito = false;
  bool _rechazado = false;
  bool _anulado = false;

  /// Compensación de Stripe pendiente (venta CANCELADA + APROBADO).
  bool _reembolsoEnProceso = false;

  /// Reembolso completado (venta CANCELADA + REEMBOLSADO): terminal.
  bool _reembolsado = false;

  /// Estado no reconocido: seguro, nunca habilita un nuevo cobro.
  bool _desconocido = false;

  /// El polling agotó sus intentos sin estado terminal (webhook pendiente).
  bool _timeout = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PagoElectronicoService();
    _gateway = widget.gateway ?? FlutterStripePaymentGateway();
    _iniciar();
  }

  // -------------------------------------------------------------------------
  // Inicio del flujo
  // -------------------------------------------------------------------------

  Future<void> _iniciar() async {
    if (!_gateway.isConfigured) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = StripeConfig.missingKeyMessage;
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
      _listo = false;
      _exito = false;
      _rechazado = false;
      _anulado = false;
      _reembolsoEnProceso = false;
      _reembolsado = false;
      _desconocido = false;
      _timeout = false;
    });

    try {
      await _gateway.initialize();
      final IntencionPago intencion = await _service.crearIntencion(
        widget.ventaId,
      );
      final String? clientSecret = intencion.clientSecret;
      if (clientSecret == null || clientSecret.trim().isEmpty) {
        throw const PagoElectronicoException(
          'No pudimos iniciar el pago. Inténtalo nuevamente.',
        );
      }
      await _gateway.initPaymentSheet(clientSecret: clientSecret);
      if (!mounted) return;
      setState(() {
        _intencion = intencion;
        _cargando = false;
        _listo = true;
      });
    } on PagoElectronicoException catch (error) {
      if (!mounted) return;
      if (error.unauthorized) {
        setState(() => _cargando = false);
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      setState(() {
        _cargando = false;
        _error = error.message;
      });
    } on StripePaymentGatewayException catch (error) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No pudimos iniciar el pago. Inténtalo nuevamente.';
      });
    }
  }

  // -------------------------------------------------------------------------
  // Presentar y confirmar
  // -------------------------------------------------------------------------

  Future<void> _pagar() async {
    if (_procesando || _confirmando || !_listo) return;
    setState(() => _procesando = true);

    try {
      final StripeSheetOutcome outcome = await _gateway.presentPaymentSheet();
      if (!mounted) return;

      if (outcome == StripeSheetOutcome.canceled) {
        // Cancelación del usuario: no es rechazo, no se confirma la venta.
        setState(() => _procesando = false);
        _mostrarMensaje('Pago cancelado. Puedes intentarlo de nuevo.');
        return;
      }

      // Éxito local del SDK: falta la autoridad del webhook backend.
      setState(() => _procesando = false);
      await _esperarConfirmacion();
    } on StripePaymentGatewayException catch (error) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _mostrarMensaje(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _mostrarMensaje('No pudimos completar el pago. Inténtalo nuevamente.');
    }
  }

  /// Consulta el backend hasta obtener un estado terminal o agotar intentos.
  Future<void> _esperarConfirmacion() async {
    setState(() {
      _confirmando = true;
      _exito = false;
      _rechazado = false;
      _anulado = false;
      _reembolsoEnProceso = false;
      _reembolsado = false;
      _desconocido = false;
      _timeout = false;
    });

    bool aprobado = false;
    bool rechazado = false;
    bool anulado = false;
    bool reembolsoEnProceso = false;
    bool reembolsado = false;
    bool desconocido = false;

    for (int intento = 1; intento <= widget.maxIntentos; intento++) {
      try {
        final EstadoPagoVenta estado = await _service.consultarEstado(
          widget.ventaId,
        );
        if (!mounted) return;

        final EstadoVisualPago visual = estado.estadoVisual;
        if (visual == EstadoVisualPago.exito) {
          aprobado = true;
        } else if (visual == EstadoVisualPago.rechazado) {
          rechazado = true;
        } else if (visual == EstadoVisualPago.anulado) {
          anulado = true;
        } else if (visual == EstadoVisualPago.reembolsoEnProceso) {
          reembolsoEnProceso = true;
        } else if (visual == EstadoVisualPago.reembolsado) {
          reembolsado = true;
        } else if (visual == EstadoVisualPago.desconocido) {
          desconocido = true;
        }

        // `enConfirmacion` sigue el polling; cualquier otro estado es terminal.
        if (visual != EstadoVisualPago.enConfirmacion) {
          break;
        }
      } on PagoElectronicoException catch (error) {
        if (!mounted) return;
        if (error.unauthorized) {
          setState(() => _confirmando = false);
          await SessionExpired.manejar(context, mensaje: error.message);
          return;
        }
        // Error transitorio: se sigue intentando hasta agotar el máximo.
      } catch (_) {
        // Error transitorio: se sigue intentando hasta agotar el máximo.
      }

      if (intento < widget.maxIntentos) {
        await Future<void>.delayed(widget.pollingInterval);
        if (!mounted) return;
      }
    }

    if (!mounted) return;
    setState(() {
      _confirmando = false;
      _exito = aprobado;
      _rechazado = rechazado;
      _anulado = anulado;
      _reembolsoEnProceso = reembolsoEnProceso;
      _reembolsado = reembolsado;
      _desconocido = desconocido;
      _timeout =
          !aprobado &&
          !rechazado &&
          !anulado &&
          !reembolsoEnProceso &&
          !reembolsado &&
          !desconocido;
    });
  }

  /// Reintento tras RECHAZADO/ANULADO: el backend decide si reutiliza el
  /// PaymentIntent o crea uno nuevo. Nunca se reutiliza un client_secret viejo.
  Future<void> _reintentar() async {
    if (_procesando || _confirmando || _cargando) return;
    // Una venta CANCELADA (compensación/reembolso) nunca vuelve a cobrarse.
    if (_reembolsoEnProceso || _reembolsado || _desconocido) return;
    await _iniciar();
  }

  /// Reconsulta el estado sin volver a cobrar (timeout del webhook).
  Future<void> _reconsultar() async {
    if (_procesando || _confirmando) return;
    await _esperarConfirmacion();
  }

  void _volverAlInicio() {
    if (_procesando || _confirmando) return;
    Navigator.of(context).pop(_exito);
  }

  /// CU23: abre el comprobante de la venta ya confirmada (solo lectura).
  ///
  /// NO cambia `_exito` ni el resultado del pago: al volver, esta pantalla sigue
  /// mostrando "Compra completada" y VOLVER AL INICIO devuelve `true` al
  /// checkout, que abandona el carrito CONVERTIDO.
  Future<void> _verComprobante() async {
    if (_procesando || _confirmando) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComprobanteVentaPage(ventaId: widget.ventaId),
      ),
    );
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
      );
  }

  String get _montoTexto {
    final IntencionPago? intencion = _intencion;
    if (intencion != null) return intencion.montoFormateado;
    final double? total = widget.total;
    if (total != null) return formatearMontoPago(total);
    return '';
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      // No se abandona el flujo mientras se presenta o se confirma el pago.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, bool? result) {
        if (didPop) return;
        if (_procesando || _confirmando) return;
        if (!mounted) return;
        Navigator.of(context).pop(_exito);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'PAGO ELECTRÓNICO',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
        ),
        body: SafeArea(top: false, child: _buildContenido()),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const _Cargando(mensaje: 'Preparando el pago...');
    }
    if (_confirmando) {
      return const _Cargando(
        mensaje: 'Confirmando pago...\nEsperando la confirmación del banco.',
      );
    }
    if (_exito) {
      return _EstadoExito(
        ventaId: widget.ventaId,
        montoTexto: _montoTexto,
        onVerComprobante: _verComprobante,
        onVolver: _volverAlInicio,
      );
    }
    if (_reembolsado) {
      return _EstadoReembolsado(
        ventaId: widget.ventaId,
        onVolver: _volverAlInicio,
      );
    }
    if (_reembolsoEnProceso) {
      return _EstadoReembolsoEnProceso(
        ventaId: widget.ventaId,
        onReconsultar: _reconsultar,
        onVolver: _volverAlInicio,
      );
    }
    if (_desconocido) {
      return _EstadoDesconocido(
        onReconsultar: _reconsultar,
        onVolver: _volverAlInicio,
      );
    }
    if (_rechazado) {
      return _EstadoFallido(
        icono: Icons.credit_card_off_rounded,
        titulo: 'Pago rechazado',
        mensaje: 'Tu venta sigue pendiente.',
        color: AppColors.error,
        accion: 'REINTENTAR PAGO',
        onAccion: _reintentar,
        onVolver: _volverAlInicio,
      );
    }
    if (_anulado) {
      return _EstadoFallido(
        icono: Icons.cancel_outlined,
        titulo: 'Pago anulado',
        mensaje: 'Tu venta sigue pendiente.',
        color: AppColors.textMuted,
        accion: 'REINTENTAR PAGO',
        onAccion: _reintentar,
        onVolver: _volverAlInicio,
      );
    }
    if (_timeout) {
      return _EstadoPendiente(
        onReconsultar: _reconsultar,
        onVolver: _volverAlInicio,
      );
    }
    final String? error = _error;
    if (error != null) {
      return _EstadoError(mensaje: error, onReintentar: _iniciar);
    }
    return _buildListo();
  }

  Widget _buildListo() {
    final IntencionPago? intencion = _intencion;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  blurRadius: 30,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 64,
                  width: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Pago seguro',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Venta #${widget.ventaId}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                if (_montoTexto.isNotEmpty)
                  Text(
                    _montoTexto,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                const SizedBox(height: 10),
                const Text(
                  'Completa el pago con tarjeta en la hoja segura de Stripe. '
                  'La compra se confirma cuando el banco y el sistema lo '
                  'verifican.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                if (intencion != null && intencion.monedaNormalizada.isNotEmpty)
                  Text(
                    'Moneda: ${intencion.monedaNormalizada}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                const SizedBox(height: 26),
                BotonGradiente(
                  label: 'PAGAR AHORA',
                  icon: Icons.lock_outline_rounded,
                  isLoading: _procesando,
                  onPressed: _procesando ? null : _pagar,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _procesando ? null : _volverAlInicio,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'VOLVER',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
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

/// Indicador de carga reutilizable.
class _Cargando extends StatelessWidget {
  const _Cargando({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            height: 28,
            width: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta base de estado terminal (éxito, rechazo, anulación, timeout).
class _TarjetaEstado extends StatelessWidget {
  const _TarjetaEstado({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.mensaje,
    required this.acciones,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final Widget mensaje;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.12),
                  blurRadius: 30,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 64,
                  width: 64,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Icon(icono, color: color, size: 30),
                ),
                const SizedBox(height: 20),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                mensaje,
                const SizedBox(height: 26),
                ...acciones,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Éxito real: el backend confirmó el pago/venta.
class _EstadoExito extends StatelessWidget {
  const _EstadoExito({
    required this.ventaId,
    required this.montoTexto,
    required this.onVerComprobante,
    required this.onVolver,
  });

  final int ventaId;
  final String montoTexto;

  /// CU23: acción principal, abre el comprobante de la venta confirmada.
  final VoidCallback onVerComprobante;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return _TarjetaEstado(
      icono: Icons.check_circle_rounded,
      color: const Color(0xFF22C55E),
      titulo: 'Compra completada',
      mensaje: Column(
        children: [
          const Text(
            'Pago aprobado',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Venta #$ventaId',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          if (montoTexto.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Monto $montoTexto',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
      acciones: [
        BotonGradiente(
          label: 'VER COMPROBANTE',
          icon: Icons.receipt_long_rounded,
          onPressed: onVerComprobante,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onVolver,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'VOLVER AL INICIO',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.4),
          ),
        ),
      ],
    );
  }
}

/// Fallo terminal: rechazo o anulación, con reintento.
class _EstadoFallido extends StatelessWidget {
  const _EstadoFallido({
    required this.icono,
    required this.titulo,
    required this.mensaje,
    required this.color,
    required this.accion,
    required this.onAccion,
    required this.onVolver,
  });

  final IconData icono;
  final String titulo;
  final String mensaje;
  final Color color;
  final String accion;
  final VoidCallback onAccion;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return _TarjetaEstado(
      icono: icono,
      color: color,
      titulo: titulo,
      mensaje: Text(
        mensaje,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: AppColors.textMuted,
        ),
      ),
      acciones: [
        BotonGradiente(
          label: accion,
          icon: Icons.refresh_rounded,
          onPressed: onAccion,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onVolver,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'VOLVER',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.4),
          ),
        ),
      ],
    );
  }
}

/// Timeout del webhook: el pago sigue en confirmación (no es rechazo).
class _EstadoPendiente extends StatelessWidget {
  const _EstadoPendiente({required this.onReconsultar, required this.onVolver});

  final VoidCallback onReconsultar;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return _TarjetaEstado(
      icono: Icons.hourglass_bottom_rounded,
      color: const Color(0xFFF5B301),
      titulo: 'Pago en confirmación',
      mensaje: const Text(
        'Tu pago sigue en confirmación. No se te volverá a cobrar.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: AppColors.textMuted,
        ),
      ),
      acciones: [
        BotonGradiente(
          label: 'RECONSULTAR ESTADO',
          icon: Icons.refresh_rounded,
          onPressed: onReconsultar,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onVolver,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'VOLVER',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.4),
          ),
        ),
      ],
    );
  }
}

/// Compensación pendiente: venta CANCELADA con el reembolso procesándose.
class _EstadoReembolsoEnProceso extends StatelessWidget {
  const _EstadoReembolsoEnProceso({
    required this.ventaId,
    required this.onReconsultar,
    required this.onVolver,
  });

  final int ventaId;
  final VoidCallback onReconsultar;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return _TarjetaEstado(
      icono: Icons.currency_exchange_rounded,
      color: const Color(0xFFF5B301),
      titulo: 'Reembolso en proceso',
      mensaje: Column(
        children: [
          const Text(
            'La compra no pudo completarse.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Estamos procesando la devolución de tu pago.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No se te volverá a cobrar esta venta.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Venta #$ventaId',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
        ],
      ),
      acciones: [
        BotonGradiente(
          label: 'RECONSULTAR ESTADO',
          icon: Icons.refresh_rounded,
          onPressed: onReconsultar,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onVolver,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'VOLVER',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.4),
          ),
        ),
      ],
    );
  }
}

/// Reembolso completado: estado terminal, sin CTA de pago.
class _EstadoReembolsado extends StatelessWidget {
  const _EstadoReembolsado({required this.ventaId, required this.onVolver});

  final int ventaId;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return _TarjetaEstado(
      icono: Icons.check_circle_rounded,
      color: const Color(0xFF22C55E),
      titulo: 'Pago reembolsado',
      mensaje: Column(
        children: [
          const Text(
            'La compra no pudo completarse porque el producto ya no estaba '
            'disponible.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'El pago fue devuelto correctamente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No se te volverá a cobrar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Venta #$ventaId',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
        ],
      ),
      acciones: [
        BotonGradiente(
          label: 'VOLVER AL INICIO',
          icon: Icons.home_rounded,
          onPressed: onVolver,
        ),
      ],
    );
  }
}

/// Estado no reconocido: seguro, sin CTA de pago, con reconsulta.
class _EstadoDesconocido extends StatelessWidget {
  const _EstadoDesconocido({
    required this.onReconsultar,
    required this.onVolver,
  });

  final VoidCallback onReconsultar;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return _TarjetaEstado(
      icono: Icons.help_outline_rounded,
      color: AppColors.textMuted,
      titulo: 'No pudimos confirmar el estado',
      mensaje: const Text(
        'Puedes reconsultar el estado de tu pago. No se te volverá a cobrar.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: AppColors.textMuted,
        ),
      ),
      acciones: [
        BotonGradiente(
          label: 'RECONSULTAR ESTADO',
          icon: Icons.refresh_rounded,
          onPressed: onReconsultar,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onVolver,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'VOLVER',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.4),
          ),
        ),
      ],
    );
  }
}

/// Error de configuración o de inicio, con opción de reintentar.
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
