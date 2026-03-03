import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/date_utils.dart';
import '../../domain/models/streak.dart';

/// A grid showing the last 30 days of solve history.
class StreakCalendar extends StatelessWidget {
  const StreakCalendar({
    super.key,
    required this.solveHistory,
    required this.currentStreak,
    this.parTimeSeconds,
  });

  final List<SolveHistory> solveHistory;
  final int currentStreak;
  final int? parTimeSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now().toUtc();
    final todayStr = AppDateUtils.formatDate(today);

    final historyMap = <String, SolveHistory>{};
    for (final entry in solveHistory) {
      historyMap[entry.date] = entry;
    }

    final days = List.generate(30, (i) {
      return today.subtract(Duration(days: 29 - i));
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last 30 Days',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSizes.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            const columns = 7;
            const spacing = AppSizes.xs;
            final cellSize =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;
            final effectiveCellSize = cellSize.clamp(
              AppSizes.minTouchTarget,
              double.infinity,
            );

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: days.map((day) {
                final dateStr = AppDateUtils.formatDate(day);
                final history = historyMap[dateStr];
                final isToday = dateStr == todayStr;
                final isSolved = history != null && history.completed;
                final isUnderPar = isSolved &&
                    parTimeSeconds != null &&
                    history.timeSeconds < parTimeSeconds!;

                final daysSinceToday = today.difference(day).inDays;
                final isInStreak =
                    isSolved && daysSinceToday < currentStreak;

                return _CalendarDay(
                  day: day.day,
                  size: effectiveCellSize,
                  isSolved: isSolved,
                  isToday: isToday,
                  isUnderPar: isUnderPar,
                  isInStreak: isInStreak,
                  isFuture: day.isAfter(today),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: AppSizes.sm),
        _CalendarLegend(),
      ],
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.size,
    required this.isSolved,
    required this.isToday,
    required this.isUnderPar,
    required this.isInStreak,
    required this.isFuture,
  });

  final int day;
  final double size;
  final bool isSolved;
  final bool isToday;
  final bool isUnderPar;
  final bool isInStreak;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    Color textColor;
    Border? border;

    if (isFuture) {
      backgroundColor = Colors.transparent;
      textColor = AppColors.textTertiaryDark;
    } else if (isSolved) {
      backgroundColor = AppColors.success.withValues(alpha: 0.8);
      textColor = Colors.white;
    } else {
      backgroundColor = AppColors.cellBackground;
      textColor = AppColors.textSecondaryDark;
    }

    if (isUnderPar) {
      border = Border.all(color: AppColors.streakGold, width: 2);
    } else if (isToday) {
      border = Border.all(color: AppColors.purpleLight, width: 2);
    }

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          border: border,
        ),
        child: Center(
          child: Text(
            '$day',
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _LegendItem(
          color: AppColors.success.withValues(alpha: 0.8),
          label: 'Solved',
          textStyle: theme.textTheme.bodySmall,
        ),
        const SizedBox(width: AppSizes.md),
        _LegendItem(
          color: AppColors.cellBackground,
          label: 'Missed',
          textStyle: theme.textTheme.bodySmall,
        ),
        const SizedBox(width: AppSizes.md),
        _LegendItem(
          color: AppColors.success.withValues(alpha: 0.8),
          borderColor: AppColors.streakGold,
          label: 'Under par',
          textStyle: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.textStyle,
    this.borderColor,
  });

  final Color color;
  final Color? borderColor;
  final String label;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 1.5)
                : null,
          ),
        ),
        const SizedBox(width: AppSizes.xs),
        Text(label, style: textStyle),
      ],
    );
  }
}
