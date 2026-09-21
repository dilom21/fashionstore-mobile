import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatters.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../models/comprobante_venta_model.dart';
import '../services/comprobante_venta_service.dart';
import '../utils/comprobante_venta_pdf.dart';

/// CU23 – Comprobante de venta del CLIENTE (solo lectura).
///
/// Flujo: Page -> ComprobanteVentaService -> GET /ventas/{venta_id}/comprobante.
/// La pantalla solo obtiene, muestra, genera el PDF, lo comparte/imprime y
/// permite volver: no crea otra venta, no registra otro pago y no vuelve a
/// llamar a Stripe.
class ComprobanteVentaPage extends StatefulWidget {
  const ComprobanteVentaPage({super.key, required this.ventaId, this.service});

  /// Venta COMPLETADA con pago APROBADO (autoridad de negocio: el backend).
  final int ventaId;

  /// Servicio inyectable (mismo patrón que CU19/CU22).
  final ComprobanteVentaService? service;

  @override
  State<ComprobanteVentaPage> createState() => _ComprobanteVentaPageState();
}

class _ComprobanteVentaPageState extends State<ComprobanteVentaPage> {
  late final ComprobanteVentaService _service;

  bool _cargando = true;
  String? _error;
  int? _statusError;
  ComprobanteVenta? _comprobante;

  /// Evita doble toque mientras se genera/comparte/imprime el PDF.
  bool _generandoPdf = false;
  Uint8List? _pdfBytes;

  static const String _errorRed =
      'No pudimos cargar el comprobante.\n'
      'Verifica tu conexión e inténtalo nuevamente.';
  static const String _errorPdf =
      'No pudimos generar el PDF. Inténtalo nuevamente.';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ComprobanteVentaService();
    _cargarComprobante();
  }

  /// Carga el comprobante (solo lectura). No toca el estado de CU22.
  Future<void> _cargarComprobante() async {
    setState(() {
      _cargando = true;
      _error = null;
      _statusError = null;
    });

    try {
      final ComprobanteVenta comprobante = await _service.obtenerComprobante(
        widget.ventaId,
      );
      if (!mounted) return;
      setState(() {
        _comprobante = comprobante;
        _pdfBytes = null; // se regenera con los datos recién obtenidos
        _cargando = false;
      });
    } on ComprobanteVentaException catch (error) {
      if (!mounted) return;
      if (error.unauthorized) {
        setState(() => _cargando = false);
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      setState(() {
        _cargando = false;
        _comprobante = null;
        _statusError = error.statusCode;
        // Sin status = fallo de red/servidor: mensaje propio de CU23.
        _error = error.statusCode == null ? _errorRed : error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _comprobante = null;
        _statusError = null;
        _error = _errorRed;
      });
    }
  }

  /// Reintentar solo cuando puede resolverse repitiendo: red/servidor (sin
  /// status), 409 (el webhook puede terminar de confirmar) o un 5xx.
  bool get _permiteReintentar {
    final int? status = _statusError;
    if (status == null) return true;
    return status == 409 || status >= 500;
  }

  /// Genera (una sola vez) el PDF vectorial del comprobante.
  Future<Uint8List?> _obtenerPdf() async {
    final ComprobanteVenta? comprobante = _comprobante;
    if (comprobante == null) return null;

    final Uint8List? cacheado = _pdfBytes;
    if (cacheado != null) return cacheado;

    setState(() => _generandoPdf = true);
    try {
      final Uint8List bytes = await generarPdfComprobante(comprobante);
      if (!mounted) return bytes;
      setState(() {
        _pdfBytes = bytes;
        _generandoPdf = false;
      });
      return bytes;
    } catch (_) {
      if (!mounted) return null;
      setState(() => _generandoPdf = false);
      _mostrarMensaje(_errorPdf);
      return null;
    }
  }

  /// DESCARGAR PDF: abre el selector nativo para guardar/compartir el archivo.
  Future<void> _descargarPdf() async {
    if (_generandoPdf) return;
    final Uint8List? bytes = await _obtenerPdf();
    if (bytes == null || !mounted) return;
    try {
      await Printing.sharePdf(
        bytes: bytes,
        filename: nombreArchivoComprobante(widget.ventaId),
      );
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje(_errorPdf);
    }
  }

  /// IMPRIMIR: manda al sistema de impresión solo el comprobante.
  Future<void> _imprimir() async {
    if (_generandoPdf) return;
    final Uint8List? bytes = await _obtenerPdf();
    if (bytes == null || !mounted) return;
    try {
      await Printing.layoutPdf(
        name: nombreArchivoComprobante(widget.ventaId),
        onLayout: (format) async => bytes,
      );
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje(_errorPdf);
    }
  }

  void _volver() => Navigator.of(context).pop();

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
          'COMPROBANTE',
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
      return const _CargandoComprobante();
    }

    final String? error = _error;
    if (error != null) {
      return _ErrorComprobante(
        mensaje: error,
        // REINTENTAR solo si el fallo puede resolverse repitiendo la consulta.
        onReintentar: _permiteReintentar ? _cargarComprobante : null,
        onVolver: _volver,
      );
    }

    final ComprobanteVenta? comprobante = _comprobante;
    if (comprobante == null) {
      return const _CargandoComprobante();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _EncabezadoComprobante(comprobante: comprobante),
          const SizedBox(height: 20),
          const _TituloSeccion('DATOS GENERALES'),
          const SizedBox(height: 10),
          _CardDatosGenerales(comprobante: comprobante),
          const SizedBox(height: 22),
          _HojaComprobante(comprobante: comprobante),
          const SizedBox(height: 22),
          _AccionesComprobante(
            generandoPdf: _generandoPdf,
            onDescargar: _descargarPdf,
            onImprimir: _imprimir,
            onVolver: _volver,
          ),
        ],
      ),
    );
  }
}

