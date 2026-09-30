import 'package:flutter/material.dart';
import '../core/a11y/access.dart';
import '../core/theme/even_colors.dart';
import '../core/utils/sensory_feedback.dart';

// Data model

enum BubbleType { wake, meal, energyDip, sleep }

extension BubbleTypeExtension on BubbleType {
  IconData get icon {
    switch (this) {
      case BubbleType.wake:
        return Icons.wb_sunny_rounded;
      case BubbleType.meal:
        return Icons.restaurant_rounded;
      case BubbleType.energyDip:
        return Icons.bolt_rounded;
      case BubbleType.sleep:
        return Icons.nightlight_round;
    }
  }

  String get label {
    switch (this) {
      case BubbleType.wake:
        return 'Wake up';
      case BubbleType.meal:
        return 'Meal';
      case BubbleType.energyDip:
        return 'Energy dip';
      case BubbleType.sleep:
        return 'Sleep';
    }
  }

  Color get color {
    switch (this) {
      case BubbleType.wake:
        return EvenColors.bufferAmber;
      case BubbleType.meal:
        return EvenColors.netSage;
      case BubbleType.energyDip:
        return const Color(0xFFF97316); // orange-500
      case BubbleType.sleep:
        return const Color(0xFF6366F1); // indigo-500
    }
  }

  Color get lightColor {
    switch (this) {
      case BubbleType.wake:
        return EvenColors.bufferAmberLight;
      case BubbleType.meal:
        return EvenColors.netSageLight;
      case BubbleType.energyDip:
        return const Color(0xFFFB923C);
      case BubbleType.sleep:
        return const Color(0xFF818CF8);
    }
  }
}

class TimelineBubble {
  final BubbleType type;

  /// Minutes since midnight (e.g. 7:30 AM = 450)
  final int minutesMidnight;

  const TimelineBubble({required this.type, required this.minutesMidnight});

  String get timeLabel {
    final h = minutesMidnight ~/ 60;
    final m = minutesMidnight % 60;
    final period = h < 12 ? 'AM' : 'PM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayH:${m.toString().padLeft(2, '0')} $period';
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineBubble &&
      other.type == type &&
      other.minutesMidnight == minutesMidnight;

  @override
  int get hashCode => Object.hash(type, minutesMidnight);
}

// Main widget

/// Interactive horizontal day-timeline for onboarding.
///
/// The visible range is 5 AM (300 min) to 1 AM next day (1500 min = 25h mark).
/// Bubbles snap to the nearest 30-minute slot.
class DayTimelineWidget extends StatefulWidget {
  final List<TimelineBubble> bubbles;
  final BubbleType selectedType;
  final ValueChanged<List<TimelineBubble>> onChanged;

  const DayTimelineWidget({
    super.key,
    required this.bubbles,
    required this.selectedType,
    required this.onChanged,
  });

