import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';

/// Theme-aware card colours shared across the groups feature (mirrors the
/// pattern used by the profile screen).
class GroupSurface {
  const GroupSurface._({required this.background, required this.border});

  factory GroupSurface.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GroupSurface._(
      background: isDark ? AppColors.cardSurface : AppColors.lightSurface,
      border: isDark
          ? AppColors.cellBorder.withValues(alpha: 0.3)
          : AppColors.lightGridLine,
    );
  }

  final Color background;
  final Color border;

  BoxDecoration decoration({Color? highlight}) => BoxDecoration(
        color: highlight == null
            ? background
            : Color.alphaBlend(highlight.withValues(alpha: 0.08), background),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: highlight ?? border,
          width: highlight == null ? 1 : 1.5,
        ),
      );
}

Color secondaryTextColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

/// Standard confirmation dialog. Returns `true` when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

void showAppSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Centered illustration + message used for empty/error states. Wrapped in
/// a scrollable so it works inside a [RefreshIndicator].
class GroupEmptyState extends StatelessWidget {
  const GroupEmptyState({
    required this.icon,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSizes.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondaryTextColor(context),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSizes.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders an `AsyncValue<List<T>>` as a pull-to-refresh list with loading,
/// empty and error states that all support the refresh gesture.
class AsyncRefreshList<T> extends StatelessWidget {
  const AsyncRefreshList({
    required this.value,
    required this.onRefresh,
    required this.itemBuilder,
    required this.empty,
    this.errorMessage = 'Something went wrong. Pull to retry.',
    this.padding = const EdgeInsetsDirectional.all(AppSizes.md),
    super.key,
  });

  final AsyncValue<List<T>> value;
  final Future<void> Function() onRefresh;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget empty;
  final String errorMessage;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final items = value.valueOrNull;

    if (items != null && items.isNotEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          itemCount: items.length,
          itemBuilder: (context, index) =>
              itemBuilder(context, items[index], index),
        ),
      );
    }

    if (value.isLoading && items == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final Widget body = value.hasError && items == null
        ? GroupEmptyState(
            icon: Icons.cloud_off_rounded,
            message: errorMessage,
            action: OutlinedButton(
              onPressed: onRefresh,
              child: const Text('Retry'),
            ),
          )
        : empty;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Circle avatar with initial fallback.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    required this.displayName,
    this.avatarUrl,
    this.radius = 20,
    super.key,
  });

  final String? displayName;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (displayName ?? '').trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
        child: avatarUrl == null
            ? Text(
                initial,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
    );
  }
}

/// Small pill used for roles ("Admin") and the "You" marker.
class GroupChip extends StatelessWidget {
  const GroupChip({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSizes.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
