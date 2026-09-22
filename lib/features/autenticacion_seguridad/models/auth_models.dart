// Modelos de datos del feature de autenticación y seguridad (CLIENTES).
//
// Mapean el contrato JSON del backend FastAPI (snake_case) a nombres Dart
// idiomáticos (camelCase):
//   access_token -> accessToken
//   token_type   -> tokenType
//   cliente_id   -> clienteId

/// Cuerpo del request para `POST /auth/clientes/login`.
class LoginRequest {
  const LoginRequest({required this.correo, required this.password});

  final String correo;
  final String password;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'correo': correo,
    'password': password,
  };
}

/// Identidad del usuario autenticado devuelta por `GET /auth/me`.
class UsuarioAuth {
  const UsuarioAuth({
    required this.id,
    required this.correo,
    required this.rol,
    required this.contexto,
  });

  factory UsuarioAuth.fromJson(Map<String, dynamic> json) => UsuarioAuth(
    id: _toInt(json['id']),
    correo: _toString(json['correo']),
    rol: _toString(json['rol']),
    contexto: _toString(json['contexto']),
  );

  final int id;
  final String correo;
  final String rol;
  final String contexto;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'correo': correo,
    'rol': rol,
    'contexto': contexto,
  };
}

/// Datos del cliente autenticado devueltos por `POST /auth/clientes/login`.
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

/// Respuesta de `POST /auth/clientes/login`.
class ClienteLoginResponse {
  const ClienteLoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.usuario,
  });

  factory ClienteLoginResponse.fromJson(Map<String, dynamic> json) =>
      ClienteLoginResponse(
        accessToken: _toString(json['access_token']),
        tokenType: _toString(json['token_type']),
        usuario: ClienteAuth.fromJson(_toJsonMap(json['usuario'])),
      );

  final String accessToken;
  final String tokenType;
  final ClienteAuth usuario;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'access_token': accessToken,
    'token_type': tokenType,
    'usuario': usuario.toJson(),
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

/// Cuerpo del request para `POST /auth/clientes/registro`.
///
/// Los 9 campos son obligatorios y el backend rechaza campos extra
/// (`model_config = ConfigDict(extra="forbid")`), por eso [toJson] emite
/// exactamente las claves del contrato en snake_case.
class ClienteRegistroRequest {
  const ClienteRegistroRequest({
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

/// Respuesta de `POST /auth/clientes/registro` (201).
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
