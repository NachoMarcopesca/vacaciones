import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_profile.dart';
import '../models/vacation_request.dart';
import '../repositories/holidays_repository.dart';
import '../repositories/requests_repository.dart';

class RequestFormScreen extends StatefulWidget {
  final UserProfile profile;
  final VacationRequest? existing;

  const RequestFormScreen({
    super.key,
    required this.profile,
    this.existing,
  });

  @override
  State<RequestFormScreen> createState() => _RequestFormScreenState();
}

class _RequestFormScreenState extends State<RequestFormScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _notesController = TextEditingController();
  bool _saving = false;
  String? _error;
  final Map<int, Set<String>> _holidaysByYear = {};

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _startDate = _parse(widget.existing!.fechaInicioStr);
      _endDate = _parse(widget.existing!.fechaFinStr);
      _notesController.text = widget.existing!.notas ?? '';
    }
    _loadHolidaysForYear(DateTime.now().year);
  }

  DateTime? _parse(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _format(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('yyyy-MM-dd').format(date);
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      });
      await _loadHolidaysForYear(picked.year);
      if (_endDate != null && _endDate!.year != picked.year) {
        await _loadHolidaysForYear(_endDate!.year);
      }
    }
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
      await _loadHolidaysForYear(picked.year);
      if (_startDate != null && _startDate!.year != picked.year) {
        await _loadHolidaysForYear(_startDate!.year);
      }
    }
  }

  Future<void> _save() async {
    if (_startDate == null || _endDate == null) {
      setState(() => _error = 'Selecciona fechas');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (widget.existing == null) {
        await RequestsRepository.createRequest(
          fechaInicio: _format(_startDate),
          fechaFin: _format(_endDate),
          notas: _notesController.text.trim(),
        );
      } else {
        await RequestsRepository.updateRequest(
          id: widget.existing!.id,
          fechaInicio: _format(_startDate),
          fechaFin: _format(_endDate),
          notas: _notesController.text.trim(),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _loadHolidaysForYear(int year) async {
    if (_holidaysByYear.containsKey(year)) return;
    try {
      final items = await HolidaysRepository.fetchHolidays(year);
      _holidaysByYear[year] = items.toSet();
    } catch (_) {
      _holidaysByYear[year] = {};
    }
  }

  List<String> _holidaysInRange() {
    if (_startDate == null || _endDate == null) return [];
    final start = _startDate!;
    final end = _endDate!;
    final dates = <String>[];
    var cursor = DateTime(start.year, start.month, start.day);
    while (!cursor.isAfter(end)) {
      final key = DateFormat('yyyy-MM-dd').format(cursor);
      final yearSet = _holidaysByYear[cursor.year] ?? {};
      if (yearSet.contains(key)) {
        dates.add(key);
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return dates;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final holidaysInRange = _holidaysInRange();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Nueva solicitud'
            : 'Editar solicitud'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona rango de vacaciones',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _pickStart,
                    child: Text('Inicio: ${_format(_startDate)}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _pickEnd,
                    child: Text('Fin: ${_format(_endDate)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (holidaysInRange.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3F3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF3B2B2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Festivos en el rango: ${holidaysInRange.length}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      holidaysInRange.take(6).join(', '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (holidaysInRange.length > 6)
                      const Text('...'),
                  ],
                ),
              ),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_saving ? 'Guardando...' : 'Guardar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
