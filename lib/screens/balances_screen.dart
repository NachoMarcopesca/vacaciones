import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../models/balance_adjustment.dart';
import '../models/balance_entry.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../repositories/balances_repository.dart';

class BalancesScreen extends StatefulWidget {
  final UserProfile profile;

  const BalancesScreen({super.key, required this.profile});

  @override
  State<BalancesScreen> createState() => _BalancesScreenState();
}

class _BalancesScreenState extends State<BalancesScreen> {
  late Future<List<BalanceEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = BalancesRepository.fetchBalancesList();
  }

  bool get _canEdit {
    return widget.profile.role == UserRole.adminSistema ||
        widget.profile.role == UserRole.jefe ||
        widget.profile.role == UserRole.responsable;
  }

  Future<void> _refresh() async {
    setState(() {
      _future = BalancesRepository.fetchBalancesList();
    });
  }

  Future<void> _openEdit(BalanceEntry entry) async {
    final assignedController = TextEditingController(
      text: entry.diasAsignadosAnual.toString(),
    );
    final carriedController = TextEditingController(
      text: entry.diasArrastrados.toString(),
    );
    final extraController = TextEditingController(text: '0');
    final commentController = TextEditingController();
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('Editar saldo: ${entry.displayName ?? entry.email}'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: assignedController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Dias asignados anuales',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: carriedController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Dias arrastrados',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: extraController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Anadir dias extra (puede ser negativo)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: commentController,
                      decoration: const InputDecoration(
                        labelText: 'Comentario (obligatorio si hay extra)',
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final extra = int.tryParse(extraController.text.trim()) ?? 0;
                    final comment = commentController.text.trim();
                    if (extra != 0 && comment.isEmpty) {
                      setStateDialog(() {
                        errorText = 'Escribe el comentario para los dias extra.';
                      });
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) {
      assignedController.dispose();
      carriedController.dispose();
      extraController.dispose();
      commentController.dispose();
      return;
    }

    int? parseInt(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return int.tryParse(trimmed);
    }

    final assigned = parseInt(assignedController.text);
    final carried = parseInt(carriedController.text);
    final extra = parseInt(extraController.text) ?? 0;
    final comment = commentController.text.trim();

    assignedController.dispose();
    carriedController.dispose();
    extraController.dispose();
    commentController.dispose();

    await BalancesRepository.adjustBalance(
      userId: entry.userId,
      diasAsignadosAnual: assigned,
      diasArrastrados: carried,
      deltaExtra: extra,
      comentario: comment.isEmpty ? null : comment,
    );

    await _refresh();
  }

  Future<void> _openExtras(BalanceEntry entry) async {
    final title = entry.displayName?.isNotEmpty == true
        ? entry.displayName!
        : entry.email;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Extras: $title'),
          content: SizedBox(
            width: 380,
            child: FutureBuilder<List<BalanceAdjustment>>(
              future: BalancesRepository.fetchAdjustments(entry.userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                final items = snapshot.data ?? [];
                final extras =
                    items.where((item) => item.deltaExtra != 0).toList();
                if (extras.isEmpty) {
                  return const Text('No hay extras registrados.');
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: extras.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final item = extras[index];
                    final date = item.createdAt != null
                        ? DateFormat('dd/MM/yyyy')
                            .format(DateTime.parse(item.createdAt!))
                        : '-';
                    final delta =
                        '${item.deltaExtra >= 0 ? '+' : ''}${item.deltaExtra}';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$date · $delta dias',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if ((item.comentario ?? '').isNotEmpty)
                          Text(item.comentario!),
                        if ((item.createdBy ?? '').isNotEmpty)
                          Text(
                            'Por: ${item.createdBy}',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saldos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<BalanceEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('No hay empleados.'));
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final entry = items[index];
              final title = entry.displayName?.isNotEmpty == true
                  ? entry.displayName!
                  : entry.email;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.departamentoId != null)
                        Text('Departamento: ${entry.departamentoId}'),
                      Text(
                        'Asignados: ${entry.diasAsignadosAnual} · Arrastrados: ${entry.diasArrastrados} · Extra: ${entry.diasExtra} · Consumidos: ${entry.diasConsumidos}',
                      ),
                    ],
                  ),
                  onTap: () => _openExtras(entry),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${entry.diasDisponibles}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_canEdit)
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openEdit(entry),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
