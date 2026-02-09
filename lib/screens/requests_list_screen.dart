import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/department.dart';
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
  List<Department> _departments = [];
  bool _loadingDepartments = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadDepartments();
  }

  Future<List<VacationRequest>> _load() {
    return RequestsRepository.fetchRequests(status: _filterStatus);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _loadDepartments() async {
    if (widget.profile.role == UserRole.empleado) return;
    setState(() => _loadingDepartments = true);
    try {
      final items = await RequestsRepository.fetchDepartments();
      setState(() {
        _departments = items;
      });
    } catch (_) {
      // Ignore; fallback to IDs.
    } finally {
      if (mounted) {
        setState(() => _loadingDepartments = false);
      }
    }
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

  bool get _canCreate => true;

  bool _canApproveRequest(VacationRequest request) {
    if (widget.profile.role == UserRole.adminSistema) {
      return false;
    }
    if (request.userId == widget.profile.uid &&
        widget.profile.role != UserRole.jefe) {
      return false;
    }
    if (widget.profile.role == UserRole.jefe) {
      return true;
    }
    if (widget.profile.role == UserRole.responsable) {
      final requesterRole =
          parseUserRole(request.userRole ?? 'empleado');
      if (requesterRole == UserRole.responsable ||
          requesterRole == UserRole.jefe ||
          requesterRole == UserRole.adminSistema) {
        return false;
      }
      return request.departamentoId != null &&
          widget.profile.departamentoId != null &&
          request.departamentoId == widget.profile.departamentoId;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bool canSeeCalendar =
        widget.profile.role != UserRole.empleado;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitudes'),
        actions: [
          if (canSeeCalendar)
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

                final own = items
                    .where((request) => request.userId == widget.profile.uid)
                    .toList();
                final others = items
                    .where((request) => request.userId != widget.profile.uid)
                    .toList();

                if (widget.profile.role == UserRole.empleado) {
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      ...own.map(_buildRequestCard),
                    ],
                  );
                }

                final deptNameById = {
                  for (final dept in _departments) dept.id: dept.name,
                };

                final grouped = <String, List<VacationRequest>>{};
                for (final request in others) {
                  final key = request.departamentoId ?? 'sin_departamento';
                  grouped.putIfAbsent(key, () => []).add(request);
                }
                final sortedKeys = grouped.keys.toList()
                  ..sort((a, b) {
                    final an = deptNameById[a] ?? a;
                    final bn = deptNameById[b] ?? b;
                    return an.compareTo(bn);
                  });

                return ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    _SectionHeader(
                      title: 'Mis solicitudes',
                      count: own.length,
                    ),
                    if (own.isEmpty)
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text('No tienes solicitudes.'),
                      )
                    else
                      ...own.map(_buildRequestCard),
                    const SizedBox(height: 12),
                    if (widget.profile.role == UserRole.responsable)
                      _SectionHeader(
                        title: 'Solicitudes del departamento',
                        count: others.length,
                      )
                    else
                      _SectionHeader(
                        title: 'Solicitudes por departamento',
                        count: others.length,
                      ),
                    if (_loadingDepartments)
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (others.isEmpty)
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text('No hay solicitudes.'),
                      )
                    else if (widget.profile.role == UserRole.responsable)
                      ...others.map(_buildRequestCard)
                    else
                      for (final key in sortedKeys) ...[
                        _SubHeader(
                          title: deptNameById[key] ??
                              (key == 'sin_departamento'
                                  ? 'Sin departamento'
                                  : key),
                          count: grouped[key]?.length ?? 0,
                        ),
                        ...grouped[key]!.map(_buildRequestCard),
                      ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(VacationRequest request) {
    final subtitle = _formatRange(request);
    final statusColor = _statusColor(request.estado);
    final bool isPending = request.estado == 'pendiente';
    final days = isPending ? request.diasEstimados : request.diasConsumidos;

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
              request.notas?.isNotEmpty == true ? request.notas! : 'Sin notas',
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
                canApprove: _canApproveRequest(request),
              ),
            ),
          );
          if (updated == true) {
            _refresh();
          }
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            count.toString(),
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SubHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            count.toString(),
            style: const TextStyle(color: Colors.black45),
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
          if (request.userId == profile.uid)
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
