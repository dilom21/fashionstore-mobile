import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatters.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../models/historial_compras_model.dart';
import '../services/historial_compras_service.dart';
import '../widgets/historial_estado_badge.dart';
import 'comprobante_venta_page.dart';

/// CU24 – Detalle de una compra del historial del CLIENTE (solo lectura).
///
/// Flujo: HistorialComprasPage -> esta pantalla ->
/// HistorialComprasService.obtenerDetalle -> `GET /ventas/historial/{venta_id}`.
///
/// La pantalla consulta de nuevo el backend (no confía en el listado) porque
/// es el backend quien valida que la venta pertenezca al cliente autenticado.
/// No modifica nada y no genera comprobantes: para eso reutiliza CU23.
class HistorialCompraDetallePage extends StatefulWidget {
  /// Crea la pantalla de detalle de una compra.
  const HistorialCompraDetallePage({
    super.key,
    required this.ventaId,
    this.service,
  });

  /// Venta del historial del cliente (autoridad de negocio: el backend).
  final int ventaId;

  /// Servicio inyectable (mismo patrón que CU19/CU22/CU23).
  final HistorialComprasService? service;

  @override
  State<HistorialCompraDetallePage> createState() =>
      _HistorialCompraDetallePageState();
}

class _HistorialCompraDetallePageState extends State<HistorialCompraDetallePage> {
  late final HistorialComprasService _service;

  bool _cargando = true;
  String? _error;
  int? _statusError;
  HistorialCompraDetalle? _detalle;

  static const String _errorRed =
      'No pudimos cargar el detalle.\n'
      'Verifica tu conexión e inténtalo nuevamente.';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? HistorialComprasService();
    _cargarDetalle();
  }

  /// Obtiene el detalle de la compra (solo lectura).
  Future<void> _cargarDetalle() async {
    setState(() {
      _cargando = true;
      _error = null;
      _statusError = null;
    });

    try {
      final HistorialCompraDetalle detalle = await _service.obtenerDetalle(
        widget.ventaId,
      );
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
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
        _detalle = null;
        _statusError = error.statusCode;
        // Sin status = fallo de red/servidor: mensaje propio de CU24.
        _error = error.statusCode == null ? _errorRed : error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _detalle = null;
        _statusError = null;
        _error = _errorRed;
      });
    }
  }

  /// REINTENTAR solo si el fallo puede resolverse repitiendo la consulta.
  bool get _permiteReintentar {
    final int? status = _statusError;
    if (status == null) return true;
    return status >= 500;
  }

  void _volver() => Navigator.of(context).pop();

  /// Reutiliza CU23 tal cual, solo cuando la compra está COMPLETADA.
  void _verComprobante() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComprobanteVentaPage(ventaId: widget.ventaId),
      ),
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
          'DETALLE DE COMPRA',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SafeArea(top: false, child: _contenido()),
    );
  }

  Widget _contenido() {
    if (_cargando) return const _CargandoDetalle();

    final String? error = _error;
    if (error != null) {
      return _MensajeDetalle(
        icono: Icons.receipt_long_rounded,
        titulo: 'No pudimos mostrar el detalle',
        mensaje: error,
        // REINTENTAR solo si el fallo puede resolverse repitiendo la consulta.
        principal: _permiteReintentar
            ? ('REINTENTAR', Icons.refresh_rounded, _cargarDetalle)
            : null,
        secundaria: ('VOLVER', Icons.arrow_back_rounded, _volver),
      );
    }

    final HistorialCompraDetalle? detalle = _detalle;
    if (detalle == null) return const _CargandoDetalle();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _EncabezadoDetalle(detalle: detalle),
          const SizedBox(height: 20),
          const _TituloSeccion('SUCURSAL'),
          const SizedBox(height: 10),
          _TarjetaDetalle(child: _SucursalDetalle(sucursal: detalle.sucursal)),
          const SizedBox(height: 20),
          const _TituloSeccion('PAGO'),
          const SizedBox(height: 10),
          _TarjetaDetalle(child: _PagoDetalle(pago: detalle.pago)),
          const SizedBox(height: 20),
          _TituloSeccion('PRODUCTOS (${detalle.items.length})'),
          const SizedBox(height: 10),
          if (detalle.items.isEmpty)
            _TarjetaDetalle(
              child: Text(
                'Esta compra no tiene productos registrados.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            for (final HistorialCompraItem item in detalle.items) ...<Widget>[
              _TarjetaDetalle(child: _ProductoDetalle(item: item)),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 8),
          _TarjetaDetalle(
            child: _TotalDetalle(
              total: detalle.totalFormateado,
              unidades: detalle.cantidadTotalUnidades,
            ),
          ),
          const SizedBox(height: 22),
          if (detalle.permiteComprobante) ...<Widget>[
            BotonGradiente(
              label: 'VER COMPROBANTE',
              icon: Icons.receipt_long_rounded,
              onPressed: _verComprobante,
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _volver,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text(
              'VOLVER',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
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
        ],
      ),
    );
  }
}

/// Encabezado del detalle: código visual, estado, fecha y canal.
class _EncabezadoDetalle extends StatelessWidget {
  const _EncabezadoDetalle({required this.detalle});

