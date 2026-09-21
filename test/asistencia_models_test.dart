// Pruebas de los modelos de Asistencia Inteligente.
//
// Verifican el parsing defensivo del contrato JSON del backend y la lógica de
// "puede agregarse directo" (inventario/sucursal resueltos).

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/asistencia_inteligente/models/asistencia_models.dart';

void main() {
  group('RecomendacionProducto.fromJson', () {
    test('parsea una recomendación resuelta completa', () {
      final RecomendacionProducto rec = RecomendacionProducto.fromJson(
        <String, dynamic>{
          'producto_id': 1,
          'nombre': 'Polo Premium Piqué',
          'precio': '149.90',
          'imagen_url': 'https://cdn.test/model.webp',
          'categoria': 'Polos',
          'variante_id': 10,
          'talla': 'M',
          'color': 'Negro',
          'inventario_id': 23,
          'sucursal_id': 1,
          'sucursal': 'Sucursal Centro',
          'temporada': 'Primavera-Verano 2026',
          'stock_disponible': 10,
          'motivo': 'Versátil para oficina',
          'requiere_seleccion': false,
        },
      );

      expect(rec.productoId, 1);
      expect(rec.nombre, 'Polo Premium Piqué');
      expect(rec.precio, 149.90);
      expect(rec.precioFormateado, 'Bs 149.90');
      expect(rec.tieneImagen, isTrue);
      expect(rec.talla, 'M');
      expect(rec.color, 'Negro');
      expect(rec.inventarioId, 23);
      expect(rec.sucursalId, 1);
      expect(rec.stockDisponible, 10);
      expect(rec.stockEtiqueta, 'Stock: 10');
      expect(rec.requiereSeleccion, isFalse);
      expect(rec.puedeAgregarDirecto, isTrue);
    });

    test('parsea requiere_seleccion con inventario null', () {
      final RecomendacionProducto rec = RecomendacionProducto.fromJson(
        <String, dynamic>{
          'producto_id': 2,
          'nombre': 'Camisa',
          'precio': 99.5,
          'categoria': 'Camisas',
          'inventario_id': null,
          'sucursal_id': null,
          'stock_disponible': 4,
          'motivo': 'Buena opción',
          'requiere_seleccion': true,
        },
      );

      expect(rec.requiereSeleccion, isTrue);
      expect(rec.inventarioId, isNull);
      expect(rec.sucursalId, isNull);
      expect(rec.puedeAgregarDirecto, isFalse);
      expect(rec.tieneImagen, isFalse);
      expect(rec.motivoTexto, 'Buena opción');
    });

    test('tolera tipos string/num y campos faltantes', () {
      final RecomendacionProducto rec = RecomendacionProducto.fromJson(
        <String, dynamic>{
          'producto_id': '7',
          'nombre': 'Pantalón',
          'precio': 80,
          'stock_disponible': '3',
          'requiere_seleccion': 'true',
          'inventario_id': '23',
          'sucursal_id': '1',
        },
      );

      expect(rec.productoId, 7);
      expect(rec.precio, 80.0);
      expect(rec.stockDisponible, 3);
      expect(rec.requiereSeleccion, isTrue);
      expect(rec.inventarioId, 23);
      expect(rec.puedeAgregarDirecto, isFalse);
    });

    test('motivo vacío usa el texto por defecto', () {
      final RecomendacionProducto rec = RecomendacionProducto.fromJson(
        <String, dynamic>{'producto_id': 1, 'nombre': 'X', 'motivo': '  '},
      );
      expect(rec.motivoTexto, 'Recomendado para ti.');
    });
  });

  group('RecomendacionesResponse.fromJson', () {
    test('parsea título, descripción y lista', () {
      final RecomendacionesResponse resp = RecomendacionesResponse.fromJson(
        <String, dynamic>{
          'titulo': 'Look casual premium',
          'descripcion': 'Una selección versátil.',
          'recomendaciones': <dynamic>[
            <String, dynamic>{
              'producto_id': 1,
              'nombre': 'Polo',
              'precio': '149.90',
              'stock_disponible': 5,
              'requiere_seleccion': false,
              'inventario_id': 23,
              'sucursal_id': 1,
            },
          ],
        },
      );

      expect(resp.titulo, 'Look casual premium');
      expect(resp.descripcion, 'Una selección versátil.');
      expect(resp.estaVacio, isFalse);
      expect(resp.recomendaciones, hasLength(1));
    });

    test('lista ausente queda vacía', () {
      final RecomendacionesResponse resp = RecomendacionesResponse.fromJson(
        <String, dynamic>{'titulo': 'Sin resultados', 'descripcion': 'Nada'},
      );
      expect(resp.estaVacio, isTrue);
    });

    test('ignora elementos que no son mapas', () {
      final RecomendacionesResponse resp = RecomendacionesResponse.fromJson(
        <String, dynamic>{
          'recomendaciones': <dynamic>[
            123,
            'texto',
            <String, dynamic>{
              'producto_id': 1,
              'nombre': 'Polo',
              'precio': '10.00',
              'stock_disponible': 1,
              'requiere_seleccion': false,
            },
          ],
        },
      );
      expect(resp.recomendaciones, hasLength(1));
    });
  });
}
