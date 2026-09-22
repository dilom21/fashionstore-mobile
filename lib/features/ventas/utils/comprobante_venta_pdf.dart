import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/date_formatters.dart';
import '../models/comprobante_venta_model.dart';

/// Nombre del archivo PDF del comprobante: `comprobante-VTA-00535.pdf`.
String nombreArchivoComprobante(int ventaId) =>
    'comprobante-${codigoVenta(ventaId)}.pdf';

/// Genera el PDF vectorial del comprobante (no es una captura de pantalla).
///
/// Reconstruye únicamente la información real que devuelve el backend: no se
/// añaden números fiscales, impuestos ni datos de tarjeta porque no existen en
/// el contrato de CU23.
Future<Uint8List> generarPdfComprobante(ComprobanteVenta comprobante) async {
  final pw.Document documento = pw.Document();

  documento.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context context) => <pw.Widget>[
        _cabecera(comprobante),
        pw.SizedBox(height: 14),
        _datosGenerales(comprobante),
        pw.SizedBox(height: 14),
        _tablaProductos(comprobante),
        pw.SizedBox(height: 12),
        _totalYPago(comprobante),
        pw.SizedBox(height: 22),
        _pie(),
      ],
    ),
  );

  return documento.save();
}

final pw.TextStyle _estiloEtiqueta = pw.TextStyle(
  fontSize: 9,
  color: PdfColors.grey700,
);
final pw.TextStyle _estiloValor = pw.TextStyle(
  fontSize: 10,
  fontWeight: pw.FontWeight.bold,
);

/// Cabecera: marca, título, código y estado de la venta.
pw.Widget _cabecera(ComprobanteVenta comprobante) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: <pw.Widget>[
      pw.Text(
        'VANTER MEN',
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text('COMPROBANTE DE VENTA', style: const pw.TextStyle(fontSize: 11)),
      pw.SizedBox(height: 8),
      pw.Text(
        '${comprobante.codigo}   ${comprobante.estadoVenta}',
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );
}

/// Fila `etiqueta: valor`; las filas sin valor no se emiten.
pw.Widget _fila(String etiqueta, String? valor) {
  final String texto = (valor ?? '').trim();
  if (texto.isEmpty) return pw.SizedBox.shrink();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.SizedBox(width: 96, child: pw.Text(etiqueta, style: _estiloEtiqueta)),
        pw.Expanded(child: pw.Text(texto, style: _estiloValor)),
      ],
    ),
  );
}

/// Datos generales: fecha, canal, sucursal, cliente y empleado (si existe).
pw.Widget _datosGenerales(ComprobanteVenta comprobante) {
  final ComprobanteCliente? cliente = comprobante.cliente;
  final ComprobanteEmpleado? empleado = comprobante.empleado;
  final ComprobanteSucursal sucursal = comprobante.sucursal;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      _fila('Fecha', formatearFechaHora(comprobante.fechaHora)),
      _fila('Canal', comprobante.canal),
      _fila('Sucursal', sucursal.nombre),
      _fila('Dirección', sucursal.direccion),
      _fila('Teléfono', sucursal.telefono),
      _fila(
        'Cliente',
        cliente == null ? 'Cliente general' : cliente.nombreCompleto,
      ),
      if (cliente != null) ...<pw.Widget>[
        _fila('CI', cliente.ci),
        _fila('Tel. cliente', cliente.telefono),
      ],
      // En compras MOVIL el empleado es `null`: la fila simplemente no se emite.
      if (empleado != null) _fila('Registrado por', empleado.nombreCompleto),
      _fila(
        'Carrito',
        comprobante.carritoId == null ? null : '#${comprobante.carritoId}',
      ),
      _fila(
        'Reserva',
        comprobante.reservaId == null ? null : '#${comprobante.reservaId}',
      ),
    ],
  );
}

/// Tabla de productos del comprobante.
pw.Widget _tablaProductos(ComprobanteVenta comprobante) {
  final List<List<String>> filas = <List<String>>[
    for (final ComprobanteVentaItem item in comprobante.items)
      <String>[
        item.varianteTexto.isEmpty
            ? item.productoNombre
            : '${item.productoNombre}\n${item.varianteTexto}',
        '${item.cantidad}',
        item.precioUnitarioFormateado,
        item.subtotalFormateado,
      ],
  ];

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Text('PRODUCTOS', style: _estiloEtiqueta),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: <String>['Producto', 'Cant.', 'P. unitario', 'Subtotal'],
        data: filas,
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellAlignments: <int, pw.Alignment>{
          1: pw.Alignment.centerRight,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
        },
        columnWidths: <int, pw.TableColumnWidth>{
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(1.4),
        },
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      ),
    ],
  );
}

/// Total (autoridad: backend) y datos del pago aprobado.
pw.Widget _totalYPago(ComprobanteVenta comprobante) {
  final ComprobantePago pago = comprobante.pago;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            'TOTAL',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            comprobante.totalFormateado,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
      pw.SizedBox(height: 10),
      _fila('Método', pago.metodo),
      _fila('Estado', pago.estado),
      _fila('Pasarela', pago.pasarela),
      _fila('Referencia', pago.referenciaTransaccion),
      _fila('Unidades', '${comprobante.cantidadTotalUnidades}'),
    ],
  );
}

/// Pie del comprobante.
pw.Widget _pie() {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: <pw.Widget>[
      pw.Text(
        'Gracias por tu compra.',
        style: const pw.TextStyle(fontSize: 10),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        'VANTER MEN - Moda que te define',
        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    ],
  );
}