  final HistorialCompraDetalle detalle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                detalle.codigo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            HistorialEstadoBadge(estado: detalle.estado),
          ],
        ),
        const SizedBox(height: 14),
        _TarjetaDetalle(
          child: Column(
            children: <Widget>[
              _FilaInfo(
                etiqueta: 'Realizada',
                valor: formatearFechaHora(detalle.fechaHora),
              ),
              const SizedBox(height: 10),
              _FilaInfo(etiqueta: 'Canal', valor: detalle.canalEtiqueta),
              const SizedBox(height: 10),
              _FilaInfo(
                etiqueta: 'Unidades',
                valor: '${detalle.cantidadTotalUnidades}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tarjeta base de CU24 (misma identidad que el resto de la app).
class _TarjetaDetalle extends StatelessWidget {
  const _TarjetaDetalle({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// Título de sección en mayúsculas.
class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
      ),
    );
  }
}

/// Fila `etiqueta / valor` del detalle (nunca muestra `null`).
class _FilaInfo extends StatelessWidget {
  const _FilaInfo({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 4,
          child: Text(
            etiqueta,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Text(
            valor,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Sucursal que realizó la venta.
class _SucursalDetalle extends StatelessWidget {
  const _SucursalDetalle({required this.sucursal});

  final HistorialCompraSucursal sucursal;

  @override
  Widget build(BuildContext context) {
    final String? telefono = sucursal.telefono;

    return Column(
      children: <Widget>[
        _FilaInfo(
          etiqueta: 'Nombre',
          valor: _textoO(sucursal.nombre, 'No disponible'),
        ),
        const SizedBox(height: 10),
        _FilaInfo(
          etiqueta: 'Dirección',
          valor: _textoO(sucursal.direccion, 'No disponible'),
        ),
        // El teléfono solo se muestra si el backend lo informa.
        if (telefono != null) ...<Widget>[
          const SizedBox(height: 10),
          _FilaInfo(etiqueta: 'Teléfono', valor: telefono),
        ],
      ],
    );
  }
}

/// Pago más relevante de la venta; `pago` puede no existir.
class _PagoDetalle extends StatelessWidget {
  const _PagoDetalle({required this.pago});

  final HistorialCompraPago? pago;

  @override
  Widget build(BuildContext context) {
    final HistorialCompraPago? datos = pago;
    if (datos == null) {
      return const Text(
        'No hay información de pago disponible.',
        style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textMuted),
      );
    }

    final String? pasarela = datos.pasarela;
    final String? referencia = datos.referenciaTransaccion;

    return Column(
      children: <Widget>[
        _FilaInfo(
          etiqueta: 'Método',
          valor: _textoO(datos.metodo, 'No disponible'),
        ),
        const SizedBox(height: 10),
        _FilaInfo(
          etiqueta: 'Estado',
          valor: _textoO(datos.estado, 'No disponible'),
        ),
        const SizedBox(height: 10),
        _FilaInfo(etiqueta: 'Monto', valor: datos.montoFormateado),
        const SizedBox(height: 10),
        _FilaInfo(
          etiqueta: 'Fecha',
          valor: formatearFechaHora(datos.fechaHora),
        ),
        // Pasarela y referencia solo cuando el backend las entrega.
        if (pasarela != null) ...<Widget>[
          const SizedBox(height: 10),
          _FilaInfo(etiqueta: 'Pasarela', valor: pasarela),
        ],
        if (referencia != null) ...<Widget>[
          const SizedBox(height: 10),
          _FilaInfo(etiqueta: 'Referencia', valor: referencia),
        ],
      ],
    );
  }
}

/// Devuelve `porDefecto` cuando el valor viene vacío (nunca se muestra `null`).
String _textoO(String valor, String porDefecto) =>
    valor.trim().isEmpty ? porDefecto : valor.trim();

/// Línea de producto del detalle. CU24 no devuelve imágenes: no se piden
/// requests extra al catálogo.
class _ProductoDetalle extends StatelessWidget {
  const _ProductoDetalle({required this.item});

  final HistorialCompraItem item;

  @override
  Widget build(BuildContext context) {
    final String variante = item.varianteEtiqueta;
    final String sku = item.sku.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _textoO(item.productoNombre, 'Producto sin nombre'),
          style: const TextStyle(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (variante.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            variante,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
        if (sku.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            'SKU: $sku',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
        const SizedBox(height: 12),
        _FilaInfo(etiqueta: 'Cantidad', valor: '${item.cantidad}'),
        const SizedBox(height: 10),
        _FilaInfo(
          etiqueta: 'Precio unitario',
          valor: item.precioUnitarioFormateado,
        ),
        const SizedBox(height: 10),
        _FilaInfo(etiqueta: 'Subtotal', valor: item.subtotalLineaFormateado),
      ],
    );
  }
}

/// Total de la compra: se muestra el `total` del backend, la autoridad.
class _TotalDetalle extends StatelessWidget {
  const _TotalDetalle({required this.total, required this.unidades});

  final String total;
  final int unidades;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'TOTAL',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$unidades ${unidades == 1 ? 'unidad' : 'unidades'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            total,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Indicador mientras se consulta el detalle.
class _CargandoDetalle extends StatelessWidget {
  const _CargandoDetalle();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              'Cargando el detalle...',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado de error del detalle (nunca muestra excepciones ni JSON crudo).
class _MensajeDetalle extends StatelessWidget {
  const _MensajeDetalle({
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 28),
      child: _TarjetaDetalle(
        padding: const EdgeInsets.all(20),
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
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
