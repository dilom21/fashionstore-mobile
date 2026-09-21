import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../models/asistencia_models.dart';

/// Error de Asistencia Inteligente con un mensaje apto para mostrar al cliente.
///
/// [unauthorized] indica que el JWT fue rechazado (hay que cerrar la sesión
/// local). [noConfigurada] indica un 503: el asistente no está configurado en
/// el backend (falta provider/model/API key). Las claves NUNCA viajan a Flutter.
class AsistenciaException implements Exception {
  const AsistenciaException(
    this.message, {
    this.statusCode,
    this.unauthorized = false,
    this.noConfigurada = false,
  });

  final String message;
  final int? statusCode;
  final bool unauthorized;
  final bool noConfigurada;

  @override
  String toString() => 'AsistenciaException($statusCode): $message';
}

/// Servicio de Asistencia Inteligente del CLIENTE.
///
/// Flujo: Page -> Service -> Backend FastAPI.
/// Endpoint consumido (requiere JWT de contexto cliente):
///   POST /asistencia-inteligente/recomendaciones
///
/// El backend obtiene el cliente desde `get_current_cliente`: la app nunca
/// envía `cliente_id`. La IA vive solo en el backend; aquí no hay ninguna
/// clave ni SDK de IA.
class AsistenciaService {
  /// Crea el servicio, permitiendo inyectar almacenamiento y cliente HTTP.
  ///
  /// [baseUrl] es un punto de inyección para pruebas; en producción se usa
  /// siempre `ApiConfig.baseUrl`.
  AsistenciaService({
    AuthStorage? storage,
    http.Client? client,
    String? baseUrl,
  }) : _storage = storage ?? AuthStorage(),
       _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).trim();

  static const Duration _timeout = Duration(seconds: 20);

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el asistente. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'No pudimos generar recomendaciones. Inténtalo nuevamente.';
  static const String _unauthorizedMessage =
      'Tu sesión expiró. Vuelve a iniciar sesión.';
  static const String _forbiddenMessage =
      'No tienes acceso a la asistencia inteligente.';
  static const String _validationMessage =
      'Tu consulta no es válida. Revísala e inténtalo nuevamente.';
  static const String _noConfiguradaMessage =
      'La asistencia inteligente no está disponible por ahora.';
  static const String _timeoutMessage =
      'El asistente tardó demasiado. Inténtalo nuevamente.';
  static const String _providerMessage =
      'No pudimos generar recomendaciones en este momento. Inténtalo nuevamente.';

  final AuthStorage _storage;
  final http.Client _client;
  final String _baseUrl;

  /// Pide recomendaciones al backend (`POST /asistencia-inteligente/recomendaciones`).
  ///
  /// Solo `consulta` es obligatoria. `talla`, `color`, `presupuestoMax` y
  /// `sucursalId` son filtros estructurados opcionales.
  Future<RecomendacionesResponse> recomendar({
    required String consulta,
    String? talla,
    String? color,
    double? presupuestoMax,
    int? sucursalId,
    int limite = 4,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'consulta': consulta.trim(),
      'limite': limite,
    };
    final String tallaTexto = (talla ?? '').trim();
    if (tallaTexto.isNotEmpty) body['talla'] = tallaTexto;
    final String colorTexto = (color ?? '').trim();
    if (colorTexto.isNotEmpty) body['color'] = colorTexto;
    if (presupuestoMax != null && presupuestoMax > 0) {
      body['presupuesto_max'] = presupuestoMax;
    }
    if (sucursalId != null && sucursalId > 0) {
      body['sucursal_id'] = sucursalId;
    }

    final Object? data = await _enviar(
      'POST',
      ApiConfig.asistenciaRecomendacionesUrlDesde(_baseUrl),
      body: body,
    );
    if (data is! Map) throw const AsistenciaException(_unexpectedErrorMessage);
    try {
      return RecomendacionesResponse.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const AsistenciaException(_unexpectedErrorMessage);
    }
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  Future<Object?> _enviar(
    String metodo,
    String url, {
    Map<String, dynamic>? body,
  }) async {
    _asegurarConfiguracion();
    final Map<String, String> headers = await _headers(conCuerpo: body != null);
    final Uri uri = Uri.parse(url);

    final http.Response response;
    try {
      if (metodo == 'POST') {
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout);
      } else {
        response = await _client.get(uri, headers: headers).timeout(_timeout);
      }
    } on TimeoutException {
      throw const AsistenciaException(_timeoutMessage);
    } catch (_) {
      throw const AsistenciaException(_connectionErrorMessage);
    }

    if (response.statusCode == 200) {
      final String cuerpo = response.body.trim();
      if (cuerpo.isEmpty) {
        throw const AsistenciaException(_unexpectedErrorMessage);
      }
      try {
        return jsonDecode(cuerpo);
      } catch (_) {
        throw const AsistenciaException(_unexpectedErrorMessage);
      }
    }

    throw _errorDesde(response);
  }

  /// Traduce el código de estado a un error con mensaje para el cliente.
  AsistenciaException _errorDesde(http.Response response) {
    switch (response.statusCode) {
      case 401:
        return const AsistenciaException(
          _unauthorizedMessage,
          statusCode: 401,
          unauthorized: true,
        );
      case 403:
        return const AsistenciaException(
          _forbiddenMessage,
          statusCode: 403,
        );
      case 422:
        return const AsistenciaException(
          _validationMessage,
          statusCode: 422,
        );
      case 502:
        return const AsistenciaException(
          _providerMessage,
          statusCode: 502,
        );
      case 503:
        return const AsistenciaException(
          _noConfiguradaMessage,
          statusCode: 503,
          noConfigurada: true,
        );
      case 504:
        return const AsistenciaException(_timeoutMessage, statusCode: 504);
      default:
        return AsistenciaException(
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
      throw const AsistenciaException(_unexpectedErrorMessage);
    }
    if (token == null || token.isEmpty) {
      throw const AsistenciaException(
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
      throw const AsistenciaException(ApiConfig.missingBaseUrlHint);
    }
  }
}
