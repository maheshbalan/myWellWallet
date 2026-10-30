import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../theme/app_palette.dart';

enum VitalWindow { day, week, month }

class VitalPoint {
  const VitalPoint(this.time, this.value);
  final DateTime time;
  final double value;
}

class VitalStats {
  const VitalStats({this.average, this.high, this.low, this.count = 0});

  final double? average;
  final double? high;
  final double? low;
  final int count;

  static VitalStats from(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return const VitalStats();
    var high = list.first;
    var low = list.first;
    var sum = 0.0;
    for (final value in list) {
      sum += value;
      if (value > high) high = value;
      if (value < low) low = value;
    }
    return VitalStats(average: sum / list.length, high: high, low: low, count: list.length);
  }
}

DateTime vitalWindowCutoff(VitalWindow window) {
  final days = switch (window) {
    VitalWindow.day => 1,
    VitalWindow.week => 7,
    VitalWindow.month => 30,
  };
  return DateTime.now().subtract(Duration(days: days));
}

List<VitalPoint> pointsInWindow(List<VitalPoint> points, VitalWindow window) {
  final cutoff = vitalWindowCutoff(window);
  return [for (final point in points) if (!point.time.isBefore(cutoff)) point];
}

/// Hourly buckets for the last day, daily buckets otherwise.
/// [sum] totals the bucket (steps). Otherwise the bucket is an average.
List<VitalPoint> bucketPoints(List<VitalPoint> points, VitalWindow window, {bool sum = false}) {
  final grouped = <DateTime, List<double>>{};
  for (final point in points) {
    final at = point.time;
    final key = window == VitalWindow.day
        ? DateTime(at.year, at.month, at.day, at.hour)
        : DateTime(at.year, at.month, at.day);
    grouped.putIfAbsent(key, () => []).add(point.value);
  }
  final keys = grouped.keys.toList()..sort();
  return [
    for (final key in keys)
      VitalPoint(
        key,
        sum
            ? grouped[key]!.reduce((a, b) => a + b)
            : grouped[key]!.reduce((a, b) => a + b) / grouped[key]!.length,
      ),
  ];
}

class VitalWindowMenu extends StatelessWidget {
  const VitalWindowMenu({super.key, required this.value, required this.onChanged});

  final VitalWindow value;
  final ValueChanged<VitalWindow> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<VitalWindow>(
      value: value,
      underline: const SizedBox.shrink(),
      items: const [
        DropdownMenuItem(value: VitalWindow.day, child: Text('Last Day')),
        DropdownMenuItem(value: VitalWindow.week, child: Text('Last Week')),
        DropdownMenuItem(value: VitalWindow.month, child: Text('Last Month')),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

class VitalStatCard extends StatelessWidget {
  const VitalStatCard({
    super.key,
    required this.label,
    required this.stats,
    required this.format,
  });

  final String label;
  final VitalStats stats;
  final String Function(double value) format;

  @override
  Widget build(BuildContext context) {
    String n(double? value) => value == null ? '—' : format(value);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppPalette.ink)),
            ),
            Expanded(child: _metric('Average', n(stats.average))),
            Expanded(child: _metric('High', n(stats.high))),
            Expanded(child: _metric('Low', n(stats.low))),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppPalette.muted, fontSize: 12)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppPalette.ink, fontSize: 16)),
      ],
    );
  }
}

class VitalTrendChart extends StatelessWidget {
  const VitalTrendChart({
    super.key,
    required this.points,
    this.secondPoints = const [],
    this.average,
    this.lowBound,
    this.highBound,
    this.emptyText = 'No readings in this period.',
  });

  final List<VitalPoint> points;
  final List<VitalPoint> secondPoints;
  final double? average;
  final double? lowBound;
  final double? highBound;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.border),
      ),
      child: points.isEmpty
          ? Center(child: Text(emptyText, style: const TextStyle(color: AppPalette.muted)))
          : Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 12, 28),
              child: CustomPaint(
                painter: _VitalPainter(
                  points: points,
                  secondPoints: secondPoints,
                  average: average,
                  lowBound: lowBound,
                  highBound: highBound,
                ),
                child: const SizedBox.expand(),
              ),
            ),
    );
  }
}

class _VitalPainter extends CustomPainter {
  _VitalPainter({
    required this.points,
    required this.secondPoints,
    required this.average,
    required this.lowBound,
    required this.highBound,
  });

  final List<VitalPoint> points;
  final List<VitalPoint> secondPoints;
  final double? average;
  final double? lowBound;
  final double? highBound;

