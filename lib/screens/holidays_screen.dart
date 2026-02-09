import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../repositories/holidays_repository.dart';

class HolidaysScreen extends StatefulWidget {
  final UserProfile profile;

  const HolidaysScreen({super.key, required this.profile});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  late int _year;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  final Set<String> _dates = {};

  bool get _canEdit =>
      widget.profile.role == UserRole.adminSistema ||
      widget.profile.role == UserRole.jefe;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _dates.clear();
    });
    try {
      final items = await HolidaysRepository.fetchHolidays(_year);
      setState(() {
        _dates.addAll(items);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sorted = _dates.toList()..sort();
      await HolidaysRepository.saveHolidays(_year, sorted);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Festivos guardados')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _addDate() async {
    final first = DateTime(_year, 1, 1);
    final last = DateTime(_year, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: first,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    final key = DateFormat('yyyy-MM-dd').format(picked);
    setState(() => _dates.add(key));
  }

  void _removeDate(String date) {
    setState(() => _dates.remove(date));
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _dates.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Festivos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saving ? null : _save,
            ),
        ],
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton(
              onPressed: _addDate,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text('Ano:'),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() {
                            _year -= 1;
                          });
                          _load();
                        },
                ),
                Text(
                  _year.toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() {
                            _year += 1;
                          });
                          _load();
                        },
                ),
                const Spacer(),
                if (_saving) const Text('Guardando...'),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : sorted.isEmpty
                    ? const Center(child: Text('No hay festivos cargados'))
                    : ListView.builder(
                        itemCount: sorted.length,
                        itemBuilder: (context, index) {
                          final item = sorted[index];
                          final date = DateTime.tryParse(item);
                          final label = date != null
                              ? DateFormat('dd/MM/yyyy').format(date)
                              : item;
                          return ListTile(
                            title: Text(label),
                            trailing: _canEdit
                                ? IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _removeDate(item),
                                  )
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
