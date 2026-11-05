class VentaContado {
  const VentaContado({required this.ventaId, required this.pagoId, required this.estado, required this.total, required this.operacionId});

  factory VentaContado.fromJson(Map<String, dynamic> json) => VentaContado(
        ventaId: (json['venta_id'] as num).toInt(),
        pagoId: (json['pago_id'] as num).toInt(),
        estado: json['estado'] as String,
        total: (json['total'] as num).toDouble(),
        operacionId: json['operacion_id'] as String,
      );

  final int ventaId;
  final int pagoId;
  final String estado;
  final double total;
  final String operacionId;
}
