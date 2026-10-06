import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/animated_background.dart';
import '../../../shared/widgets/content_width.dart';
import '../../puzzle/domain/solver/puzzle_core.dart';
import '../providers/archive_provider.dart';

/// Past puzzles (last 30 UTC days). Solving one is scored but never counts
/// toward the streak.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(archiveEntriesProvider);

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: const Text('Archive'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: ContentWidth(child: RefreshIndicator(
              color: context.palette.accent,
              backgroundColor: context.palette.card,
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
                              ?.copyWith(color: context.palette.textSecondary),
                        ),
                      );
                    }
                    return _ArchiveTile(entry: entries[index - 1]);
                  },
                ),
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: context.palette.accent,
                  ),
                ),
                error: (error, _) => ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.all(AppSizes.lg),
                      child: Column(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 40,
                            color: context.palette.error,
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
          )),
        ],
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
        ? ('Not counted', context.palette.warning, Icons.info_outline_rounded)
        : entry.solved
        ? (
            'Solved · ${AppDateUtils.formatTime(result!.timeSeconds)}',
            context.palette.success,
            Icons.check_circle_rounded,
          )
        : ('Unsolved', context.palette.textSecondary, Icons.circle_outlined);

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
            color: context.palette.card,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(
              color: context.palette.border.withValues(alpha: 0.4),
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
                      style: TextStyle(
                        color: context.palette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.date} · ${difficulty[0].toUpperCase()}${difficulty.substring(1)}',
                      style: TextStyle(
                        color: context.palette.textSecondary,
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
              Icon(
                Icons.chevron_right_rounded,
                color: context.palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
