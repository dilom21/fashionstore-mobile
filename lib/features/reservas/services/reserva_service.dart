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

/// Resultado real de `POST /tenant/reservas`.
class ReservaCreada {
  const ReservaCreada({
    required this.reservaId,
    required this.carritoId,
    required this.estado,
  });

  factory ReservaCreada.fromJson(Map<String, dynamic> json) => ReservaCreada(
    reservaId: _toInt(json['reserva_id']),
    carritoId: _toInt(json['carrito_id']),
    estado: _toString(json['estado']),
  );

  final int reservaId;
  final int carritoId;
  final String estado;
}

/// Resultado real de `PATCH /tenant/reservas/{id}/cancelar`.
class ReservaEstado {
  const ReservaEstado({required this.reservaId, required this.estado});

  factory ReservaEstado.fromJson(Map<String, dynamic> json) => ReservaEstado(
    reservaId: _toInt(json['reserva_id']),
    estado: _toString(json['estado']),
  );

  final int reservaId;
  final String estado;
}

/// Servicio de reservas ONLINE del CLIENTE (CU16 SaaS).
///
/// Endpoints consumidos (JWT de contexto cliente):
///   POST  /tenant/reservas
///   GET   /tenant/reservas
///   GET   /tenant/reservas/{reserva_id}
///   PATCH /tenant/reservas/{reserva_id}/cancelar
///
/// El backend obtiene cliente/empresa del JWT. No existe sincronización
/// offline de reservas: un fallo de red NUNCA se presenta como confirmación.
class ReservaService {
  ReservaService({AuthStorage? storage, http.Client? client, String? baseUrl})
    : _storage = storage ?? AuthStorage(),
      _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).trim();

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
  static const String _conflictCancelMessage =
      'Esta reserva ya no puede cancelarse.';

  final AuthStorage _storage;
  final http.Client _client;
  final String _baseUrl;

  /// Crea una reserva a partir de un carrito ACTIVO.
  Future<ReservaCreada> crearReserva({
    required int carritoId,
    required DateTime fechaAtencion,
    String? observacion,
  }) async {
    final Object? data = await _enviar(
      'POST',
      '$_baseUrl/tenant/reservas',
      mensajeConflicto: _conflictStockMessage,
      body: <String, dynamic>{
        'carrito_id': carritoId,
        // El contrato SaaS exige datetime con zona horaria.
        'fecha_atencion': formatearIsoConZona(fechaAtencion),
        'observacion': _observacionOLimpiar(observacion),
      },
    );
    if (data is! Map) throw const ReservaException(_unexpectedErrorMessage);
    return ReservaCreada.fromJson(data.cast<String, dynamic>());
  }

  /// Lista las reservas del cliente con paginación real.
  Future<ReservaListaResponse> listarReservas({
    String? estado,
    int limit = 20,
    int offset = 0,
  }) async {
    final String filtro = (estado ?? '').trim().toUpperCase();
    final Object? data = await _enviar(
      'GET',
      '$_baseUrl/tenant/reservas',
      query: <String, String>{
        if (filtro.isNotEmpty) 'estado': filtro,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    if (data is! Map) throw const ReservaException(_unexpectedErrorMessage);
    try {
      return ReservaListaResponse.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const ReservaException(_unexpectedErrorMessage);
    }
  }

  /// Obtiene el detalle real de una reserva.
  Future<ReservaDetalle> obtenerReserva(int reservaId) async {
    if (reservaId <= 0) {
      throw const ReservaException(_notFoundMessage, statusCode: 404);
    }
    final Object? data = await _enviar(
      'GET',
      '$_baseUrl/tenant/reservas/$reservaId',
    );
    if (data is! Map) throw const ReservaException(_unexpectedErrorMessage);
    try {
      return ReservaDetalle.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const ReservaException(_unexpectedErrorMessage);
    }
  }

  /// Cancela una reserva PENDIENTE o CONFIRMADA.
  Future<ReservaEstado> cancelarReserva({
    required int reservaId,
    String? observacion,
  }) async {
    final Object? data = await _enviar(
      'PATCH',
      '$_baseUrl/tenant/reservas/$reservaId/cancelar',
      mensajeConflicto: _conflictCancelMessage,
      body: <String, dynamic>{'observacion': _observacionOLimpiar(observacion)},
    );
    if (data is! Map) throw const ReservaException(_unexpectedErrorMessage);
    return ReservaEstado.fromJson(data.cast<String, dynamic>());
  }

  static String? _observacionOLimpiar(String? valor) {
    final String texto = (valor ?? '').trim();
    if (texto.isEmpty) return null;
    return texto.length <= 500 ? texto : texto.substring(0, 500);
  }

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
      if (cuerpo.isEmpty) throw const ReservaException(_unexpectedErrorMessage);
      try {
        return jsonDecode(cuerpo);
      } catch (_) {
        throw const ReservaException(_unexpectedErrorMessage);
      }
    }

    throw _errorDesde(response, mensajeConflicto: mensajeConflicto);
  }

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

  void _asegurarConfiguracion() {
    if (_baseUrl.isEmpty) {
      throw const ReservaException(ApiConfig.missingBaseUrlHint);
    }
  }
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String _toString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}
