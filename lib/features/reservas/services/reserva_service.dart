import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/utils/date_formatters.dart';
import '../models/reserva_model.dart';

/// Error de reservas con un mensaje apto para mostrar al cliente.
///
/// [unauthorized] indica que el JWT fue rechazado (hay que cerrar la sesión
/// local). [conflicto] indica un 409 del backend (carrito ya convertido, stock
/// insuficiente, reserva no cancelable, etc.).
class ReservaException implements Exception {
  const ReservaException(
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
  String toString() => 'ReservaException($statusCode): $message';
}

/// Servicio de reserva de prendas del CLIENTE (CU16).
///
/// Flujo: Page -> Service -> Backend FastAPI.
/// Endpoints consumidos (todos requieren JWT de contexto cliente):
///   POST  /reservas
///   GET   /reservas
///   GET   /reservas/{reserva_id}
///   PATCH /reservas/{reserva_id}/cancelar
///
/// El backend obtiene el cliente desde `get_current_cliente`: la app nunca
/// envía `cliente_id`.
class ReservaService {
  /// Crea el servicio, permitiendo inyectar almacenamiento y cliente HTTP.
  ReservaService({AuthStorage? storage, http.Client? client})
      : _storage = storage ?? AuthStorage(),
        _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 15);

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el servicio. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'Ocurrió un problema. Inténtalo nuevamente.';
  static const String _unauthorizedMessage =
      'Tu sesión expiró. Vuelve a iniciar sesión.';
  static const String _forbiddenMessage = 'No tienes acceso a esta reserva.';
  static const String _notFoundMessage =
      'No encontramos la reserva o el carrito solicitado.';
  static const String _validationMessage =
      'La fecha y hora seleccionadas no son válidas. Revísalas e inténtalo nuevamente.';
  static const String _conflictMessage =
      'La operación no pudo completarse. Actualiza la información e inténtalo nuevamente.';
  static const String _conflictStockMessage =
      'No fue posible reservar todas las prendas. Revisa nuevamente la disponibilidad.';
  static const String _conflictCancelMessage = 'Esta reserva ya no puede cancelarse.';

  final AuthStorage _storage;
  final http.Client _client;

  /// Crea una reserva a partir de un carrito ACTIVO (`POST /reservas`).
  ///
  /// Solo se envían carrito, fecha de atención y observación: el backend deriva
  /// sucursal, inventario, productos y cantidades desde el carrito almacenado.
  Future<ReservaDetalle> crearReserva({
    required int carritoId,
    required DateTime fechaAtencion,
    String? observacion,
  }) async {
    final Object? data = await _enviar(
      'POST',
      ApiConfig.reservasUrl,
      mensajeConflicto: _conflictStockMessage,
      body: <String, dynamic>{
        'carrito_id': carritoId,
        'fecha_atencion': formatearIsoLocal(fechaAtencion),
        'observacion': _observacionOLimpiar(observacion),
      },
    );
    return _detalleDesde(data);
  }

  /// Lista las reservas del cliente (`GET /reservas`).
  ///
  /// [estado] es un filtro opcional con los valores reales del backend.
  Future<ReservaListaResponse> listarReservas({String? estado}) async {
    final String filtro = (estado ?? '').trim().toUpperCase();
    final Object? data = await _enviar(
      'GET',
      ApiConfig.reservasUrl,
      query: filtro.isEmpty ? null : <String, String>{'estado': filtro},
    );
    if (data is! Map) throw const ReservaException(_unexpectedErrorMessage);
    try {
      return ReservaListaResponse.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const ReservaException(_unexpectedErrorMessage);
    }
  }

  /// Obtiene el detalle de una reserva (`GET /reservas/{reserva_id}`).
  Future<ReservaDetalle> obtenerReserva(int reservaId) async {
    final Object? data = await _enviar(
      'GET',
      ApiConfig.reservaDetalleUrl(reservaId),
    );
    return _detalleDesde(data);
  }

