import 'package:flutter/material.dart';

import '../models/user_entry.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../repositories/users_repository.dart';

class UsersScreen extends StatefulWidget {
  final UserProfile profile;

  const UsersScreen({super.key, required this.profile});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<UserEntry>> _future;

  bool get _canEdit =>
      widget.profile.role == UserRole.admin ||
      widget.profile.role == UserRole.responsableGeneral ||
      widget.profile.role == UserRole.responsable;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<UserEntry>> _load() {
    return UsersRepository.fetchUsers();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuarios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<UserEntry>>(
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
            return const Center(child: Text('No hay usuarios'));
          }

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = items[index];
              final name = (user.displayName != null &&
                      user.displayName!.trim().isNotEmpty)
                  ? user.displayName!.trim()
                  : _emailLabel(user.email);
              final role = _roleLabel(user.role);
              final dept = user.departamentoId ?? '-';
              final schedule = _workingDaysLabel(user.workingDays);
              final initials =
                  name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
              return ListTile(
                title: Text(name),
                subtitle: Text('Rol: $role · Depto: $dept\nHorario: $schedule'),
                trailing: _canEdit
                    ? IconButton(
                        icon: const Icon(Icons.edit_calendar),
                        onPressed: () => _editWorkingDays(user),
                      )
                    : null,
                onTap: _canEdit ? () => _editWorkingDays(user) : null,
                leading: CircleAvatar(
                  child: Text(initials),
                ),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'responsable_general':
        return 'Responsable general';
      case 'responsable':
        return 'Responsable';
      case 'empleado':
      default:
        return 'Empleado';
    }
  }

  String _emailLabel(String email) {
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return email;
  }

  String _workingDaysLabel(List<int> workingDays) {
    final days = workingDays.isEmpty ? const [1, 2, 3, 4, 5] : workingDays;
    const labels = {
      1: 'L',
      2: 'M',
      3: 'X',
      4: 'J',
      5: 'V',
      6: 'S',
      7: 'D',
    };
    return days.map((d) => labels[d] ?? '').where((v) => v.isNotEmpty).join(' ');
  }

  Future<void> _editWorkingDays(UserEntry user) async {
    final current =
        user.workingDays.isEmpty ? [1, 2, 3, 4, 5] : List<int>.from(user.workingDays);
    final selected = current.toSet();
    final result = await showDialog<List<int>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('Horario de ${user.displayName ?? user.email}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: _weekdayLabels.entries.map((entry) {
                  return CheckboxListTile(
                    value: selected.contains(entry.key),
                    title: Text(entry.value),
                    onChanged: (checked) {
                      setStateDialog(() {
                        if (checked == true) {
                          selected.add(entry.key);
                        } else {
                          selected.remove(entry.key);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                            context,
                            selected.toList()..sort(),
                          ),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    await UsersRepository.updateWorkingDays(
      userId: user.userId,
      workingDays: result,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Horario actualizado')),
    );
    _refresh();
  }
}

const Map<int, String> _weekdayLabels = {
  1: 'Lunes',
  2: 'Martes',
  3: 'Miercoles',
  4: 'Jueves',
  5: 'Viernes',
  6: 'Sabado',
  7: 'Domingo',
};
