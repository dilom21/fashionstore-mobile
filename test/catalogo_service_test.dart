// Pruebas de los parámetros de filtros de `GET /productos` (CU09).
//
// Verifican que la construcción de query params se mantiene igual tras la
// mejora visual de imágenes, sin necesidad de red ni de API_BASE_URL.

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/catalogo/services/catalogo_service.dart';

void main() {
  group('CatalogoService.construirQueryProductos', () {
    test('sin filtros devuelve un mapa vacío', () {
      expect(CatalogoService.construirQueryProductos(), isEmpty);
    });

    test('arma todos los parámetros de filtros actuales', () {
      final Map<String, String> query =
          CatalogoService.construirQueryProductos(
        buscar: '  polo  ',
        categoriaId: 3,
        tallaId: 5,
        colorId: 7,
        temporadaId: 2,
        coleccionId: 4,
        sucursalId: 1,
        conStock: true,
      );

      expect(query, <String, String>{
        'buscar': 'polo',
        'categoria_id': '3',
        'talla_id': '5',
        'color_id': '7',
        'temporada_id': '2',
        'coleccion_id': '4',
        'sucursal_id': '1',
        'con_stock': 'true',
      });
    });

    test('con_stock false se envía explícitamente', () {
      expect(
        CatalogoService.construirQueryProductos(conStock: false),
        <String, String>{'con_stock': 'false'},
      );
    });

    test('búsqueda vacía no agrega el parámetro buscar', () {
      expect(
        CatalogoService.construirQueryProductos(buscar: '   '),
        isEmpty,
      );
    });

    test('filtros nulos no se agregan', () {
      expect(
        CatalogoService.construirQueryProductos(categoriaId: null, tallaId: null),
        isEmpty,
      );
    });
  });
}