  /// Cancela una reserva PENDIENTE o CONFIRMADA
  /// (`PATCH /reservas/{reserva_id}/cancelar`).
  ///
  /// La liberación de stock la realiza el backend: la app solo envía el motivo
  /// opcional y consume la respuesta.
  Future<ReservaDetalle> cancelarReserva({
    required int reservaId,
    String? observacion,
  }) async {
    final Object? data = await _enviar(
      'PATCH',
      ApiConfig.reservaCancelarUrl(reservaId),
      mensajeConflicto: _conflictCancelMessage,
      body: <String, dynamic>{
        'observacion': _observacionOLimpiar(observacion),
      },
    );
    return _detalleDesde(data);
  }

  /// Normaliza la observación: recorta espacios, vacío → `null` y máximo 500.
  ///
  /// El backend también valida el límite; aquí solo se evita enviar ruido.
  static String? _observacionOLimpiar(String? valor) {
    final String texto = (valor ?? '').trim();
    if (texto.isEmpty) return null;
    return texto.length <= 500 ? texto : texto.substring(0, 500);
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  /// Ejecuta la petición autenticada y decodifica el JSON.
  ///
  /// Centraliza el `Authorization: Bearer`, los códigos de estado y los
  /// mensajes de error para que las páginas no manejen HTTP directamente.
  Future<Object?> _enviar(
    String metodo,
    String url, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? mensajeConflicto,
  }) async {
    _asegurarConfiguracion();
    final Map<String, String> headers = await _headers(conCuerpo: body != null);
    final Uri uri = Uri.parse(url).replace(queryParameters: query);

    final http.Response response;
    try {
      if (metodo == 'POST') {
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout);
      } else if (metodo == 'PATCH') {
        response = await _client
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout);
      } else {
        response = await _client.get(uri, headers: headers).timeout(_timeout);
      }
    } catch (_) {
      throw const ReservaException(_connectionErrorMessage);
    }

    if (response.statusCode == 200 ||
        response.statusCode == 201 ||
        response.statusCode == 204) {
      final String cuerpo = response.body.trim();
      // Toda operación de CU16 devuelve el detalle de la reserva.
      if (cuerpo.isEmpty) throw const ReservaException(_unexpectedErrorMessage);
      try {
        return jsonDecode(cuerpo);
      } catch (_) {
        throw const ReservaException(_unexpectedErrorMessage);
      }
    }

    throw _errorDesde(response, mensajeConflicto: mensajeConflicto);
  }

  /// Traduce el código de estado a un error con mensaje para el cliente.
  ReservaException _errorDesde(
    http.Response response, {
    String? mensajeConflicto,
  }) {
    switch (response.statusCode) {
      case 401:
        return const ReservaException(
          _unauthorizedMessage,
          statusCode: 401,
          unauthorized: true,
        );
      case 403:
        return const ReservaException(_forbiddenMessage, statusCode: 403);
      case 404:
        return const ReservaException(_notFoundMessage, statusCode: 404);
      case 409:
        return ReservaException(
          mensajeConflicto ?? _detalleDeError(response) ?? _conflictMessage,
          statusCode: 409,
          conflicto: true,
        );
      case 422:
        return const ReservaException(_validationMessage, statusCode: 422);
      default:
        return ReservaException(
          _unexpectedErrorMessage,
          statusCode: response.statusCode,
        );
    }
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
      throw const ReservaException(_unexpectedErrorMessage);
    }
    if (token == null || token.isEmpty) {
      throw const ReservaException(
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

  ReservaDetalle _detalleDesde(Object? data) {
    if (data is! Map) throw const ReservaException(_unexpectedErrorMessage);
    try {
      return ReservaDetalle.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const ReservaException(_unexpectedErrorMessage);
    }
  }

  void _asegurarConfiguracion() {
    if (!ApiConfig.isConfigured) {
      throw const ReservaException(ApiConfig.missingBaseUrlHint);
    }
  }
}