/// Devuelve `porDefecto` cuando el valor viene vacío (nunca se muestra `null`).
String _textoO(String valor, String porDefecto) =>
    valor.trim().isEmpty ? porDefecto : valor.trim();

/// Tarjeta base de la pantalla (misma identidad que el resto de la app).
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.child, this.padding});

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

/// Encabezado: título, código visual, estado y confirmación.
class _EncabezadoComprobante extends StatelessWidget {
  const _EncabezadoComprobante({required this.comprobante});

  final ComprobanteVenta comprobante;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'COMPROBANTE DE VENTA',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Text(
              comprobante.codigo,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.55),
                ),
              ),
              child: Text(
                _textoO(comprobante.estadoVenta, 'COMPLETADA'),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: Color(0xFF22C55E),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Venta registrada y pagada correctamente.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Título de sección con el estilo de la app.
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

/// Fila etiqueta/valor de una tarjeta.
class _FilaDato extends StatelessWidget {
  const _FilaDato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              etiqueta,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resumen de datos generales de la venta.
class _CardDatosGenerales extends StatelessWidget {
  const _CardDatosGenerales({required this.comprobante});

  final ComprobanteVenta comprobante;

  @override
  Widget build(BuildContext context) {
    final ComprobanteCliente? cliente = comprobante.cliente;
    return _Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _FilaDato(
            etiqueta: 'Fecha',
            valor: formatearFechaHora(comprobante.fechaHora),
          ),
          _FilaDato(
            etiqueta: 'Canal',
            valor: _textoO(comprobante.canal, 'No disponible'),
          ),
          _FilaDato(
            etiqueta: 'Sucursal',
            valor: _textoO(comprobante.sucursal.nombre, 'No disponible'),
          ),
          _FilaDato(
            etiqueta: 'Cliente',
            valor: cliente == null ? 'Cliente general' : cliente.nombreCompleto,
          ),
        ],
      ),
    );
  }
}

/// Encabezado de la hoja (marca + título del documento).
class _MarcaComprobante extends StatelessWidget {
  const _MarcaComprobante();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        Text(
          'VANTER MEN',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'COMPROBANTE DE VENTA',
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.4,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Encabezado de sección de la hoja.
const TextStyle _estiloRotulo = TextStyle(
  fontSize: 11,
  letterSpacing: 1.6,
  fontWeight: FontWeight.w700,
  color: AppColors.textMuted,
);

/// Línea `etiqueta: valor` de la hoja (valor alineado a la derecha).
class _DatoLinea extends StatelessWidget {
  const _DatoLinea(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$etiqueta: ',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Separador entre secciones de la hoja.
class _SeparadorComprobante extends StatelessWidget {
  const _SeparadorComprobante();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Divider(height: 1, thickness: 1, color: AppColors.border),
    );
  }
}

/// Una línea de producto del comprobante (vertical: se adapta a pantallas
/// pequeñas sin tablas horizontales gigantes).
class _ItemProducto extends StatelessWidget {
  const _ItemProducto({required this.item});

  final ComprobanteVentaItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.productoNombre,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (item.varianteTexto.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              item.varianteTexto,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Cantidad: ${item.cantidad}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          _DatoLinea('Precio unitario', item.precioUnitarioFormateado),
          _DatoLinea('Subtotal', item.subtotalFormateado),
        ],
      ),
    );
  }
}

