// Pruebas de parsing de los modelos del catálogo CU09.
//
// Validan tolerancia a nulls (descripcion, recurso.color, sucursal.ciudad),
// listas vacías y precio entregado como number o string.

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/catalogo/models/catalogo_filtros_model.dart';
import 'package:fashionstore_mobile/features/catalogo/models/disponibilidad_model.dart';
import 'package:fashionstore_mobile/features/catalogo/models/producto_model.dart';

void main() {
  group('Producto', () {
    test('parsea precio string, categoria y descripcion null', () {
      final Producto producto = Producto.fromJson(<String, dynamic>{
        'id': 1,
        'nombre': 'Camisa Oxford',
        'descripcion': null,
        'precio': '150.50',
        'estado': true,
        'categoria_id': 3,
        'categoria': <String, dynamic>{'id': 3, 'nombre': 'Camisas'},
      });

      expect(producto.id, 1);
      expect(producto.precio, 150.50);
      expect(producto.precioFormateado, 'Bs 150.50');
      expect(producto.categoriaNombre, 'Camisas');
      expect(producto.descripcion, isNull);
      expect(producto.descripcionCorta, 'Sin descripción disponible.');
    });

    test('parsea precio numérico', () {
      final Producto producto = Producto.fromJson(<String, dynamic>{
        'id': 2,
        'nombre': 'Pantalón',
        'precio': 89,
        'categoria': <String, dynamic>{'nombre': 'Pantalones'},
      });

      expect(producto.precio, 89.0);
      expect(producto.categoriaId, 0);
    });

    test('parsea imagen_principal_url cuando viene presente', () {
      final Producto producto = Producto.fromJson(<String, dynamic>{
        'id': 1,
        'nombre': 'Polo Premium Piqué',
        'precio': '149.90',
        'categoria': <String, dynamic>{'id': 3, 'nombre': 'Polos'},
        'imagen_principal_url':
            'https://cdn.test/storage/products/1/general/model.webp',
      });

      expect(
        producto.imagenPrincipalUrl,
        'https://cdn.test/storage/products/1/general/model.webp',
      );
    });

    test('imagen_principal_url null o ausente se parsea como null', () {
      final Producto ausente = Producto.fromJson(<String, dynamic>{
        'id': 2,
        'nombre': 'Camisa',
        'precio': 100,
      });
      final Producto nula = Producto.fromJson(<String, dynamic>{
        'id': 3,
        'nombre': 'Camisa',
        'precio': 100,
        'imagen_principal_url': null,
      });
      final Producto vacia = Producto.fromJson(<String, dynamic>{
        'id': 4,
        'nombre': 'Camisa',
        'precio': 100,
        'imagen_principal_url': '   ',
      });

      expect(ausente.imagenPrincipalUrl, isNull);
      expect(nula.imagenPrincipalUrl, isNull);
      expect(vacia.imagenPrincipalUrl, isNull);
    });
  });

  group('ProductoDetalle', () {
    test('soporta recursos y variantes vacíos', () {
      final ProductoDetalle detalle =
          ProductoDetalle.fromJson(<String, dynamic>{
        'id': 5,
        'nombre': 'Chaqueta',
        'precio': 200,
        'recursos': <dynamic>[],
        'variantes': <dynamic>[],
        'categoria': <String, dynamic>{'id': 1, 'nombre': 'Chaquetas'},
      });

      expect(detalle.recursos, isEmpty);
      expect(detalle.variantes, isEmpty);
      expect(detalle.recursosUtilizables, isEmpty);
      expect(detalle.recursoPrincipal, isNull);
      expect(detalle.tallas, isEmpty);
      expect(detalle.colores, isEmpty);
    });

    test('recurso.color null y principal primero', () {
      final ProductoDetalle detalle =
          ProductoDetalle.fromJson(<String, dynamic>{
        'id': 6,
        'nombre': 'Polera',
        'precio': 120,
        'recursos': <dynamic>[
          <String, dynamic>{
            'id': 1,
            'tipo': 'imagen',
            'url': 'https://cdn.test/a.jpg',
            'es_principal': false,
            'color': null,
          },
          <String, dynamic>{
            'id': 2,
            'tipo': 'imagen',
            'url': 'https://cdn.test/b.jpg',
            'es_principal': true,
            'color': <String, dynamic>{'id': 9, 'nombre': 'Azul'},
          },
        ],
        'variantes': <dynamic>[
          <String, dynamic>{
            'id': 10,
            'sku': 'SKU-1',
            'estado': true,
            'talla': <String, dynamic>{'id': 1, 'nombre': 'M'},
            'color': <String, dynamic>{'id': 9, 'nombre': 'Azul'},
          },
        ],
        'categoria': <String, dynamic>{'id': 1, 'nombre': 'Poleras'},
      });

      expect(detalle.recursosUtilizables.length, 2);
      expect(detalle.recursoPrincipal?.id, 2);
      expect(detalle.recursosUtilizables.first.colorNombre, 'Azul');
      expect(detalle.tallas, <String>['M']);
      expect(detalle.colores, <String>['Azul']);
      expect(detalle.tallasOpciones.single.id, 1);
      expect(detalle.coloresOpciones.single.id, 9);
    });

    test('un solo recurso no falla y queda como principal', () {
      final ProductoDetalle detalle =
          ProductoDetalle.fromJson(<String, dynamic>{
        'id': 7,
        'nombre': 'Polo',
        'precio': 149.90,
        'recursos': <dynamic>[
          <String, dynamic>{
            'id': 1,
            'tipo': 'imagen',
            'url': 'https://cdn.test/model.webp',
            'es_principal': true,
            'color': null,
          },
        ],
        'variantes': <dynamic>[],
      });

      expect(detalle.recursosUtilizables.length, 1);
      expect(detalle.recursoPrincipal?.url, 'https://cdn.test/model.webp');
    });

    test('mantiene el orden del backend dentro de cada grupo', () {
      final ProductoDetalle detalle =
          ProductoDetalle.fromJson(<String, dynamic>{
        'id': 8,
        'nombre': 'Traje',
        'precio': 500,
        'recursos': <dynamic>[
          <String, dynamic>{
            'id': 10,
            'tipo': 'imagen',
            'url': 'https://cdn.test/sec-1.webp',
            'es_principal': false,
            'color': null,
          },
          <String, dynamic>{
            'id': 11,
            'tipo': 'imagen',
            'url': 'https://cdn.test/principal.webp',
            'es_principal': true,
            'color': null,
          },
          <String, dynamic>{
            'id': 12,
            'tipo': 'imagen',
            'url': 'https://cdn.test/sec-2.webp',
            'es_principal': false,
            'color': null,
          },
        ],
        'variantes': <dynamic>[],
      });

      expect(
        detalle.recursosUtilizables
            .map((RecursoProducto r) => r.url)
            .toList(),
        <String>[
          'https://cdn.test/principal.webp',
          'https://cdn.test/sec-1.webp',
          'https://cdn.test/sec-2.webp',
        ],
      );
    });

    test('galería descarta recursos no visuales y sin URL', () {
      final ProductoDetalle detalle =
          ProductoDetalle.fromJson(<String, dynamic>{
        'id': 9,
        'nombre': 'Conjunto',
        'precio': 300,
        'recursos': <dynamic>[
          <String, dynamic>{
            'id': 1,
            'tipo': 'video',
            'url': 'https://cdn.test/video.mp4',
            'es_principal': true,
            'color': null,
          },
          <String, dynamic>{
            'id': 2,
            'tipo': 'imagen',
            'url': '   ',
            'es_principal': false,
            'color': null,
          },
          <String, dynamic>{
            'id': 3,
            'tipo': 'galeria',
            'url': 'https://cdn.test/foto.webp',
            'es_principal': false,
            'color': null,
          },
        ],
        'variantes': <dynamic>[],
      });

      expect(detalle.recursosUtilizables.length, 1);
      expect(detalle.recursosUtilizables.single.url, 'https://cdn.test/foto.webp');
    });

    test('detalle parsea imagen_principal_url', () {
      final ProductoDetalle detalle =
          ProductoDetalle.fromJson(<String, dynamic>{
        'id': 10,
        'nombre': 'Blazer',
        'precio': 350,
        'imagen_principal_url': 'https://cdn.test/general/model.webp',
        'recursos': <dynamic>[],
        'variantes': <dynamic>[],
      });

      expect(detalle.imagenPrincipalUrl, 'https://cdn.test/general/model.webp');
    });
  });

  group('CatalogoFiltros', () {
    test('listas ausentes se vuelven vacías y ciudad null', () {
      final CatalogoFiltros filtros =
          CatalogoFiltros.fromJson(<String, dynamic>{
        'categorias': <dynamic>[],
        'tallas': <dynamic>[],
        'colores': <dynamic>[],
        'temporadas': <dynamic>[],
        'colecciones': <dynamic>[
          <String, dynamic>{'id': 1, 'nombre': 'Verano', 'temporada_id': 4},
        ],
        'sucursales': <dynamic>[
          <String, dynamic>{'id': 2, 'nombre': 'Central', 'ciudad': null},
        ],
      });

      expect(filtros.categorias, isEmpty);
      expect(filtros.sucursales.single.ciudad, isNull);
      expect(filtros.sucursales.single.etiqueta, 'Central');
      expect(filtros.coleccionesDe(4).single.id, 1);
      expect(filtros.coleccionesDe(9), isEmpty);
      expect(filtros.coleccionCompatible(1, 4), isTrue);
      expect(filtros.coleccionCompatible(1, 9), isFalse);
    });

    test('CatalogoFiltrosSeleccion cuenta activos y limpia', () {
      const CatalogoFiltrosSeleccion vacia = CatalogoFiltrosSeleccion();
      expect(vacia.estaVacio, isTrue);

      final CatalogoFiltrosSeleccion seleccion = vacia.copyWith(
        categoriaId: 1,
        soloConStock: true,
      );
      expect(seleccion.activos, 2);
      expect(seleccion.limpiar().estaVacio, isTrue);

      final CatalogoFiltrosSeleccion sinCategoria =
          seleccion.copyWith(categoriaId: null);
      expect(sinCategoria.categoriaId, isNull);
      expect(sinCategoria.soloConStock, isTrue);
    });
  });

  group('Disponibilidad', () {
    test('parsea stock_disponible tal como llega y listas vacías', () {
      final DisponibilidadProducto disponibilidad =
          DisponibilidadProducto.fromJson(<String, dynamic>{
        'producto_id': 7,
        'producto': 'Camisa',
        'sucursales': <dynamic>[
          <String, dynamic>{
            'sucursal_id': 1,
            'sucursal': 'Central',
            'variantes': <dynamic>[
              <String, dynamic>{
                'variante_id': 11,
                'sku': 'SKU-11',
                'talla': 'L',
                'color': 'Negro',
                'temporada': 'Invierno',
                'stock_disponible': 3,
              },
              <String, dynamic>{
                'variante_id': 12,
                'sku': 'SKU-12',
                'talla': 'M',
                'color': 'Negro',
                'temporada': 'Invierno',
                'stock_disponible': 0,
              },
            ],
          },
        ],
      });

      expect(disponibilidad.estaVacio, isFalse);
      expect(disponibilidad.totalVariantesConStock, 1);
      expect(disponibilidad.sucursales.single.variantesConStock, 1);
      expect(disponibilidad.sucursales.single.variantes.first.stockDisponible, 3);
    });

    test('sin sucursales queda vacío', () {
      final DisponibilidadProducto disponibilidad =
          DisponibilidadProducto.fromJson(<String, dynamic>{
        'producto_id': 8,
        'producto': 'Camisa',
        'sucursales': null,
      });

      expect(disponibilidad.estaVacio, isTrue);
      expect(disponibilidad.sucursales, isEmpty);
    });
  });
}
