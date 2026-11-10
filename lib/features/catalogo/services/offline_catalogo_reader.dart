import '../../../core/offline/local_database.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/storage/tenant_session.dart';
import '../models/producto_model.dart';

/// CU18: lector local de la SQLite creada por CU17. La ausencia de stock no
/// se interpreta como cero y talla/color se conserva en la misma variante.
class OfflineCatalogoReader {
  OfflineCatalogoReader({AuthStorage? storage, LocalDatabase? database}) : _storage = storage ?? AuthStorage(), _database = database ?? LocalDatabase.instance;
  final AuthStorage _storage;
  final LocalDatabase _database;

  Future<Map<String, dynamic>?> status() async {
    final session = await _storage.readSession();
    return session == null ? null : _database.cu17Status(session.empresaId, session.usuarioId, null);
  }

  Future<List<Producto>> listar({String? buscar, bool soloConStock = false}) async {
    final session = await _requireSession();
    final rows = await _database.cu18Productos(session.empresaId, session.usuarioId, null);
    final variants = await _database.cu18Variantes(session.empresaId, session.usuarioId, null);
    final stock = await _database.cu18Stock(session.empresaId, session.usuarioId, null);
    final term = (buscar ?? '').trim().toLowerCase();
    return rows.map(Producto.fromJson).where((p) {
      final pVariants = variants.where((v) => _int(v['producto_id']) == p.id).toList();
      final total = pVariants.fold<int>(0, (sum, v) => sum + stock.where((s) => _int(s['variante_id']) == _int(v['id'])).fold<int>(0, (a, s) => a + _int(s['stock_disponible_conocido'])));
      return (term.isEmpty || '${p.nombre} ${p.descripcion ?? ''} ${p.categoriaNombre}'.toLowerCase().contains(term)) && (!soloConStock || total > 0);
    }).toList()..sort((a, b) => a.nombre.compareTo(b.nombre));
  }

  Future<ProductoDetalle?> detalle(int id) async {
    final session = await _requireSession();
    final products = await _database.cu18Productos(session.empresaId, session.usuarioId, null);
    final raw = products.where((p) => _int(p['id']) == id).firstOrNull;
    if (raw == null) return null;
    final base = Producto.fromJson(raw);
    final stock = await _database.cu18Stock(session.empresaId, session.usuarioId, null);
    final variants = (await _database.cu18Variantes(session.empresaId, session.usuarioId, null)).where((v) => _int(v['producto_id']) == id).map((v) {
      final rawVariant = Map<String, dynamic>.from(v);
      rawVariant['inventarios'] = stock.where((s) => _int(s['variante_id']) == _int(v['id'])).map((s) => {'id': _int(s['variante_id']), 'stock_disponible': _int(s['stock_disponible_conocido']), 'stock_actual': _int(s['stock_disponible_conocido']), 'stock_reservado': 0, 'sucursal_id': _int(s['sucursal_id']), 'fecha_actualizacion': s['fecha_actualizacion']}).toList();
      return VarianteProducto.fromJson(rawVariant);
    }).toList();
    return ProductoDetalle(id: base.id, nombre: base.nombre, descripcion: base.descripcion, precio: base.precio, estado: base.estado, categoriaId: base.categoriaId, categoriaNombre: base.categoriaNombre, imagenPrincipalUrl: base.imagenPrincipalUrl, recursos: const [], variantes: variants);
  }

  Future<TenantSession> _requireSession() async => await _storage.readSession() ?? (throw StateError('Sesión empresarial no disponible'));
  int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
