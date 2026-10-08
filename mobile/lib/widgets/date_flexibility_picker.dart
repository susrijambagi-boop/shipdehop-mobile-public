import '../core/india_time.dart';
import 'package:flutter/material.dart';
import '../models/date_flexibility.dart';

class DateFlexibilityPicker extends StatefulWidget {
  const DateFlexibilityPicker({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onChanged,
  });

  final String title;
  final DateFlexibility initialValue;
  final void Function(DateFlexibility value) onChanged;

  @override
  State<DateFlexibilityPicker> createState() => _DateFlexibilityPickerState();
}

class _DateFlexibilityPickerState extends State<DateFlexibilityPicker> {
  late DateTime _earliest;
  late DateTime _latest;
  late bool _isFlexible;
  late int _windowHours;

  @override
  void initState() {
    super.initState();
    _earliest = widget.initialValue.earliestDateTime;
    _latest = widget.initialValue.latestDateTime;
    _isFlexible = widget.initialValue.isFlexible;
    _windowHours = widget.initialValue.flexibilityWindowHours;
  }

  void _notify() {
    final value = DateFlexibility(
      earliestDateTime: _earliest,
      latestDateTime: _latest,
      isFlexible: _isFlexible,
      flexibilityWindowHours: _windowHours,
    );
    widget.onChanged(value);
  }

  Future<void> _pickEarliestDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: IndiaTime.wallClock(_earliest),
      firstDate: IndiaTime.wallClock(DateTime.now()).subtract(const Duration(days: 1)),
      lastDate: IndiaTime.wallClock(DateTime.now()).add(const Duration(days: 90)),
    );
    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(IndiaTime.wallClock(_earliest)),
      );
      if (time != null && mounted) {
        setState(() {
          _earliest = IndiaTime.fromWallClock(date.year, date.month, date.day, time.hour, time.minute);
          if (_latest.isBefore(_earliest)) {
            _latest = _earliest.add(const Duration(hours: 24));
          }
        });
        _notify();
      }
    }
  }

  Future<void> _pickLatestDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: IndiaTime.wallClock(_latest.isAfter(_earliest) ? _latest : _earliest),
      firstDate: IndiaTime.wallClock(_earliest),
      lastDate: IndiaTime.wallClock(DateTime.now()).add(const Duration(days: 90)),
    );
    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(IndiaTime.wallClock(_latest)),
      );
      if (time != null && mounted) {
        setState(() {
          _latest = IndiaTime.fromWallClock(date.year, date.month, date.day, time.hour, time.minute);
        });
        _notify();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final flexModel = DateFlexibility(
      earliestDateTime: _earliest,
      latestDateTime: _latest,
      isFlexible: _isFlexible,
      flexibilityWindowHours: _windowHours,
    );

    final errorMsg = flexModel.validationError;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, color: Colors.indigo, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Switch.adaptive(
                  value: _isFlexible,
                  onChanged: (val) {
                    setState(() {
                      _isFlexible = val;
                      if (!val) _windowHours = 0;
                    });
                    _notify();
                  },
                ),
                const Text('Flexible', style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),

            // Formatted timing summary pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      flexModel.formattedFlexibility,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
                    ),
                  ),
                ],
              ),
            ),

            if (errorMsg != null) ...[
              const SizedBox(height: 6),
              Text(
                errorMsg,
                style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],

            const SizedBox(height: 10),

            // Date Pickers
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEarliestDate,
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(
                      _isFlexible ? 'Earliest Pickup' : 'Departure Time',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                if (_isFlexible) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickLatestDate,
                      icon: const Icon(Icons.event_available, size: 16),
                      label: const Text(
                        'Latest Delivery',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),

            if (_isFlexible) ...[
              const SizedBox(height: 10),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  const Text('Flexibility window: ', style: TextStyle(fontSize: 12)),
                  ...[0, 1, 2, 6, 24].map((hrs) {
                    final selected = _windowHours == hrs;
                    return ChoiceChip(
                      label: Text(hrs == 0 ? 'Exact' : '±$hrs hr${hrs > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11)),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _windowHours = hrs);
                        _notify();
                      },
                    );
                  }),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