  @override
  State<DayTimelineWidget> createState() => _DayTimelineWidgetState();
}

class _DayTimelineWidgetState extends State<DayTimelineWidget>
    with SingleTickerProviderStateMixin {
  // Timeline range: 5 AM  1 AM (next day) = 20 hours = 1200 minutes
  static const int _startMinutes = 5 * 60; // 300
  static const int _endMinutes = 25 * 60; // 1500
  static const int _totalMinutes = _endMinutes - _startMinutes; // 1200

  // Pixels per minute
  static const double _pxPerMin = 4.0;
  static const double _timelineWidth = _totalMinutes * _pxPerMin; // 4800px

  // Visual constants
  static const double _bubbleRadius = 22.0;
  static const double _trackY = 148.0; // Y position of the timeline track
  static const double _trackHeight = 3.0;
  static const double _labelY = _trackY + 16.0;

  late final ScrollController _scrollController;
  late final AnimationController _popController;

  @override
  void initState() {
    super.initState();

    // Scroll to 7 AM on initial load (a natural start-of-day anchor)
    const initialAnchorMinutes = 7 * 60; // 7:00 AM
    final initialOffset =
        ((initialAnchorMinutes - _startMinutes) * _pxPerMin - 60).clamp(
          0.0,
          _timelineWidth,
        );

    _scrollController = ScrollController(initialScrollOffset: initialOffset);

    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _popController.dispose();
    super.dispose();
  }

  int _snapToSlot(double tapX) {
    final minutes = (tapX / _pxPerMin).round() + _startMinutes;
    // Snap to nearest 30-min
    final snapped = ((minutes / 30).round() * 30).clamp(
      _startMinutes,
      _endMinutes - 30,
    );
    return snapped;
  }

  double _minutesToX(int minutes) => (minutes - _startMinutes) * _pxPerMin;

  void _handleTap(TapUpDetails details) {
    final localY = details.localPosition.dy;

    // Only respond to taps in the track zone
    if (localY < _trackY - 40 || localY > _labelY + 20) return;

    final tapX = details.localPosition.dx + _scrollController.offset;
    final snappedMin = _snapToSlot(tapX);

    // Check if tapping an existing bubble  remove it
    final existing = widget.bubbles.where((b) {
      final bx = _minutesToX(b.minutesMidnight);
      return (bx - tapX).abs() < _bubbleRadius * 2;
    }).toList();

    final updated = List<TimelineBubble>.from(widget.bubbles);

    if (existing.isNotEmpty) {
      // Remove the first matching bubble
      updated.removeWhere((b) => existing.contains(b));
      SensoryFeedback.gentleTap();
    } else {
      // Check if same type already placed at this slot: replace it
      updated.removeWhere(
        (b) =>
            b.type == widget.selectedType &&
            (b.minutesMidnight - snappedMin).abs() < 30,
      );

      // For single-slot types (wake, sleep), remove any previous of same type
      if (widget.selectedType == BubbleType.wake ||
          widget.selectedType == BubbleType.sleep) {
        updated.removeWhere((b) => b.type == widget.selectedType);
      }

      updated.add(
        TimelineBubble(type: widget.selectedType, minutesMidnight: snappedMin),
      );
      SensoryFeedback.gentleTap();
      _popController.forward(from: 0);
    }

    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Day timeline with ${widget.bubbles.length} events. '
          '${widget.bubbles.map((b) => '${b.type.label} at ${b.timeLabel}').join('. ')}',
      child: GestureDetector(
        onTapUp: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: _timelineWidth,
            height: _labelY + 40,
            child: CustomPaint(
              painter: _TimelinePainter(
                bubbles: widget.bubbles,
                startMinutes: _startMinutes,
                pxPerMin: _pxPerMin,
                trackY: _trackY,
                trackHeight: _trackHeight,
                labelY: _labelY,
                bubbleRadius: _bubbleRadius,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

// Custom Painter

class _TimelinePainter extends CustomPainter {
  final List<TimelineBubble> bubbles;
  final int startMinutes;
  final double pxPerMin;
  final double trackY;
  final double trackHeight;
  final double labelY;
  final double bubbleRadius;

  _TimelinePainter({
    required this.bubbles,
    required this.startMinutes,
    required this.pxPerMin,
    required this.trackY,
    required this.trackHeight,
    required this.labelY,
    required this.bubbleRadius,
  });

  double _minutesToX(int minutes) => (minutes - startMinutes) * pxPerMin;

  @override
  void paint(Canvas canvas, Size size) {
    _drawTrack(canvas, size);
    _drawHourMarkers(canvas, size);
    _drawBubbles(canvas, size);
  }

  void _drawTrack(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = trackHeight
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(0, trackY), Offset(size.width, trackY), trackPaint);
  }

  void _drawHourMarkers(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.5;

    final labelStyle = const TextStyle(
      fontSize: 10,
      color: Color(0xFF94A3B8),
      fontWeight: FontWeight.w500,
    );

    // Draw tick + label every 3 hours
    for (int h = 5; h <= 25; h++) {
      if ((h - 5) % 3 != 0) continue;

      final minutes = h * 60;
      final x = _minutesToX(minutes);

      // Tick mark
      canvas.drawLine(Offset(x, trackY - 6), Offset(x, trackY + 6), tickPaint);

      // Time label
      final displayH = h % 24;
      final period = displayH < 12 ? 'AM' : 'PM';
      final h12 = displayH == 0
          ? 12
          : (displayH > 12 ? displayH - 12 : displayH);
      final label = '$h12 $period';

      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(x - tp.width / 2, labelY));
    }
  }

  void _drawBubbles(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final bubble in bubbles) {
      final x = _minutesToX(bubble.minutesMidnight);
      final center = Offset(x, trackY - bubbleRadius - 8);

      // Shadow
      final shadowPaint = Paint()
        ..color = bubble.type.color.withValues(alpha: 0.25)
        ..maskFilter = safeMaskBlur(8);
      canvas.drawCircle(center, bubbleRadius + 2, shadowPaint);

      // Bubble fill
      final fillPaint = Paint()..color = bubble.type.color;
      canvas.drawCircle(center, bubbleRadius, fillPaint);

      // Connector line from bubble bottom to track
      final linePaint = Paint()
        ..color = bubble.type.color.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, trackY - 8), Offset(x, trackY), linePaint);

      // Dot on track
      final dotPaint = Paint()..color = bubble.type.color;
      canvas.drawCircle(Offset(x, trackY), 5, dotPaint);

      // Icon glyph
      textPainter.text = TextSpan(
        text: String.fromCharCode(bubble.type.icon.codePoint),
        style: TextStyle(
          fontFamily: bubble.type.icon.fontFamily,
          package: bubble.type.icon.fontPackage,
          fontSize: 16,
          color: Colors.white,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        center - Offset(textPainter.width / 2, textPainter.height / 2),
      );

      // Time label below bubble (small)
      textPainter.text = TextSpan(
        text: bubble.timeLabel,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: bubble.type.lightColor,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          x - textPainter.width / 2,
          center.dy - bubbleRadius - textPainter.height - 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => old.bubbles != bubbles;
}

// Bubble Type Selector (bottom row)

class BubbleTypeSelector extends StatelessWidget {
  final BubbleType selected;
  final ValueChanged<BubbleType> onSelect;

  const BubbleTypeSelector({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: BubbleType.values.map((type) {
          final isSelected = type == selected;
          return GestureDetector(
            onTap: () {
              SensoryFeedback.gentleTap();
              onSelect(type);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? type.color.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: isSelected
                      ? type.color.withValues(alpha: 0.6)
                      : const Color(0xFFE2E8F0),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    type.icon,
                    size: 14,
                    color: isSelected ? type.color : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    type.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected ? type.color : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Helper: infer UserProfile fields from placed bubbles

class TimelineInference {
  static const _defaultWakeMins = 7 * 60; // 7:00 AM
  static const _defaultSleepMins = 23 * 60; // 11:00 PM
  static const List<int> _defaultMealMins = [
    8 * 60, // 8:00 AM
    13 * 60, // 1:00 PM
    19 * 60, // 7:00 PM
  ];
  static const _defaultCrashMins = 15 * 60; // 3:00 PM

  static ({
    String wakeTime,
    String sleepTime,
    int targetMealsPerDay,
    String mealSchedule,
    double targetSatietyHoursDaily,
    String crashPattern,
  })
  infer(List<TimelineBubble> bubbles) {
    // Wake & sleep
    final wake =
        bubbles
            .where((b) => b.type == BubbleType.wake)
            .map((b) => b.minutesMidnight)
            .firstOrNull ??
        _defaultWakeMins;

    final sleep =
        bubbles
            .where((b) => b.type == BubbleType.sleep)
            .map((b) => b.minutesMidnight)
            .firstOrNull ??
        _defaultSleepMins;

    // Meals
    final mealMinutes = bubbles
        .where((b) => b.type == BubbleType.meal)
        .map((b) => b.minutesMidnight)
        .toList();

    final effectiveMeals = mealMinutes.isEmpty ? _defaultMealMins : mealMinutes;
    final mealCount = effectiveMeals.length.clamp(1, 5);

    final mealSchedule = switch (mealCount) {
      1 => '1 Meal (OMAD)',
      2 => '2 Substantial Meals (Intermittent Fasting)',
      3 => '3 Balanced Meals',
      _ => '3 Meals + Mindful Afternoon Snack',
    };

    // Satiety hours (wake  sleep window)
    final awakeMins = sleep > wake ? sleep - wake : (sleep + 24 * 60) - wake;
    final satietyHours = (awakeMins / 60).clamp(8.0, 18.0);

    // Crash pattern
    final crashMins =
        bubbles
            .where((b) => b.type == BubbleType.energyDip)
            .map((b) => b.minutesMidnight)
            .firstOrNull ??
        _defaultCrashMins;

    final crashHour = crashMins ~/ 60;
    final crashPattern = _crashLabel(crashHour);

    return (
      wakeTime: _toTimeString(wake),
      sleepTime: _toTimeString(sleep),
      targetMealsPerDay: mealCount,
      mealSchedule: mealSchedule,
      targetSatietyHoursDaily: satietyHours,
      crashPattern: crashPattern,
    );
  }

  static String _toTimeString(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static String _crashLabel(int hour) {
    if (hour >= 10 && hour < 12) return 'Mid-Morning Dip (10:30-11:30 AM)';
    if (hour >= 13 && hour < 16) return 'Afternoon Slump (2:00-3:30 PM)';
    if (hour >= 19 && hour < 23) return 'Late-Night Snacking (8:00-10:00 PM)';
    return 'Afternoon Slump (2:00-3:30 PM)'; // sensible default
  }
}
