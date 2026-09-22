import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../models/vestidor_config_model.dart';
import '../models/vestidor_session_model.dart';

/// Error del Vestidor virtual con un mensaje apto para mostrar al cliente.
///
/// [unauthorized] indica que el JWT fue rechazado (hay que cerrar la sesión
/// local). [conflict] agrupa los 409 de negocio (sesión no activa,
/// configuración inactiva, transición inválida, variante incompatible).
/// [notFound] marca recursos inexistentes.
class VestidorApiException implements Exception {
  const VestidorApiException(
    this.message, {
    this.statusCode,
    this.unauthorized = false,
    this.conflict = false,
    this.notFound = false,
  });

  final String message;
  final int? statusCode;
  final bool unauthorized;
  final bool conflict;
  final bool notFound;

  @override
  String toString() => 'VestidorApiException($statusCode): $message';
}

/// Servicio HTTP de CU26 - Vestidor virtual (CLIENTE).
///
/// Flujo: Page/Launcher -> Service -> Backend FastAPI.
/// Endpoints (todos requieren JWT de contexto cliente):
///   GET   /vestidor-virtual/productos/{id}/configuraciones
///   POST  /vestidor-virtual/sesiones
///   POST  /vestidor-virtual/sesiones/{id}/pruebas
///   PATCH /vestidor-virtual/pruebas/{id}/finalizar
///   PATCH /vestidor-virtual/sesiones/{id}/finalizar
///
/// El backend obtiene el cliente desde `get_current_cliente`: la app nunca
/// envía `cliente_id`. Este servicio NO abre la cámara: solo negocia el DTO
/// [VestidorConfig] y el ciclo de vida de sesiones/pruebas. El motor AR de
/// Harold es 100% local.
class VestidorApiService {
  VestidorApiService({
    AuthStorage? storage,
    http.Client? client,
    String? baseUrl,
  }) : _storage = storage ?? AuthStorage(),
       _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).trim();

  static const Duration _timeout = Duration(seconds: 15);

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el vestidor. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'No pudimos completar la operación del vestidor. Inténtalo nuevamente.';
  static const String _unauthorizedMessage =
      'Tu sesión expiró. Vuelve a iniciar sesión.';
  static const String _forbiddenMessage =
      'No tienes acceso a este vestidor.';
  static const String _notFoundMessage =
      'No encontramos la información del vestidor solicitada.';
  static const String _conflictMessage =
      'La operación del vestidor no es válida en este momento.';
  static const String _validationMessage =
      'Los datos enviados al vestidor no son válidos.';
  static const String _timeoutMessage =
      'El vestidor tardó demasiado en responder. Inténtalo nuevamente.';

  final AuthStorage _storage;
  final http.Client _client;
  final String _baseUrl;

  /// Configuraciones AR compatibles de un producto.
  ///
  /// [varianteId] y [colorId] son filtros opcionales. Si el producto no tiene
  /// try-on se devuelve `compatible = false` (no es un error).
  Future<VestidorConfiguracionesResponse> obtenerConfiguraciones({
    required int productoId,
    int? varianteId,
    int? colorId,
  }) async {
    final Map<String, String> query = <String, String>{};
    if (varianteId != null && varianteId > 0) {
      query['variante_id'] = '$varianteId';
    }
    if (colorId != null && colorId > 0) query['color_id'] = '$colorId';

    final Object? data = await _enviar(
      'GET',
      ApiConfig.vestidorConfiguracionesUrlDesde(_baseUrl, productoId),
      query: query,
    );
    if (data is! Map) {
      throw const VestidorApiException(_unexpectedErrorMessage);
    }
    try {
      return VestidorConfiguracionesResponse.fromJson(
        data.cast<String, dynamic>(),
      );
    } catch (_) {
      throw const VestidorApiException(_unexpectedErrorMessage);
    }
  }

  /// Crea (o reutiliza) la sesión ACTIVA del cliente autenticado.
  Future<VestidorSesion> crearSesion() async {
    final Object? data = await _enviar(
      'POST',
      ApiConfig.vestidorSesionesUrlDesde(_baseUrl),
    );
    return _parseSesion(data);
  }

  /// Registra el inicio de una prueba de prenda en una sesión ACTIVA.
  Future<VestidorPrueba> iniciarPrueba({
    required int sesionId,
    required int configuracionId,
    int? varianteProductoId,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'configuracion_id': configuracionId,
    };
    if (varianteProductoId != null && varianteProductoId > 0) {
      body['variante_producto_id'] = varianteProductoId;
    }

    final Object? data = await _enviar(
      'POST',
      ApiConfig.vestidorSesionPruebasUrlDesde(_baseUrl, sesionId),
      body: body,
    );
    return _parsePrueba(data);
  }

  /// Finaliza una prueba con un estado final (idempotente en el backend).
  Future<VestidorPrueba> finalizarPrueba({
    required int pruebaId,
    required String estado,
  }) async {
    final Object? data = await _enviar(
      'PATCH',
      ApiConfig.vestidorPruebaFinalizarUrlDesde(_baseUrl, pruebaId),
      body: <String, dynamic>{'estado': estado},
    );
    return _parsePrueba(data);
  }

  /// Finaliza una sesión con un estado final (idempotente en el backend).
  Future<VestidorSesion> finalizarSesion({
    required int sesionId,
    required String estado,
  }) async {
    final Object? data = await _enviar(
      'PATCH',
      ApiConfig.vestidorSesionFinalizarUrlDesde(_baseUrl, sesionId),
      body: <String, dynamic>{'estado': estado},
    );
    return _parseSesion(data);
  }

  // -------------------------------------------------------------------------
  // Parsing
  // -------------------------------------------------------------------------

  VestidorSesion _parseSesion(Object? data) {
    if (data is! Map) {
      throw const VestidorApiException(_unexpectedErrorMessage);
    }
    try {
      return VestidorSesion.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const VestidorApiException(_unexpectedErrorMessage);
    }
  }

  VestidorPrueba _parsePrueba(Object? data) {
    if (data is! Map) {
      throw const VestidorApiException(_unexpectedErrorMessage);
    }
    try {
      return VestidorPrueba.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const VestidorApiException(_unexpectedErrorMessage);
    }
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  Future<Object?> _enviar(
    String metodo,
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    _asegurarConfiguracion();
    final Map<String, String> headers = await _headers(conCuerpo: body != null);
    Uri uri = Uri.parse(url);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }

    final http.Response response;
    try {
      switch (metodo) {
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(_timeout);
        case 'PATCH':
          response = await _client
              .patch(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(_timeout);
        default:
          response = await _client.get(uri, headers: headers).timeout(_timeout);
      }
    } on TimeoutException {
      throw const VestidorApiException(_timeoutMessage);
    } catch (_) {
      throw const VestidorApiException(_connectionErrorMessage);
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      final String cuerpo = response.body.trim();
      if (cuerpo.isEmpty) {
        throw const VestidorApiException(_unexpectedErrorMessage);
      }
      try {
        return jsonDecode(cuerpo);
      } catch (_) {
        throw const VestidorApiException(_unexpectedErrorMessage);
      }
    }

    throw _errorDesde(response);
  }

  /// Traduce el código de estado a un error con mensaje para el cliente.
  VestidorApiException _errorDesde(http.Response response) {
    switch (response.statusCode) {
      case 401:
        return const VestidorApiException(
          _unauthorizedMessage,
          statusCode: 401,
          unauthorized: true,
        );
      case 403:
        return const VestidorApiException(
          _forbiddenMessage,
          statusCode: 403,
        );
      case 404:
        return const VestidorApiException(
          _notFoundMessage,
          statusCode: 404,
          notFound: true,
        );
      case 409:
        return const VestidorApiException(
          _conflictMessage,
          statusCode: 409,
          conflict: true,
        );
      case 422:
        return const VestidorApiException(
          _validationMessage,
          statusCode: 422,
        );
      default:
        return VestidorApiException(
          _unexpectedErrorMessage,
          statusCode: response.statusCode,
        );
    }
  }

  /// Cabeceras de la petición, con el JWT del cliente.
  Future<Map<String, String>> _headers({required bool conCuerpo}) async {
    final String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      throw const VestidorApiException(_unexpectedErrorMessage);
    }
    if (token == null || token.isEmpty) {
      throw const VestidorApiException(
        _unauthorizedMessage,
        statusCode: 401,
        unauthorized: true,
      );
    }

    return <String, String>{
      'Accept': 'application/json',
      if (conCuerpo) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  void _asegurarConfiguracion() {
    if (_baseUrl.isEmpty) {
      throw const VestidorApiException(ApiConfig.missingBaseUrlHint);
    }
  }
}
