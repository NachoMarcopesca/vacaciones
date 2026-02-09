import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../repositories/balances_repository.dart';
import 'calendar_screen.dart';
import 'balances_screen.dart';
import 'holidays_screen.dart';
import 'requests_list_screen.dart';
import 'users_screen.dart';

class DashboardScreen extends StatelessWidget {
  final UserProfile profile;

  const DashboardScreen({super.key, required this.profile});

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.adminSistema:
        return 'Administrador sistema';
      case UserRole.jefe:
        return 'Jefe';
      case UserRole.responsable:
        return 'Responsable';
      case UserRole.empleado:
      default:
        return 'Empleado';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vacaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile.displayName ?? profile.email,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('Rol: ${_roleLabel(profile.role)}'),
            if (profile.departamentoId != null)
              Text('Departamento: ${profile.departamentoId}'),
            const SizedBox(height: 20),
            FutureBuilder(
              future: BalancesRepository.fetchBalance(profile.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }

                if (snapshot.hasError) {
                  return const Text('No se pudo cargar el saldo');
                }

                final balance = snapshot.data;
                if (balance == null) {
                  return const SizedBox.shrink();
                }

                return Card(
                  child: ListTile(
                    title: const Text('Saldo disponible'),
                    subtitle: Text(
                      'Asignados: ${balance.diasAsignadosAnual} · Arrastrados: ${balance.diasArrastrados} · Extra: ${balance.diasExtra}',
                    ),
                    trailing: Text(
                      '${balance.diasDisponibles}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Modulos en construccion',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ModuleChip(
                  label: 'Solicitudes',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RequestsListScreen(profile: profile),
                      ),
                    );
                  },
                ),
                _ModuleChip(
                  label: 'Calendario',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CalendarScreen(profile: profile),
                      ),
                    );
                  },
                ),
                _ModuleChip(
                  label: 'Saldo',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BalancesScreen(profile: profile),
                      ),
                    );
                  },
                ),
                _ModuleChip(
                  label: 'Festivos',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HolidaysScreen(profile: profile),
                      ),
                    );
                  },
                ),
                if (profile.role == UserRole.adminSistema ||
                    profile.role == UserRole.jefe ||
                    profile.role == UserRole.responsable)
                  _ModuleChip(
                    label: 'Usuarios',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UsersScreen(profile: profile),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ModuleChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _ModuleChip({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (onTap != null) {
      return ActionChip(
        label: Text(label),
        onPressed: onTap,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }
    return Chip(
      label: Text(label),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
