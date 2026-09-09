import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/animated_background.dart';
import '../../../shared/widgets/spring_button.dart';
import '../providers/practice_provider.dart';

/// Practice mode setup: pick a grid size and difficulty, then play an
/// unlimited number of locally generated puzzles (never submitted).
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  int _size = 5;
  String _difficulty = 'easy';

  void _start() {
    final seed = newPracticeSeed();
    context.push(
      '/practice/play?size=$_size&difficulty=$_difficulty&seed=$seed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(practiceStatsNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.deepBlack,
      appBar: AppBar(
        title: const Text('Practice'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsetsDirectional.all(AppSizes.lg),
              children: [
                Text(
                  'Unlimited puzzles, generated on your device. Practice '
                  'solves never affect your streak or leaderboards.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondaryDark,
                      ),
                ),
                const SizedBox(height: AppSizes.lg),
                const _SectionLabel('Grid size'),
                const SizedBox(height: AppSizes.sm),
                Wrap(
                  spacing: AppSizes.sm,
                  children: [
                    for (final size in practiceSizes)
                      _ChoiceChip(
                        label: '${size}x$size',
                        selected: _size == size,
                        onTap: () => setState(() => _size = size),
                      ),
                  ],
                ),
                const SizedBox(height: AppSizes.lg),
                const _SectionLabel('Difficulty'),
                const SizedBox(height: AppSizes.sm),
                Wrap(
                  spacing: AppSizes.sm,
                  children: [
                    for (final d in practiceDifficulties)
                      _ChoiceChip(
                        label: '${d[0].toUpperCase()}${d.substring(1)}',
                        selected: _difficulty == d,
                        onTap: () => setState(() => _difficulty = d),
                      ),
                  ],
                ),
                const SizedBox(height: AppSizes.xl),
                SpringButton(
                  onPressed: _start,
                  child: Container(
                    key: const Key('practice-start'),
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.purpleButtonGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.purpleGlow,
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Start practice',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.xl),
                const _SectionLabel('Your practice stats'),
                const SizedBox(height: AppSizes.sm),
                _PracticeStatsCard(stats: stats),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.textPrimaryDark,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSizes.minTouchTarget,
            minWidth: 72,
          ),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm,
          ),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.purpleButtonGradient : null,
            color: selected ? null : AppColors.elevatedSurface,
            borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            border: Border.all(
              color: selected
                  ? AppColors.purpleLight
                  : AppColors.cellBorder.withValues(alpha: 0.6),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textPrimaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PracticeStatsCard extends StatelessWidget {
  const _PracticeStatsCard({required this.stats});

  final PracticeStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.cellBorder.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${stats.count} solved'
            '${stats.count > 0 ? ' · avg ${AppDateUtils.formatTime(stats.averageTimeSeconds)}' : ''}',
            style: const TextStyle(
              color: AppColors.textPrimaryDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          for (final size in practiceSizes)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: AppSizes.xs),
              child: Row(
                children: [
                  Text(
                    '${size}x$size best',
                    style: const TextStyle(color: AppColors.textSecondaryDark),
                  ),
                  const Spacer(),
                  Text(
                    stats.bestBySize[size] == null
                        ? '--:--'
                        : AppDateUtils.formatTime(stats.bestBySize[size]!),
                    style: const TextStyle(
                      color: AppColors.textPrimaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
