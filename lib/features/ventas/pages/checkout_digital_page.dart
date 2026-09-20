import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../../carrito/models/carrito_model.dart';
import '../../carrito/services/carrito_service.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../../catalogo/widgets/producto_media.dart';
import '../models/venta_digital_model.dart';
import '../payments/stripe_payment_gateway.dart';
import '../services/pago_electronico_service.dart';
import '../services/venta_digital_service.dart';
import 'pago_electronico_page.dart';

/// CU19 – Checkout digital (compra desde el carrito ACTIVO).
///
/// Es READ-ONLY: revalida el carrito con `GET /carritos/{carrito_id}` y solo
/// permite confirmar. Al confirmar envía `POST /ventas/digital` con
/// `canal = MOVIL`; el backend deriva cliente, sucursal, prendas y precios, y
/// convierte el carrito en CONVERTIDO.
///
/// No procesa el pago (eso es CU22): la venta queda PENDIENTE.
class CheckoutDigitalPage extends StatefulWidget {
  const CheckoutDigitalPage({
    super.key,
    required this.carritoId,
    this.carritoService,
    this.ventaService,
    this.pagoService,
    this.stripeGateway,
    this.pagoPollingInterval = const Duration(milliseconds: 1500),
    this.pagoMaxIntentos = 20,
  });

  /// Carrito ACTIVO que se convertirá en venta digital.
  final int carritoId;

  /// Servicio de carrito inyectable (revalidación previa).
  final CarritoService? carritoService;

  /// Servicio de ventas inyectable (facilita pruebas).
  final VentaDigitalService? ventaService;

  /// Servicio de pago electrónico (CU22) inyectable para pruebas.
  final PagoElectronicoService? pagoService;

  /// Gateway Stripe (CU22) inyectable para pruebas sin plugin nativo.
  final StripePaymentGateway? stripeGateway;

  /// Intervalo de polling del pago electrónico (inyectable para pruebas).
  final Duration pagoPollingInterval;

  /// Máximo de consultas de estado del pago electrónico.
  final int pagoMaxIntentos;

  @override
  State<CheckoutDigitalPage> createState() => _CheckoutDigitalPageState();
}

class _CheckoutDigitalPageState extends State<CheckoutDigitalPage> {
  late final CarritoService _carritoService;
  late final VentaDigitalService _ventaService;

  CarritoDetalle? _carrito;
  VentaDigital? _venta;
  bool _cargando = true;
  bool _procesando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _carritoService = widget.carritoService ?? CarritoService();
    _ventaService = widget.ventaService ?? VentaDigitalService();
    _cargarCarrito();
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

  bool get _puedeConfirmar {
    final CarritoDetalle? carrito = _carrito;
    return !_procesando &&
        carrito != null &&
        carrito.estaActivo &&
        carrito.tieneItems &&
        carrito.cantidadTotalUnidades > 0;
  }

  // -------------------------------------------------------------------------
  // Confirmación
  // -------------------------------------------------------------------------

  Future<void> _confirmar() async {
    if (_procesando || !_puedeConfirmar) return;

    final bool confirmado = await _pedirConfirmacion();
    if (!confirmado || !mounted) return;
    // El diálogo pudo tardar: se vuelve a comprobar el bloqueo de doble submit.
    if (_procesando) return;

    setState(() => _procesando = true);
    try {
      final VentaDigital venta = await _ventaService.realizarCompra(
        widget.carritoId,
      );
      if (!mounted) return;
      setState(() {
        _venta = venta;
        _procesando = false;
      });
    } on VentaDigitalException catch (error) {
      if (!mounted) return;
      setState(() => _procesando = false);
      if (error.unauthorized) {
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      _mostrarMensaje(error.message);
      // 409/404: el carrito cambió o ya no existe → revalidar contra el backend.
      if (error.conflicto || error.statusCode == 404) await _cargarCarrito();
    } catch (_) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _mostrarMensaje('No pudimos preparar tu compra. Inténtalo nuevamente.');
    }
  }

  Future<bool> _pedirConfirmacion() async {
    final CarritoDetalle? carrito = _carrito;
    final bool? respuesta = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Confirmar compra',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          carrito == null
              ? '¿Confirmas tu compra?'
              : '¿Confirmas la compra de ${carrito.cantidadTotalUnidades} '
                    '${carrito.cantidadTotalUnidades == 1 ? 'unidad' : 'unidades'} '
                    'por ${carrito.subtotalFormateado}?',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'CONFIRMAR',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    return respuesta ?? false;
  }

  void _volverAlCarrito() {
    if (_procesando) return;
    Navigator.of(context).pop(false);
  }

  /// Vuelve al detalle del carrito devolviendo `true` para que este regrese al
  /// listado (el carrito quedó CONVERTIDO y ya no debe editarse).
  void _volverAlListado() {
    Navigator.of(context).pop(true);
  }

