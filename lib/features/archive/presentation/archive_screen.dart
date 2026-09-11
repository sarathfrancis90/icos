import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/animated_background.dart';
import '../../puzzle/domain/solver/puzzle_core.dart';
import '../providers/archive_provider.dart';

/// Past puzzles (last 30 UTC days). Solving one is scored but never counts
/// toward the streak.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(archiveEntriesProvider);

    // Always-dark screen (matches the puzzle screen); pin the theme so the
    // AppBar and text stay legible when the system theme is light.
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.deepBlack,
        appBar: AppBar(
          title: const Text('Archive'),
          backgroundColor: Colors.transparent,
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackground()),
            SafeArea(
              child: RefreshIndicator(
                color: AppColors.purpleLight,
                backgroundColor: AppColors.cardSurface,
                onRefresh: () async {
                  ref.invalidate(archiveEntriesProvider);
                  await ref.read(archiveEntriesProvider.future);
                },
                child: entriesAsync.when(
                  data: (entries) => ListView.separated(
                    padding: const EdgeInsetsDirectional.all(AppSizes.md),
                    itemCount: entries.length + 1,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSizes.sm),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(
                            bottom: AppSizes.sm,
                          ),
                          child: Text(
                            "Archive solves don't affect your streak.",
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textSecondaryDark),
                          ),
                        );
                      }
                      return _ArchiveTile(entry: entries[index - 1]);
                    },
                  ),
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.purpleLight,
                    ),
                  ),
                  error: (error, _) => ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.all(AppSizes.lg),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 40,
                              color: AppColors.error,
                            ),
                            const SizedBox(height: AppSizes.md),
                            Text(
                              'Could not load the archive',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSizes.md),
                            ElevatedButton(
                              onPressed: () =>
                                  ref.invalidate(archiveEntriesProvider),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({required this.entry});

  final ArchiveEntry entry;

  @override
  Widget build(BuildContext context) {
    final difficulty = weekdayDifficulty(entry.date).name;
    final result = entry.result;

    final (String badge, Color badgeColor, IconData icon) = entry.rejected
        ? ('Not counted', AppColors.warning, Icons.info_outline_rounded)
        : entry.solved
        ? (
            'Solved · ${AppDateUtils.formatTime(result!.timeSeconds)}',
            AppColors.success,
            Icons.check_circle_rounded,
          )
        : ('Unsolved', AppColors.textSecondaryDark, Icons.circle_outlined);

    return Semantics(
      button: true,
      label: '${AppDateUtils.formatDateHuman(entry.date)}, $difficulty, $badge',
      child: InkWell(
        key: Key('archive-${entry.date}'),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: () => context.push('/puzzle/${entry.date}'),
        child: Container(
          padding: const EdgeInsetsDirectional.all(AppSizes.md),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(
              color: AppColors.cellBorder.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: badgeColor, size: 22),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppDateUtils.formatDateHuman(entry.date),
                      style: const TextStyle(
                        color: AppColors.textPrimaryDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.date} · ${difficulty[0].toUpperCase()}${difficulty.substring(1)}',
                      style: const TextStyle(
                        color: AppColors.textSecondaryDark,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                badge,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSizes.xs),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiaryDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
