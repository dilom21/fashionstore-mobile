import 'package:flutter/material.dart';

import '../../../core/offline/offline_operation.dart';
import '../../../core/theme/app_colors.dart';
import '../services/offline_operations_reader.dart';

class OfflineOperationsPage extends StatefulWidget {
  const OfflineOperationsPage({super.key});

  @override
  State<OfflineOperationsPage> createState() => _OfflineOperationsPageState();
}

class _OfflineOperationsPageState extends State<OfflineOperationsPage> {
  final OfflineOperationsReader _reader = OfflineOperationsReader();
  OfflineOperationStatus? _filter;
  late Future<List<OfflineOperation>> _operations;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _operations = _reader.read(status: _filter);
  }

  String _status(OfflineOperationStatus value) => switch (value) {
    OfflineOperationStatus.pendiente => 'Pendiente',
    OfflineOperationStatus.enviado => 'En envío local',
    OfflineOperationStatus.confirmado => 'Confirmado local',
    OfflineOperationStatus.conflicto => 'Conflicto local',
    OfflineOperationStatus.error => 'Error local',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: const Text('Operaciones locales'),
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
    ),
    body: FutureBuilder<List<OfflineOperation>>(
      future: _operations,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('No se pudo leer la cola local.'));
        }
        final operations = snapshot.data ?? const <OfflineOperation>[];
        return RefreshIndicator(
          onRefresh: () async => setState(_reload),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _warning(),
              const SizedBox(height: 12),
              DropdownButtonFormField<OfflineOperationStatus?>(
                    initialValue: _filter,
                decoration: const InputDecoration(labelText: 'Filtrar estado'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ...OfflineOperationStatus.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_status(value)),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _filter = value;
                  _reload();
                }),
              ),
              const SizedBox(height: 12),
              if (operations.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No hay operaciones guardadas para esta empresa y usuario.',
                    ),
                  ),
                )
              else
                ...operations.map(_operationCard),
            ],
          ),
        );
      },
    ),
  );

  Widget _warning() => Card(
    color: AppColors.primary.withValues(alpha: .08),
    child: const Padding(
      padding: EdgeInsets.all(14),
      child: Text(
        'Operaciones guardadas localmente; sincronización comercial deshabilitada hasta aprobación del backend.',
      ),
    ),
  );

  Widget _operationCard(OfflineOperation operation) => Card(
    child: ListTile(
      title: Text(operation.type),
      subtitle: Text(
        '${_status(operation.status)} · ${operation.createdAt.toLocal()}\nIntentos: ${operation.attempts}',
      ),
      isThreeLine: true,
      trailing: operation.lastError == null
          ? null
          : const Icon(Icons.info_outline),
    ),
  );
}