  /// CU22: abre el pago electrónico de la venta PENDIENTE recién preparada.
  ///
  /// No vuelve a llamar `POST /ventas/digital` ni crea otra venta: reutiliza el
  /// `ventaId` de CU19. Si el pago se completa, se propaga `true` para cerrar
  /// el flujo y regresar al listado.
  Future<void> _continuarAlPago() async {
    final VentaDigital? venta = _venta;
    if (venta == null || _procesando) return;

    final bool? pagada = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PagoElectronicoPage(
          ventaId: venta.ventaId,
          total: venta.total,
          service: widget.pagoService,
          gateway: widget.stripeGateway,
          pollingInterval: widget.pagoPollingInterval,
          maxIntentos: widget.pagoMaxIntentos,
        ),
      ),
    );
    if (!mounted) return;
    if (pagada == true) {
      _volverAlListado();
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
    return PopScope<bool>(
      // Tras una compra exitosa, el back del sistema también debe propagar
      // `true` para que el detalle abandone el carrito convertido.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, bool? result) {
        if (didPop) return;
        if (!mounted) return;
        Navigator.of(context).pop(_venta != null);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'CHECKOUT',
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

    final VentaDigital? venta = _venta;
    if (venta != null) {
      return _CompraPreparada(
        venta: venta,
        onContinuarAlPago: _continuarAlPago,
        onVolver: _volverAlListado,
      );
    }

    final CarritoDetalle? carrito = _carrito;
    if (carrito == null || !carrito.tieneItems) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Este carrito ya no tiene prendas para comprar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ),
      );
    }

    // Un carrito CONVERTIDO ya no es ACTIVO: no puede volver a comprarse.
    if (!carrito.estaActivo) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Este carrito ya no está activo: no es posible completar la compra.',
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
            const Text(
              'REVISAR COMPRA',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Revisa tu compra antes de confirmarla. Al confirmar, el carrito '
              'se convertirá en una venta pendiente de pago.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            _ResumenCheckout(carrito: carrito),
            const SizedBox(height: 20),
            const Text(
              'PRENDAS',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...carrito.items.map(
              (CarritoItem item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ItemCheckout(item: item),
              ),
            ),
            const SizedBox(height: 12),
            BotonGradiente(
              label: 'CONFIRMAR COMPRA',
              icon: Icons.lock_outline_rounded,
              isLoading: _procesando,
              onPressed: _puedeConfirmar ? _confirmar : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _procesando ? null : _volverAlCarrito,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'VOLVER AL CARRITO',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resumen READ-ONLY del carrito que se convertirá en venta.
class _ResumenCheckout extends StatelessWidget {
  const _ResumenCheckout({required this.carrito});

  final CarritoDetalle carrito;

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
                'RESUMEN',
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
          _FilaResumen(
            etiqueta: carrito.cantidadLineas == 1 ? 'Prenda' : 'Prendas',
            valor: '${carrito.cantidadLineas}',
          ),
          const SizedBox(height: 10),
          _FilaResumen(
            etiqueta: 'Unidades',
            valor: '${carrito.cantidadTotalUnidades}',
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),
          _FilaResumen(
            etiqueta: 'Total',
            valor: carrito.subtotalFormateado,
            destacado: true,
          ),
        ],
      ),
    );
  }
}

/// Fila READ-ONLY de una prenda del carrito (sin controles de edición).
class _ItemCheckout extends StatelessWidget {
  const _ItemCheckout({required this.item});

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
            height: 78,
            width: 62,
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
                const SizedBox(height: 6),
                Text(
                  '${item.precioUnitarioFormateado} c/u',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'x${item.cantidad}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.subtotalFormateado,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Confirmación de la venta PENDIENTE tras un `POST /ventas/digital` exitoso.
class _CompraPreparada extends StatelessWidget {
  const _CompraPreparada({
    required this.venta,
    required this.onContinuarAlPago,
    required this.onVolver,
  });

  final VentaDigital venta;
  final VoidCallback onContinuarAlPago;
  final VoidCallback onVolver;

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
                    Icons.receipt_long_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Compra preparada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Venta #${venta.ventaId}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                _EstadoPendiente(venta: venta),
                const SizedBox(height: 18),
                Text(
                  'Total: ${venta.totalFormateado}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${venta.cantidadLineas} '
                  '${venta.cantidadLineas == 1 ? 'prenda' : 'prendas'} · '
                  '${venta.cantidadTotalUnidades} '
                  '${venta.cantidadTotalUnidades == 1 ? 'unidad' : 'unidades'} · '
                  '${venta.sucursalEtiqueta}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 26),
                BotonGradiente(
                  label: 'CONTINUAR AL PAGO',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: onContinuarAlPago,
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
                    'VOLVER A MIS CARRITOS',
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

/// Badge del estado real de la venta (PENDIENTE de pago en CU19).
class _EstadoPendiente extends StatelessWidget {
  const _EstadoPendiente({required this.venta});

  final VentaDigital venta;

  static const Color _ambar = Color(0xFFF5B301);

  @override
  Widget build(BuildContext context) {
    final bool pendiente = venta.estaPendiente;
    final Color color = pendiente ? _ambar : AppColors.inactive;
    final String texto = pendiente
        ? 'PENDIENTE DE PAGO'
        : venta.estado.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11.5,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
          color: color,
        ),
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

/// Estado de error del checkout, con opción de reintentar.
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
