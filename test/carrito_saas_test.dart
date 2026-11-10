import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fashionstore_mobile/core/storage/auth_storage.dart';
import 'package:fashionstore_mobile/core/storage/tenant_session.dart';
import 'package:fashionstore_mobile/features/carrito/models/carrito_model.dart';
import 'package:fashionstore_mobile/features/carrito/services/carrito_service.dart';

class _Storage extends AuthStorage {
  _Storage(this.token);

  final String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<TenantSession?> readSession() async => const TenantSession(
    empresaId: 2,
    usuarioId: 7,
    empresaSlug: 'acme',
    empresaNombre: 'Acme',
  );
}

Map<String, dynamic> _detail() => <String, dynamic>{
  'carrito_id': 45,
  'sucursal_id': 2,
  'sucursal_nombre': 'Centro',
  'estado': 'ACTIVO',
  'fecha_creacion': '2026-11-10T10:00:00',
  'fecha_actualizacion': '2026-11-10T10:05:00',
  'items': <dynamic>[
    <String, dynamic>{
      'detalle_id': 1,
      'inventario_id': 44,
      'producto_id': 9,
      'producto_nombre': 'Camisa',
      'imagen_principal_url': 'https://cdn/camisa.jpg',
      'precio_unitario': '149.90',
      'variante_producto_id': 7,
      'sku': 'SKU-1',
      'talla_id': 1,
      'talla_nombre': 'M',
      'color_id': 3,
      'color_nombre': 'Negro',
      'temporada_id': 2,
      'temporada_nombre': 'Verano',
      'cantidad': 2,
      'stock_disponible': 5,
      'subtotal_linea': '299.80',
    },
  ],
  'cantidad_total_unidades': 2,
  'subtotal_carrito': '299.80',
};

void main() {
  test('agrega con variante + temporada y refresca el detalle', () async {
    late http.Request post;
    final http.Client client = MockClient((http.Request request) async {
      if (request.method == 'POST') {
        post = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'carrito_id': 45,
            'detalle_id': 1,
            'inventario_id': 44,
            'cantidad': 2,
            'estado': 'ACTIVO',
          }),
          200,
        );
      }
      expect(request.url.path, '/tenant/carritos/45');
      return http.Response(jsonEncode(_detail()), 200);
    });

    final CarritoDetalle carrito =
        await CarritoService(
          client: client,
          storage: _Storage('jwt'),
          baseUrl: 'http://test.local',
        ).agregarItemVariante(
          sucursalId: 2,
          varianteProductoId: 7,
          temporadaId: 4,
          cantidad: 2,
        );

    expect(post.url.path, '/tenant/carritos/items');
    expect(post.headers['Authorization'], 'Bearer jwt');
    expect(jsonDecode(post.body), <String, dynamic>{
      'sucursal_id': 2,
      'variante_producto_id': 7,
      'temporada_id': 4,
      'cantidad': 2,
    });
    expect(carrito.items.single.imagenPrincipal, 'https://cdn/camisa.jpg');
    expect(carrito.items.single.stockDisponible, 5);
  });

  test('lista, actualiza y elimina líneas con los contratos SaaS', () async {
    final List<String> paths = <String>[];
    final http.Client client = MockClient((http.Request request) async {
      paths.add('${request.method} ${request.url.path}');
      if (request.url.path == '/tenant/carritos') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'items': <dynamic>[
              <String, dynamic>{
                'carrito_id': 45,
                'sucursal_id': 2,
                'sucursal_nombre': 'Centro',
                'cantidad_lineas': 1,
                'cantidad_unidades': 2,
                'subtotal': '299.80',
                'fecha_actualizacion': '2026-11-10T10:05:00',
              },
            ],
            'total_carritos_activos': 1,
          }),
          200,
        );
      }
      if (request.method == 'PATCH') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'carrito_id': 45,
            'detalle_id': 1,
            'inventario_id': 44,
            'cantidad': 3,
            'estado': 'ACTIVO',
          }),
          200,
        );
      }
      if (request.method == 'DELETE') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'carrito_id': 45,
            'estado': 'ACTIVO',
            'cantidad_lineas': 0,
          }),
          200,
        );
      }
      return http.Response(jsonEncode(_detail()), 200);
    });

    final CarritoService service = CarritoService(
      client: client,
      storage: _Storage('jwt'),
      baseUrl: 'http://test.local',
    );

    expect((await service.listarCarritos()).totalCarritosActivos, 1);
    expect(
      (await service.actualizarCantidad(
        carritoId: 45,
        detalleId: 1,
        cantidad: 3,
      )).items.single.cantidad,
      2,
    );
    await service.eliminarItem(carritoId: 45, detalleId: 1);

    expect(paths, contains('GET /tenant/carritos'));
    expect(paths, contains('PATCH /tenant/carritos/45/items/1'));
    expect(paths, contains('DELETE /tenant/carritos/45/items/1'));
  });

  test('403 de otra empresa se reporta como acceso denegado', () async {
    final http.Client client = MockClient(
      (http.Request request) async => http.Response('{}', 403),
    );

    await expectLater(
      CarritoService(
        client: client,
        storage: _Storage('jwt'),
        baseUrl: 'http://test.local',
      ).obtenerCarrito(45),
      throwsA(
        isA<CarritoException>()
            .having((CarritoException e) => e.statusCode, 'status', 403)
            .having(
              (CarritoException e) => e.message,
              'message',
              contains('No tienes acceso'),
            ),
      ),
    );
  });

  test('409 de stock conserva el mensaje de negocio', () async {
    final http.Client client = MockClient(
      (http.Request request) async => http.Response(
        jsonEncode(<String, dynamic>{
          'detail': 'Stock insuficiente para la cantidad solicitada',
        }),
        409,
      ),
    );

    await expectLater(
      CarritoService(
        client: client,
        storage: _Storage('jwt'),
        baseUrl: 'http://test.local',
      ).agregarItemVariante(
        sucursalId: 2,
        varianteProductoId: 7,
        temporadaId: 4,
        cantidad: 99,
      ),
      throwsA(
        isA<CarritoException>()
            .having((CarritoException e) => e.conflicto, 'conflicto', isTrue)
            .having(
              (CarritoException e) => e.message,
              'message',
              contains('Stock'),
            ),
      ),
    );
  });
}
