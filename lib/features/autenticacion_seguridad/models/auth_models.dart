// Modelos de datos del feature de autenticación y seguridad (CLIENTES).
//
// Mapean el contrato JSON del backend FastAPI (snake_case) a nombres Dart
// idiomáticos (camelCase):
//   access_token -> accessToken
//   token_type   -> tokenType
//   cliente_id   -> clienteId

/// Cuerpo del request para `POST /auth/tenant/login`.
class LoginRequest {
  const LoginRequest({
    required this.correo,
    required this.password,
    required this.empresaSlug,
  });

  final String correo;
  final String password;
  final String empresaSlug;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'correo': correo,
    'password': password,
    'empresa_slug': empresaSlug,
    'contexto': 'cliente',
  };
}

/// Empresa habilitada devuelta por `GET /auth/tenant/empresas`.
class EmpresaTenant {
  const EmpresaTenant({required this.slug, required this.nombreComercial});

  factory EmpresaTenant.fromJson(Map<String, dynamic> json) => EmpresaTenant(
    slug: _toString(json['slug']).trim().toLowerCase(),
    nombreComercial: _toString(json['nombre_comercial']).trim(),
  );

  final String slug;
  final String nombreComercial;

  String get etiqueta => nombreComercial.isEmpty ? slug : nombreComercial;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'slug': slug,
    'nombre_comercial': nombreComercial,
  };
}

/// Identidad del usuario autenticado devuelta por `GET /auth/tenant/me`.
class UsuarioAuth {
  const UsuarioAuth({
    required this.id,
    required this.correo,
    required this.rol,
    required this.contexto,
    this.empresaId = 0,
    this.empresaSlug = '',
    this.empresaNombre = '',
    this.nombre = '',
    this.apellido = '',
    this.sucursalId,
    this.planCodigo = '',
    this.permiteReportesIa = false,
  });

  factory UsuarioAuth.fromJson(Map<String, dynamic> json) => UsuarioAuth(
    id: _toInt(json['usuario_id'] ?? json['id']),
    correo: _toString(json['correo']),
    rol: _toString(json['rol']),
    contexto: _toString(json['contexto']),
    empresaId: _toInt(json['empresa_id']),
    empresaSlug: _toString(json['empresa_slug']),
    empresaNombre: _toString(json['empresa_nombre']),
    nombre: _toString(json['nombre']),
    apellido: _toString(json['apellido']),
    sucursalId: _toNullableInt(json['sucursal_id']),
    planCodigo: _toString(json['plan_codigo']),
    permiteReportesIa: json['permite_reportes_ia'] == true,
  );

  final int id;
  final String correo;
  final String rol;
  final String contexto;
  final int empresaId;
  final String empresaSlug;
  final String empresaNombre;
  final String nombre;
  final String apellido;
  final int? sucursalId;
  final String planCodigo;
  final bool permiteReportesIa;

  String get nombreCompleto => '$nombre $apellido'.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'correo': correo,
    'rol': rol,
    'contexto': contexto,
    'empresa_id': empresaId,
    'empresa_slug': empresaSlug,
    'empresa_nombre': empresaNombre,
    'nombre': nombre,
    'apellido': apellido,
    'sucursal_id': sucursalId,
    'plan_codigo': planCodigo,
    'permite_reportes_ia': permiteReportesIa,
  };
}

/// Datos del cliente autenticado devueltos por `POST /auth/tenant/login`.
class ClienteAuth {
  const ClienteAuth({
    required this.id,
    required this.correo,
    required this.rol,
    required this.contexto,
    required this.clienteId,
    required this.nombre,
    required this.apellido,
  });

  factory ClienteAuth.fromJson(Map<String, dynamic> json) => ClienteAuth(
    id: _toInt(json['id']),
    correo: _toString(json['correo']),
    rol: _toString(json['rol']),
    contexto: _toString(json['contexto']),
    clienteId: _toNullableInt(json['cliente_id']),
    nombre: _toString(json['nombre']),
    apellido: _toString(json['apellido']),
  );

  final int id;
  final String correo;
  final String rol;
  final String contexto;
  final int? clienteId;
  final String nombre;
  final String apellido;

  /// Nombre completo para mostrar al cliente.
  String get nombreCompleto => '$nombre $apellido'.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'correo': correo,
    'rol': rol,
    'contexto': contexto,
    'cliente_id': clienteId,
    'nombre': nombre,
    'apellido': apellido,
  };
}

