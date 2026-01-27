import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/vacation_request.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../repositories/requests_repository.dart';
import 'calendar_screen.dart';
import 'request_form_screen.dart';

class RequestsListScreen extends StatefulWidget {
  final UserProfile profile;

  const RequestsListScreen({super.key, required this.profile});

  @override
  State<RequestsListScreen> createState() => _RequestsListScreenState();
}

class _RequestsListScreenState extends State<RequestsListScreen> {
  late Future<List<VacationRequest>> _future;
  String _filterStatus = 'pendiente';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<VacationRequest>> _load() {
    return RequestsRepository.fetchRequests(status: _filterStatus);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
  }

  String _formatRange(VacationRequest request) {
    final start = request.fechaInicioStr ?? '-';
    final end = request.fechaFinStr ?? '-';
    return '$start → $end';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'aprobada':
        return Colors.green;
      case 'rechazada':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  bool get _canCreate => widget.profile.role == UserRole.empleado;

  bool _canApprove(UserRole role) {
    return role == UserRole.admin ||
        role == UserRole.responsable ||
        role == UserRole.responsableGeneral;
  }

  @override
  Widget build(BuildContext context) {
    final bool canApprove =
        widget.profile.role == UserRole.admin ||
        widget.profile.role == UserRole.responsable ||
        widget.profile.role == UserRole.responsableGeneral;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitudes'),
        actions: [
          if (canApprove)
            IconButton(
              tooltip: 'Calendario',
              icon: const Icon(Icons.calendar_month),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CalendarScreen(
                      profile: widget.profile,
                      includePending: true,
                      title: 'Calendario de solicitudes',
                    ),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: _canCreate
          ? FloatingActionButton(
              onPressed: () async {
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RequestFormScreen(profile: widget.profile),
                  ),
                );
                if (created == true) {
                  _refresh();
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text('Estado:'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _filterStatus,
                  items: const [
                    DropdownMenuItem(
                      value: 'pendiente',
                      child: Text('Pendientes'),
                    ),
                    DropdownMenuItem(
                      value: 'aprobada',
                      child: Text('Aprobadas'),
                    ),
                    DropdownMenuItem(
                      value: 'rechazada',
                      child: Text('Rechazadas'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _filterStatus = value;
                      _future = _load();
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<VacationRequest>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No hay solicitudes.'),
                  );
                }

                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final request = items[index];
                    final subtitle = _formatRange(request);
                    final statusColor = _statusColor(request.estado);
                    final bool isPending = request.estado == 'pendiente';
                    final days =
                        isPending ? request.diasEstimados : request.diasConsumidos;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        title: Text(subtitle),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.profile.role != UserRole.empleado &&
                                ((request.userDisplayName ?? '').isNotEmpty ||
                                    (request.userEmail ?? '').isNotEmpty))
                              Text(
                                request.userDisplayName?.isNotEmpty == true
                                    ? request.userDisplayName!
                                    : (request.userEmail ?? ''),
                                style: const TextStyle(fontSize: 12),
                              ),
                            Text(
                              request.notas?.isNotEmpty == true
                                  ? request.notas!
                                  : 'Sin notas',
                            ),
                          ],
                        ),
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.15),
                          child: Text(
                            request.estado.substring(0, 1).toUpperCase(),
                            style: TextStyle(color: statusColor),
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              request.estado.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (days > 0)
                              Text(
                                isPending ? '$days dias (est.)' : '$days dias',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                        onTap: () async {
                          final updated = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _RequestDetailScreen(
                                profile: widget.profile,
                                request: request,
                                canApprove: _canApprove(widget.profile.role),
                              ),
                            ),
                          );
                          if (updated == true) {
                            _refresh();
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestDetailScreen extends StatelessWidget {
  final UserProfile profile;
  final VacationRequest request;
  final bool canApprove;

  const _RequestDetailScreen({
    required this.profile,
    required this.request,
    required this.canApprove,
  });

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return dateStr;
    return DateFormat('dd/MM/yyyy').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final status = request.estado;
    final statusColor = status == 'aprobada'
        ? Colors.green
        : status == 'rechazada'
            ? Colors.red
            : Colors.orange;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle solicitud'),
        actions: [
          if (profile.role == UserRole.empleado)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RequestFormScreen(
                      profile: profile,
                      existing: request,
                    ),
                  ),
                );
                if (updated == true && context.mounted) {
                  Navigator.pop(context, true);
                }
              },
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estado: ${request.estado.toUpperCase()}',
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text('Desde: ${_formatDate(request.fechaInicioStr)}'),
            Text('Hasta: ${_formatDate(request.fechaFinStr)}'),
            const SizedBox(height: 12),
            if (request.estado == 'pendiente')
              Text('Dias estimados: ${request.diasEstimados}'),
            if (request.estado != 'pendiente')
              Text('Dias consumidos: ${request.diasConsumidos}'),
            const SizedBox(height: 12),
            Text('Notas: ${request.notas ?? '-'}'),
            const SizedBox(height: 24),
            if (canApprove && request.estado == 'pendiente')
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () async {
                        await RequestsRepository.approveRequest(request.id);
                        if (context.mounted) {
                          Navigator.pop(context, true);
                        }
                      },
                      child: const Text('Aprobar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () async {
                        await RequestsRepository.rejectRequest(request.id);
                        if (context.mounted) {
                          Navigator.pop(context, true);
                        }
                      },
                      child: const Text('Rechazar'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
