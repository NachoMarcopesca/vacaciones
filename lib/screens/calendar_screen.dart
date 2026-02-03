import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/department.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../models/vacation_request.dart';
import '../repositories/holidays_repository.dart';
import '../repositories/requests_repository.dart';

class CalendarScreen extends StatefulWidget {
  final UserProfile profile;
  final bool includePending;
  final String? title;

  const CalendarScreen({
    super.key,
    required this.profile,
    this.includePending = false,
    this.title,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  late Future<List<VacationRequest>> _future;
  List<Department> _departments = [];
  final Set<String> _selectedDeptIds = {};
  bool _loadingDepartments = false;
  bool _loadingHolidays = false;
  final Set<String> _holidayDates = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _future = _load();
    _loadDepartments();
    _loadHolidays(_month.year);
  }

  Future<List<VacationRequest>> _load() {
    final from = DateTime(_month.year, _month.month, 1);
    final to = DateTime(_month.year, _month.month + 1, 0);
    return RequestsRepository.fetchCalendar(
      from: _formatKey(from),
      to: _formatKey(to),
      departamentoIds:
          _selectedDeptIds.isEmpty ? null : _selectedDeptIds.toList(),
      includePending: widget.includePending,
    );
  }

  String _formatKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _future = _load();
    });
    _loadHolidays(_month.year);
  }

  Future<void> _loadDepartments() async {
    final role = widget.profile.role;
    if (role != UserRole.admin && role != UserRole.responsableGeneral) {
      return;
    }
    setState(() => _loadingDepartments = true);
    try {
      final items = await RequestsRepository.fetchDepartments();
      setState(() {
        _departments = items;
      });
    } catch (_) {
      // Ignore for now; calendar still works without filter.
    } finally {
      if (mounted) {
        setState(() => _loadingDepartments = false);
      }
    }
  }

  Future<void> _loadHolidays(int year) async {
    if (_loadingHolidays) return;
    setState(() => _loadingHolidays = true);
    try {
      final items = await HolidaysRepository.fetchHolidays(year);
      setState(() {
        _holidayDates
          ..clear()
          ..addAll(items);
      });
    } catch (_) {
      // Ignore; calendar still works without holidays.
    } finally {
      if (mounted) {
        setState(() => _loadingHolidays = false);
      }
    }
  }

  Map<String, List<VacationRequest>> _expandRequests(
    List<VacationRequest> items,
    Set<String> holidayDates,
  ) {
    final Map<String, List<VacationRequest>> map = {};
    for (final request in items) {
      final start = DateTime.tryParse(request.fechaInicioStr ?? '');
      final end = DateTime.tryParse(request.fechaFinStr ?? '');
      if (start == null || end == null) continue;
      final workingDays = request.workingDays.isEmpty
          ? const [1, 2, 3, 4, 5]
          : request.workingDays;
      var cursor = DateTime(start.year, start.month, start.day);
      while (!cursor.isAfter(end)) {
        final key = _formatKey(cursor);
        if (!_isWorkingDay(cursor, workingDays) ||
            holidayDates.contains(key)) {
          cursor = cursor.add(const Duration(days: 1));
          continue;
        }
        map.putIfAbsent(key, () => []).add(request);
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return map;
  }

  bool _isWorkingDay(DateTime date, List<int> workingDays) {
    return workingDays.contains(date.weekday);
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 420;
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final monthLabel =
        '${months[_month.month - 1]} ${_month.year}';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Calendario'),
      ),
      body: Column(
        children: [
          if (_departments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text('Departamento:'),
                  const SizedBox(width: 12),
                  if (_loadingDepartments)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    OutlinedButton(
                      onPressed: _openDepartmentFilter,
                      child: Text(
                        _selectedDeptIds.isEmpty
                            ? 'Todos'
                            : '${_selectedDeptIds.length} seleccionados',
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeMonth(-1),
                ),
                Text(
                  monthLabel,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),
          if (widget.includePending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _LegendDot(color: Color(0xFF2E7D32)),
                  SizedBox(width: 6),
                  Text('Aprobada'),
                  SizedBox(width: 16),
                  _LegendDot(color: Color(0xFFFF8F00)),
                  SizedBox(width: 6),
                  Text('Pendiente'),
                ],
              ),
            ),
          _WeekHeader(),
          Expanded(
            child: FutureBuilder<List<VacationRequest>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final items = snapshot.data ?? [];
                final map = _expandRequests(items, _holidayDates);

                final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
                final firstWeekday = DateTime(_month.year, _month.month, 1).weekday; // 1=Mon
                final leadingEmpty = firstWeekday - 1;
                final totalCells = leadingEmpty + daysInMonth;
                final rows = (totalCells / 7).ceil();

                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: isCompact ? 0.75 : 1.2,
                  ),
                  itemCount: rows * 7,
                  itemBuilder: (context, index) {
                    final dayNumber = index - leadingEmpty + 1;
                    if (dayNumber < 1 || dayNumber > daysInMonth) {
                      return const SizedBox.shrink();
                    }
                    final date = DateTime(_month.year, _month.month, dayNumber);
                    final key = _formatKey(date);
                    final dayRequests = map[key] ?? [];
                    final isHoliday = _holidayDates.contains(key);

                    return _DayCell(
                      dayNumber: dayNumber,
                      items: dayRequests,
                      includePending: widget.includePending,
                      isHoliday: isHoliday,
                      compact: isCompact,
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

  Future<void> _openDepartmentFilter() async {
    final selected = Set<String>.from(_selectedDeptIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Filtrar departamentos'),
              content: SizedBox(
                width: 300,
                child: ListView(
                  shrinkWrap: true,
                  children: _departments
                      .map(
                        (dept) => CheckboxListTile(
                          value: selected.contains(dept.id),
                          title: Text(dept.name),
                          onChanged: (checked) {
                            setStateDialog(() {
                              if (checked == true) {
                                selected.add(dept.id);
                              } else {
                                selected.remove(dept.id);
                              }
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    selected.clear();
                    Navigator.pop(context, selected);
                  },
                  child: const Text('Limpiar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedDeptIds
          ..clear()
          ..addAll(result);
        _future = _load();
      });
    }
  }
}

class _WeekHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: labels
            .map(
              (label) => Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int dayNumber;
  final List<VacationRequest> items;
  final bool includePending;
  final bool isHoliday;
  final bool compact;

  const _DayCell({
    required this.dayNumber,
    required this.items,
    required this.includePending,
    required this.isHoliday,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final count = items.length;
    return Container(
      padding: EdgeInsets.all(compact ? 4 : 8),
      decoration: BoxDecoration(
        color: isHoliday ? const Color(0xFFFFF3F3) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isHoliday ? const Color(0xFFF3B2B2) : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dayNumber.toString(),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 11 : 13,
                ),
              ),
              if (isHoliday)
                Icon(
                  Icons.flag,
                  size: compact ? 12 : 14,
                  color: const Color(0xFFC62828),
                ),
            ],
          ),
          SizedBox(height: compact ? 2 : 4),
          if (count == 0)
            const SizedBox.shrink()
          else
            ..._buildNames(compact),
        ],
      ),
    );
  }

  List<Widget> _buildNames(bool compact) {
    final maxLines = compact ? 3 : 2;
    final sorted = List<VacationRequest>.from(items)
      ..sort((a, b) => a.estado.compareTo(b.estado));
    final visible = sorted.take(maxLines).toList();
    final remaining = items.length - visible.length;
    final widgets = <Widget>[];

    for (final request in visible) {
      final displayName = request.userDisplayName?.trim();
      final email = request.userEmail ?? '';
      final fallback = email.contains('@') ? email.split('@').first : email;
      final label =
          (displayName != null && displayName.isNotEmpty) ? displayName : fallback;
      final color = _colorFor(label);
      final statusColor = request.estado == 'aprobada'
          ? const Color(0xFF2E7D32)
          : const Color(0xFFFF8F00);
      final dotColor = includePending ? statusColor : color;
      widgets.add(
        Row(
          children: [
            Container(
              width: compact ? 6 : 8,
              height: compact ? 6 : 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: compact ? 3 : 4),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 8 : 10,
                  color: includePending ? statusColor : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    if (remaining > 0) {
      widgets.add(
        Text(
          '+$remaining mas',
          style: TextStyle(
            fontSize: compact ? 8 : 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return widgets;
  }

  Color _colorFor(String value) {
    const palette = [
      Color(0xFF1565C0),
      Color(0xFF2E7D32),
      Color(0xFF6A1B9A),
      Color(0xFFEF6C00),
      Color(0xFF00838F),
      Color(0xFFAD1457),
      Color(0xFF4E342E),
      Color(0xFF283593),
      Color(0xFF558B2F),
      Color(0xFF4527A0),
    ];
    final hash = value.codeUnits.fold<int>(0, (acc, c) => acc + c);
    return palette[hash % palette.length];
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;

  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