/// Hoja del comprobante: mismo contenido que el PDF generado.
class _HojaComprobante extends StatelessWidget {
  const _HojaComprobante({required this.comprobante});

  final ComprobanteVenta comprobante;

  @override
  Widget build(BuildContext context) {
    final ComprobanteCliente? cliente = comprobante.cliente;
    final ComprobanteEmpleado? empleado = comprobante.empleado;
    final ComprobanteSucursal sucursal = comprobante.sucursal;
    final ComprobantePago pago = comprobante.pago;

    return _Tarjeta(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _MarcaComprobante(),
          const SizedBox(height: 14),
          _DatoLinea('Venta', comprobante.codigo),
          _DatoLinea('Fecha', formatearFechaHora(comprobante.fechaHora)),
          _DatoLinea('Canal', _textoO(comprobante.canal, 'No disponible')),
          if (sucursal.nombre.trim().isNotEmpty)
            _DatoLinea('Sucursal', sucursal.nombre),
          if (sucursal.direccion.trim().isNotEmpty)
            _DatoLinea('Dirección', sucursal.direccion),
          if ((sucursal.telefono ?? '').trim().isNotEmpty)
            _DatoLinea('Teléfono', sucursal.telefono!),
          _DatoLinea(
            'Cliente',
            cliente == null ? 'Cliente general' : cliente.nombreCompleto,
          ),
          if ((cliente?.ci ?? '').trim().isNotEmpty)
            _DatoLinea('CI', cliente!.ci!),
          if ((cliente?.telefono ?? '').trim().isNotEmpty)
            _DatoLinea('Teléfono', cliente!.telefono!),
          // En compras MOVIL el empleado es `null`: la fila no se muestra.
          if (empleado != null)
            _DatoLinea('Registrado por', empleado.nombreCompleto),
          const _SeparadorComprobante(),
          const Text('PRODUCTOS', style: _estiloRotulo),
          const SizedBox(height: 10),
          for (final ComprobanteVentaItem item in comprobante.items)
            _ItemProducto(item: item),
          const _SeparadorComprobante(),
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'TOTAL',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                comprobante.totalFormateado,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DatoLinea('Método', _textoO(pago.metodo, 'No disponible')),
          _DatoLinea('Estado', _textoO(pago.estado, 'No disponible')),
          if ((pago.pasarela ?? '').trim().isNotEmpty)
            _DatoLinea('Pasarela', pago.pasarela!),
          if ((pago.referenciaTransaccion ?? '').trim().isNotEmpty)
            _DatoLinea('Referencia', pago.referenciaTransaccion!),
          _DatoLinea('Unidades', '${comprobante.cantidadTotalUnidades}'),
          const SizedBox(height: 12),
          const Text(
            'Gracias por tu compra.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'VANTER MEN - Moda que te define',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Acciones: DESCARGAR PDF, IMPRIMIR y VOLVER.
class _AccionesComprobante extends StatelessWidget {
  const _AccionesComprobante({
    required this.generandoPdf,
    required this.onDescargar,
    required this.onImprimir,
    required this.onVolver,
  });

  final bool generandoPdf;
  final VoidCallback onDescargar;
  final VoidCallback onImprimir;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BotonGradiente(
          label: 'DESCARGAR PDF',
          icon: Icons.download_rounded,
          isLoading: generandoPdf,
          onPressed: onDescargar,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: generandoPdf ? null : onImprimir,
          icon: const Icon(Icons.print_rounded, size: 18),
          label: const Text('IMPRIMIR'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
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
        if (generandoPdf) ...<Widget>[
          const SizedBox(height: 10),
          const Text(
            'Generando PDF...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// Estado de carga del comprobante.
class _CargandoComprobante extends StatelessWidget {
  const _CargandoComprobante();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Cargando comprobante...',
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Error de carga: REINTENTAR (solo si tiene sentido) y VOLVER.
class _ErrorComprobante extends StatelessWidget {
  const _ErrorComprobante({
    required this.mensaje,
    this.onReintentar,
    required this.onVolver,
  });

  final String mensaje;
  final VoidCallback? onReintentar;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? reintentar = onReintentar;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
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
            if (reintentar != null) ...<Widget>[
              BotonGradiente(
                label: 'REINTENTAR',
                icon: Icons.refresh_rounded,
                onPressed: reintentar,
              ),
              const SizedBox(height: 12),
            ],
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
