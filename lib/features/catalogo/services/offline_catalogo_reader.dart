import '../../../core/offline/local_database.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/storage/tenant_session.dart';
import '../models/disponibilidad_model.dart';
import '../models/producto_model.dart';

/// CU18: lector local de la SQLite creada por CU17.
///
/// La ausencia de stock no se interpreta como cero y talla/color se conserva
/// en la misma variante. El stock mostrado es el ÚLTIMO CONOCIDO descargado.
class OfflineCatalogoReader {
  OfflineCatalogoReader({AuthStorage? storage, LocalDatabase? database})
    : _storage = storage ?? AuthStorage(),
      _database = database ?? LocalDatabase.instance;

  final AuthStorage _storage;
  final LocalDatabase _database;

  Future<Map<String, dynamic>?> status() async {
    final TenantSession? session = await _storage.readSession();
    if (session == null) return null;
    return _database.cu17Status(session.empresaId, session.usuarioId, null);
  }

  Future<List<Producto>> listar({
    String? buscar,
    bool soloConStock = false,
  }) async {
    final TenantSession session = await _requireSession();
    final List<Map<String, dynamic>> rows = await _database.cu18Productos(
      session.empresaId,
      session.usuarioId,
      null,
    );
    final List<Map<String, dynamic>> variants = await _database.cu18Variantes(
      session.empresaId,
      session.usuarioId,
      null,
    );
    final List<Map<String, dynamic>> stock = await _database.cu18Stock(
      session.empresaId,
      session.usuarioId,
      null,
    );
    final String term = (buscar ?? '').trim().toLowerCase();

    return rows.map(Producto.fromJson).where((Producto p) {
      final List<Map<String, dynamic>> pVariants = variants
          .where((Map<String, dynamic> v) => _int(v['producto_id']) == p.id)
          .toList();
      final int total = pVariants.fold<int>(
        0,
        (int sum, Map<String, dynamic> v) =>
            sum +
            stock
                .where(
                  (Map<String, dynamic> s) =>
                      _int(s['variante_id']) == _int(v['id']),
                )
                .fold<int>(
                  0,
                  (int a, Map<String, dynamic> s) =>
                      a + _int(s['stock_disponible_conocido']),
                ),
      );
      final String searchable =
          '${p.nombre} ${p.descripcion ?? ''} ${p.categoriaNombre}'
              .toLowerCase();
      return (term.isEmpty || searchable.contains(term)) &&
          (!soloConStock || total > 0);
    }).toList()..sort((Producto a, Producto b) => a.nombre.compareTo(b.nombre));
  }

  Future<ProductoDetalle?> detalle(int id) async {
    final TenantSession session = await _requireSession();
    final List<Map<String, dynamic>> products = await _database.cu18Productos(
      session.empresaId,
      session.usuarioId,
      null,
    );
    final Map<String, dynamic>? raw = products
        .where((Map<String, dynamic> p) => _int(p['id']) == id)
        .firstOrNull;
    if (raw == null) return null;

    final Producto base = Producto.fromJson(raw);
    final List<Map<String, dynamic>> stock = await _database.cu18Stock(
      session.empresaId,
      session.usuarioId,
      null,
    );
    final List<Map<String, dynamic>> rawVariants =
        (await _database.cu18Variantes(
              session.empresaId,
              session.usuarioId,
              null,
            ))
            .where((Map<String, dynamic> v) => _int(v['producto_id']) == id)
            .toList();

    final List<VarianteProducto> variants = <VarianteProducto>[];
    final List<DisponibilidadVariante> disponibilidad =
        <DisponibilidadVariante>[];
    for (final Map<String, dynamic> v in rawVariants) {
      final int variantId = _int(v['id']);
      final List<Map<String, dynamic>> variantStock = stock
          .where(
            (Map<String, dynamic> s) => _int(s['variante_id']) == variantId,
          )
          .toList();
      final Map<String, dynamic> rawVariant = Map<String, dynamic>.from(v);
      rawVariant['inventarios'] = variantStock
          .map(
            (Map<String, dynamic> s) => <String, dynamic>{
              'id': variantId,
              'stock_disponible': _int(s['stock_disponible_conocido']),
              'stock_actual': _int(s['stock_disponible_conocido']),
              'stock_reservado': 0,
              'sucursal_id': _int(s['sucursal_id']),
              'fecha_actualizacion': s['fecha_actualizacion'],
            },
          )
          .toList();
      final VarianteProducto variante = VarianteProducto.fromJson(rawVariant);
      variants.add(variante);
      for (final Map<String, dynamic> s in variantStock) {
        disponibilidad.add(
          DisponibilidadVariante(
            varianteId: variantId,
            sku: variante.sku,
            talla: variante.tallaNombre,
            color: variante.colorNombre,
            temporada: '',
            stockDisponible: _int(s['stock_disponible_conocido']),
            sucursalId: _int(s['sucursal_id']),
            sucursal: 'Sucursal ${_int(s['sucursal_id'])}',
          ),
        );
      }
    }

    return ProductoDetalle(
      id: base.id,
      nombre: base.nombre,
      descripcion: base.descripcion,
      precio: base.precio,
      estado: base.estado,
      categoriaId: base.categoriaId,
      categoriaNombre: base.categoriaNombre,
      imagenPrincipalUrl: base.imagenPrincipalUrl,
      precioDefinitivo: base.precioDefinitivo,
      precioCalculoPendiente: base.precioCalculoPendiente,
      recursos: const <RecursoProducto>[],
      variantes: variants,
      disponibilidad: disponibilidad,
    );
  }

  Future<TenantSession> _requireSession() async =>
      await _storage.readSession() ??
      (throw StateError('Sesión empresarial no disponible'));

  int _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