/// Respuesta de `POST /auth/tenant/login`.
class ClienteLoginResponse {
  const ClienteLoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.usuario,
    required this.empresaId,
    required this.empresaSlug,
    required this.empresaNombre,
  });

  factory ClienteLoginResponse.fromJson(Map<String, dynamic> json) =>
      ClienteLoginResponse(
        accessToken: _toString(json['access_token']),
        tokenType: _toString(json['token_type']),
        usuario: ClienteAuth.fromJson(
          json['usuario'] is Map
              ? _toJsonMap(json['usuario'])
              : <String, dynamic>{
                  'rol': json['rol'],
                  'contexto': json['contexto'],
                },
        ),
        empresaId: _toInt(json['empresa_id']),
        empresaSlug: _toString(json['empresa_slug']),
        empresaNombre: _toString(json['empresa_nombre']),
      );

  final String accessToken;
  final String tokenType;
  final ClienteAuth usuario;
  final int empresaId;
  final String empresaSlug;
  final String empresaNombre;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'access_token': accessToken,
    'token_type': tokenType,
    'usuario': usuario.toJson(),
    'empresa_id': empresaId,
    'empresa_slug': empresaSlug,
    'empresa_nombre': empresaNombre,
  };
}

/// Sexo del cliente: valores REALES admitidos por el backend
/// (`SexoCliente` en `app/modules/autenticacion_seguridad/schemas/schemas.py`).
///
/// [codigo] es lo que viaja al backend; [etiqueta] es lo que ve el cliente
/// (nunca se muestra el valor crudo del enum).
enum SexoCliente {
  masculino('MASCULINO', 'Masculino'),
  femenino('FEMENINO', 'Femenino'),
  otro('OTRO', 'Otro'),
  noEspecifica('NO_ESPECIFICA', 'Prefiero no especificar');

  const SexoCliente(this.codigo, this.etiqueta);

  /// Valor exacto que espera el backend.
  final String codigo;

  /// Texto para la interfaz.
  final String etiqueta;
}

/// Cuerpo del request para `POST /auth/tenant/clientes/registro`.
///
/// Los 9 campos son obligatorios y el backend rechaza campos extra
/// (`model_config = ConfigDict(extra="forbid")`), por eso [toJson] emite
/// exactamente las claves del contrato en snake_case.
class ClienteRegistroRequest {
  const ClienteRegistroRequest({
    required this.empresaSlug,
    required this.correo,
    required this.password,
    required this.passwordConfirmacion,
    required this.nombre,
    required this.apellido,
    required this.ci,
    required this.telefono,
    required this.sexo,
    required this.fechaNacimiento,
  });

  /// Empresa seleccionada por el cliente; el backend la valida.
  final String empresaSlug;
  final String correo;
  final String password;
  final String passwordConfirmacion;
  final String nombre;
  final String apellido;
  final String ci;
  final String telefono;
  final SexoCliente sexo;
  final DateTime fechaNacimiento;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'empresa_slug': empresaSlug.trim().toLowerCase(),
    'correo': correo,
    'password': password,
    'password_confirmacion': passwordConfirmacion,
    'nombre': nombre,
    'apellido': apellido,
    'ci': ci,
    'telefono': telefono,
    'sexo': sexo.codigo,
    'fecha_nacimiento': _fechaBackend(fechaNacimiento),
  };
}

/// Respuesta de `POST /auth/tenant/clientes/registro` (201).
///
/// No incluye `access_token`: el registro NO inicia sesión, así que este
/// modelo no se guarda en `AuthStorage`.
class ClienteRegistroResponse {
  const ClienteRegistroResponse({
    required this.mensaje,
    required this.usuarioId,
    required this.clienteId,
    required this.correo,
    required this.nombre,
    required this.apellido,
  });

  factory ClienteRegistroResponse.fromJson(Map<String, dynamic> json) =>
      ClienteRegistroResponse(
        mensaje: _toString(json['mensaje']),
        usuarioId: _toInt(json['usuario_id']),
        clienteId: _toInt(json['cliente_id']),
        correo: _toString(json['correo']),
        nombre: _toString(json['nombre']),
        apellido: _toString(json['apellido']),
      );

  final String mensaje;
  final int usuarioId;
  final int clienteId;
  final String correo;
  final String nombre;
  final String apellido;

  /// Nombre de pila para el mensaje de confirmación.
  String get nombrePila => nombre.trim();
}

/// Convierte la fecha al `YYYY-MM-DD` que espera el backend (`date`).
///
/// Se arma con los componentes locales porque es una fecha de calendario, sin
/// zona horaria ni hora.
String _fechaBackend(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}'
    '-${fecha.month.toString().padLeft(2, '0')}'
    '-${fecha.day.toString().padLeft(2, '0')}';

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _toNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _toString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

Map<String, dynamic> _toJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return <String, dynamic>{};
}
