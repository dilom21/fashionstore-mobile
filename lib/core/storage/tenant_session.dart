/// Sesión SaaS activa del CLIENTE.
///
/// `scopeKey` identifica de forma estable `empresa:usuario` y se conserva para
/// no invalidar las instantáneas CU17/CU18 ya descargadas. Los datos de perfil
/// son opcionales para mantener compatibilidad con sesiones antiguas.
class TenantSession {
  const TenantSession({
    required this.empresaId,
    required this.usuarioId,
    required this.empresaSlug,
    required this.empresaNombre,
    this.contexto = 'cliente',
    this.rol = 'CLIENTE',
    this.correo = '',
    this.nombre = '',
    this.apellido = '',
    this.sucursalId,
    this.planCodigo = '',
  });

  factory TenantSession.fromJson(Map<String, dynamic> json) => TenantSession(
    empresaId: _int(json['empresa_id']),
    usuarioId: _int(json['usuario_id']),
    empresaSlug: '${json['empresa_slug'] ?? ''}',
    empresaNombre: '${json['empresa_nombre'] ?? ''}',
    contexto: '${json['contexto'] ?? 'cliente'}',
    rol: '${json['rol'] ?? 'CLIENTE'}',
    correo: '${json['correo'] ?? ''}',
    nombre: '${json['nombre'] ?? ''}',
    apellido: '${json['apellido'] ?? ''}',
    sucursalId: _nullableInt(json['sucursal_id']),
    planCodigo: '${json['plan_codigo'] ?? ''}',
  );

  final int empresaId;
  final int usuarioId;
  final String empresaSlug;
  final String empresaNombre;
  final String contexto;
  final String rol;
  final String correo;
  final String nombre;
  final String apellido;
  final int? sucursalId;
  final String planCodigo;

  /// Clave de aislamiento usada por caché, SQLite CU17/CU18 y colas locales.
  String get scopeKey => '$empresaId:$usuarioId';

  String get nombreCompleto => '$nombre $apellido'.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'empresa_id': empresaId,
    'usuario_id': usuarioId,
    'empresa_slug': empresaSlug,
    'empresa_nombre': empresaNombre,
    'contexto': contexto,
    'rol': rol,
    'correo': correo,
    'nombre': nombre,
    'apellido': apellido,
    'sucursal_id': sucursalId,
    'plan_codigo': planCodigo,
  };
}

/// Referencia segura de un checkout móvil pendiente.
///
/// Solo guarda identificadores y datos de presentación: nunca secretos de
/// Stripe ni datos de tarjeta. Sirve para recuperar la venta PENDIENTE tras
/// cerrar/reabrir la app o volver desde Stripe, sin crear otra venta.
class PendingCheckout {
  const PendingCheckout({
    required this.ventaId,
    required this.carritoId,
    required this.total,
    required this.empresaSlug,
    this.sucursalNombre = '',
    this.estado = 'PENDIENTE',
  });

  factory PendingCheckout.fromJson(Map<String, dynamic> json) =>
      PendingCheckout(
        ventaId: _int(json['venta_id']),
        carritoId: _int(json['carrito_id']),
        total: _double(json['total']),
        empresaSlug: '${json['empresa_slug'] ?? ''}',
        sucursalNombre: '${json['sucursal_nombre'] ?? ''}',
        estado: '${json['estado'] ?? 'PENDIENTE'}',
      );

  final int ventaId;
  final int carritoId;
  final double total;
  final String empresaSlug;
  final String sucursalNombre;
  final String estado;

  bool get esValido => ventaId > 0 && carritoId > 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'venta_id': ventaId,
    'carrito_id': carritoId,
    'total': total,
    'empresa_slug': empresaSlug,
    'sucursal_nombre': sucursalNombre,
    'estado': estado,
  };
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

int? _nullableInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
