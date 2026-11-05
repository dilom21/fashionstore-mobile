class TenantSession {
  const TenantSession({
    required this.empresaId,
    required this.usuarioId,
    required this.empresaSlug,
    required this.empresaNombre,
  });

  factory TenantSession.fromJson(Map<String, dynamic> json) => TenantSession(
    empresaId: _int(json['empresa_id']),
    usuarioId: _int(json['usuario_id']),
    empresaSlug: '${json['empresa_slug'] ?? ''}',
    empresaNombre: '${json['empresa_nombre'] ?? ''}',
  );

  final int empresaId;
  final int usuarioId;
  final String empresaSlug;
  final String empresaNombre;

  String get scopeKey => '$empresaId:$usuarioId';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'empresa_id': empresaId,
    'usuario_id': usuarioId,
    'empresa_slug': empresaSlug,
    'empresa_nombre': empresaNombre,
  };
}

int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