  @override
  void paint(Canvas canvas, Size size) {
    final values = <double>[
      for (final point in points) point.value,
      for (final point in secondPoints) point.value,
      if (average != null) average!,
      if (lowBound != null) lowBound!,
      if (highBound != null) highBound!,
    ];
    var yMin = values.reduce(math.min);
    var yMax = values.reduce(math.max);
    final span = yMax - yMin;
    final tiny = yMax.abs() < 10 && yMin.abs() < 10;
    final minSpan = tiny ? 0.4 : 20.0;
    if (span < minSpan) {
      final pad = math.max(minSpan / 2, yMax.abs() * 0.05);
      yMin -= pad;
      yMax += pad;
    }
    if (yMax == yMin) {
      yMin -= 1;
      yMax += 1;
    }

    final topLabel = _axisLabel(highBound ?? yMax);
    final bottomLabel = _axisLabel(lowBound ?? yMin);
    final left = 8.0 + math.max(topLabel.length, bottomLabel.length) * 8.0;
    final plot = Rect.fromLTWH(left, 4, math.max(8, size.width - left - 4), size.height - 22);

    double yOf(double value) {
      final t = (value - yMin) / (yMax - yMin);
      return plot.bottom - t * plot.height;
    }

    double xOf(int index) {
      if (points.length == 1) return plot.center.dx;
      return plot.left + index / (points.length - 1) * plot.width;
    }

    if (lowBound != null && highBound != null) {
      final top = math.max(lowBound!, highBound!);
      final bottom = math.min(lowBound!, highBound!);
      canvas.drawRect(
        Rect.fromLTRB(plot.left, yOf(top), plot.right, yOf(bottom)),
        Paint()..color = AppPalette.goldSoft,
      );
      final boundPaint = Paint()
        ..color = AppPalette.goldDeep
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(plot.left, yOf(bottom)), Offset(plot.right, yOf(bottom)), boundPaint);
      canvas.drawLine(Offset(plot.left, yOf(top)), Offset(plot.right, yOf(top)), boundPaint);
      _label(canvas, _axisLabel(top), Offset(0, yOf(top) - 6));
      _label(canvas, _axisLabel(bottom), Offset(0, yOf(bottom) - 6));
    } else {
      _label(canvas, topLabel, Offset(0, yOf(yMax) - 6));
      _label(canvas, bottomLabel, Offset(0, yOf(yMin) - 6));
    }

    if (average != null) {
      final avgPaint = Paint()
        ..color = AppPalette.ink
        ..strokeWidth = 1.4;
      final y = yOf(average!);
      const dash = 6.0;
      for (double x = plot.left; x < plot.right; x += dash * 2) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, plot.right), y), avgPaint);
      }
    }

    _drawSeries(
      canvas,
      xOf,
      yOf,
      [for (final point in points) point.value as double?],
      AppPalette.ink,
    );
    if (secondPoints.isNotEmpty) {
      _drawSeries(
        canvas,
        xOf,
        yOf,
        [for (var i = 0; i < points.length; i++) _secondAt(i)],
        AppPalette.goldDeep,
      );
    }

    final first = DateFormat.MMMd().format(points.first.time);
    final last = DateFormat.MMMd().add_jm().format(points.last.time);
    final caption = TextPainter(
      text: TextSpan(
        text: points.length == 1 ? last : '$first – $last',
        style: const TextStyle(color: AppPalette.muted, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: plot.width);
    caption.paint(canvas, Offset(plot.left, size.height - 14));
  }

  double? _secondAt(int index) {
    if (index < secondPoints.length && secondPoints[index].time == points[index].time) {
      return secondPoints[index].value;
    }
    final time = points[index].time;
    for (final point in secondPoints) {
      if (point.time == time) return point.value;
    }
    return null;
  }

  void _drawSeries(
    Canvas canvas,
    double Function(int) xOf,
    double Function(double) yOf,
    List<double?> values,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    Path? path;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        if (path != null) canvas.drawPath(path, paint);
        path = null;
        continue;
      }
      final offset = Offset(xOf(i), yOf(value));
      path ??= Path()..moveTo(offset.dx, offset.dy);
      path.lineTo(offset.dx, offset.dy);
      canvas.drawCircle(offset, 3.5, Paint()..color = color);
    }
    if (path != null) canvas.drawPath(path, paint);
  }

  String _axisLabel(double value) {
    if (value.abs() >= 100 || value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(value.abs() >= 10 ? 1 : 1);
  }

  void _label(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: AppPalette.muted, fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _VitalPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.secondPoints != secondPoints ||
        oldDelegate.average != average ||
        oldDelegate.lowBound != lowBound ||
        oldDelegate.highBound != highBound;
  }
}
