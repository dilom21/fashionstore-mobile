import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/catalogo/services/offline_snapshot_service.dart';

void main() {
  test('CU17 adapta el contrato paginado real de inventario', () {
    final rows = OfflineSnapshotService.inventoryRows(<String, dynamic>{
      'items': <dynamic>[
        <String, dynamic>{
          'sucursal_id': 2,
          'variante_producto_id': 8,
          'stock_disponible': 3,
          'fecha_actualizacion': '2026-11-09T10:00:00Z',
        },
      ],
      'total': 1,
      'limit': 100,
      'offset': 0,
    });

    expect(rows, <Map<String, dynamic>>[
      <String, dynamic>{
        'sucursal_id': 2,
        'variante_id': 8,
        'stock_disponible_conocido': 3,
        'fecha_actualizacion': '2026-11-09T10:00:00Z',
      },
    ]);
  });

  test('CU17 descarta filas sin claves referenciales válidas', () {
    expect(
      OfflineSnapshotService.inventoryRows(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'sucursal_id': 0, 'variante_producto_id': 8},
          <String, dynamic>{'sucursal_id': 2, 'variante_producto_id': 0},
        ],
      }),
      isEmpty,
    );
  });
}
