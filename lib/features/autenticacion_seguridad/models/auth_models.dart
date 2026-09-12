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
