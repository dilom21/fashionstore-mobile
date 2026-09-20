import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../models/pago_electronico_model.dart';

/// Error del pago electrónico con un mensaje apto para mostrar al cliente.
///
/// [unauthorized] indica que el JWT fue rechazado (hay que cerrar la sesión
/// local). [conflicto] indica un 409 del backend (venta no pagable, ya
/// completada, inconsistencia, etc.).
class PagoElectronicoException implements Exception {
  const PagoElectronicoException(
    this.message, {
    this.statusCode,
    this.unauthorized = false,
    this.conflicto = false,
  });

  final String message;
  final int? statusCode;
  final bool unauthorized;
  final bool conflicto;

  @override
  String toString() => 'PagoElectronicoException($statusCode): $message';
}

/// Servicio HTTP de CU22: intención de pago y consulta de estado.
///
/// Flujo: Page -> Service -> Backend FastAPI.
/// Endpoints consumidos (requieren JWT de contexto cliente):
///   POST /pagos/stripe/intencion
///   GET  /pagos/stripe/ventas/{venta_id}/estado
///
/// NO presenta el PaymentSheet ni llama al webhook: eso es responsabilidad del
/// gateway de Stripe y de Stripe respectivamente.
class PagoElectronicoService {
  /// Crea el servicio, permitiendo inyectar almacenamiento y cliente HTTP.
  ///
  /// [baseUrl] es un punto de inyección para pruebas; en producción se usa
  /// siempre `ApiConfig.baseUrl`.
  PagoElectronicoService({
    AuthStorage? storage,
    http.Client? client,
    String? baseUrl,
  }) : _storage = storage ?? AuthStorage(),
       _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).trim();

  static const Duration _timeout = Duration(seconds: 15);

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el servicio. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'Ocurrió un problema. Inténtalo nuevamente.';
  static const String _unauthorizedMessage =
      'Tu sesión expiró. Vuelve a iniciar sesión.';
  static const String _forbiddenMessage =
      'No tienes acceso a esta venta para pagarla.';
  static const String _notFoundMessage =
      'No encontramos la venta para procesar el pago.';
  static const String _validationMessage =
      'No pudimos iniciar el pago con los datos enviados. Inténtalo nuevamente.';
  static const String _conflictMessage =
      'No fue posible procesar el pago electrónico de esta venta.';
  static const String _gatewayMessage =
      'La pasarela de pago no está disponible. Inténtalo más tarde.';
  static const String _configErrorMessage =
      'Stripe no está configurado en el servidor. Inténtalo más tarde.';

  final AuthStorage _storage;
  final http.Client _client;
  final String _baseUrl;

  /// Crea/reutiliza el PaymentIntent de la venta (`POST /pagos/stripe/intencion`).
  Future<IntencionPago> crearIntencion(int ventaId) async {
    final Object? data = await _enviar(
      'POST',
      ApiConfig.stripeIntencionUrlDesde(_baseUrl),
      body: <String, dynamic>{'venta_id': ventaId},
    );
    if (data is! Map) {
      throw const PagoElectronicoException(_unexpectedErrorMessage);
    }
    try {
      return IntencionPago.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const PagoElectronicoException(_unexpectedErrorMessage);
    }
  }

  /// Consulta el estado backend de la venta y su pago electrónico.
  Future<EstadoPagoVenta> consultarEstado(int ventaId) async {
    final Object? data = await _enviar(
      'GET',
      ApiConfig.stripeEstadoVentaUrlDesde(_baseUrl, ventaId),
    );
    if (data is! Map) {
      throw const PagoElectronicoException(_unexpectedErrorMessage);
    }
    try {
      return EstadoPagoVenta.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const PagoElectronicoException(_unexpectedErrorMessage);
    }
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  /// Ejecuta la petición autenticada y decodifica el JSON.
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
    } catch (_) {
      throw const PagoElectronicoException(_connectionErrorMessage);
    }

    if (response.statusCode == 200 ||
        response.statusCode == 201 ||
        response.statusCode == 204) {
      final String cuerpo = response.body.trim();
      if (cuerpo.isEmpty) {
        throw const PagoElectronicoException(_unexpectedErrorMessage);
      }
      try {
        return jsonDecode(cuerpo);
      } catch (_) {
        throw const PagoElectronicoException(_unexpectedErrorMessage);
      }
    }

    throw _errorDesde(response);
  }

  /// Traduce el código de estado a un error con mensaje para el cliente.
  PagoElectronicoException _errorDesde(http.Response response) {
    switch (response.statusCode) {
      case 401:
        return const PagoElectronicoException(
          _unauthorizedMessage,
          statusCode: 401,
          unauthorized: true,
        );
      case 403:
        return const PagoElectronicoException(
          _forbiddenMessage,
          statusCode: 403,
        );
      case 404:
        return const PagoElectronicoException(
          _notFoundMessage,
          statusCode: 404,
        );
      case 409:
        return PagoElectronicoException(
          _mensajeConflicto(response),
          statusCode: 409,
          conflicto: true,
        );
      case 422:
        return const PagoElectronicoException(
          _validationMessage,
          statusCode: 422,
        );
      case 500:
        return const PagoElectronicoException(
          _configErrorMessage,
          statusCode: 500,
        );
      case 502:
        return const PagoElectronicoException(_gatewayMessage, statusCode: 502);
      default:
        return PagoElectronicoException(
          _unexpectedErrorMessage,
          statusCode: response.statusCode,
        );
    }
  }

  /// Conserva el `detail` de negocio ya validado (nunca SQL ni trazas).
  String _mensajeConflicto(http.Response response) {
    final String? detalle = _detalleDeError(response);
    return detalle ?? _conflictMessage;
  }

  /// Extrae `detail` del backend solo si es un mensaje breve y no técnico.
  String? _detalleDeError(http.Response response) {
    try {
      final Object? data = jsonDecode(response.body);
      if (data is! Map) return null;
      final Object? detalle = data['detail'];
      final String texto = detalle is String ? detalle.trim() : '';
      if (texto.isEmpty || texto.length > 160) return null;
      final String minusculas = texto.toLowerCase();
      const List<String> tecnicos = <String>[
        'traceback',
        'exception',
        'sql',
        'select ',
        'insert ',
        'postgres',
        'error interno',
      ];
      for (final String tecnico in tecnicos) {
        if (minusculas.contains(tecnico)) return null;
      }
      return texto;
    } catch (_) {
      return null;
    }
  }

  /// Cabeceras de la petición, con el JWT del cliente.
  Future<Map<String, String>> _headers({required bool conCuerpo}) async {
    final String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      throw const PagoElectronicoException(_unexpectedErrorMessage);
    }
    if (token == null || token.isEmpty) {
      throw const PagoElectronicoException(
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
      throw const PagoElectronicoException(ApiConfig.missingBaseUrlHint);
    }
  }
}
