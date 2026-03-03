import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../domain/models/game_state.dart';

class GameControls extends StatelessWidget {
  const GameControls({
    required this.gameState,
    required this.onUndo,
    required this.onReset,
    required this.onHint,
    super.key,
  });

  final GameState gameState;
  final VoidCallback onUndo;
  final VoidCallback onReset;
  final VoidCallback onHint;

  @override
  Widget build(BuildContext context) {
    final isPlaying = gameState.status == GameStatus.playing;
    final hasPath = gameState.path.isNotEmpty;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSizes.lg,
        vertical: AppSizes.sm,
      ),
      child: Row(
        children: [
          // Reset button — purple gradient pill
          Expanded(
            flex: 3,
            child: _GradientPillButton(
              label: 'Reset',
              icon: Icons.refresh_rounded,
              gradient: const LinearGradient(
                colors: [AppColors.purpleGradientStart, AppColors.purpleGradientEnd],
              ),
              onPressed: isPlaying && hasPath ? onReset : null,
            ),
          ),
          const SizedBox(width: AppSizes.sm),

          // Hint button — outlined pill
          Expanded(
            flex: 3,
            child: _OutlinedPillButton(
              label: 'Hint',
              badgeCount: gameState.hintsUsed,
              onPressed: isPlaying ? onHint : null,
            ),
          ),
          const SizedBox(width: AppSizes.sm),

          // Undo button — dark circle
          _CircleIconButton(
            icon: Icons.undo_rounded,
            onPressed: isPlaying && hasPath ? onUndo : null,
          ),
        ],
      ),
    );
  }
}

/// Purple gradient pill button (like "Reset" in reference).
class _GradientPillButton extends StatelessWidget {
  const _GradientPillButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedOpacity(
          opacity: isEnabled ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: isEnabled ? gradient : null,
              color: isEnabled ? null : AppColors.cellBackground,
              borderRadius: BorderRadius.circular(26),
              boxShadow: isEnabled
                  ? [
                      BoxShadow(
                        color: AppColors.purpleGlow,
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isEnabled ? Colors.white : AppColors.textTertiaryDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  icon,
                  color: isEnabled ? Colors.white.withValues(alpha: 0.8) : AppColors.textTertiaryDark,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined pill button with optional badge (like "Hint" in reference).
class _OutlinedPillButton extends StatelessWidget {
  const _OutlinedPillButton({
    required this.label,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final String label;
  final VoidCallback? onPressed;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedOpacity(
          opacity: isEnabled ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isEnabled
                    ? AppColors.textSecondaryDark.withValues(alpha: 0.4)
                    : AppColors.cellBorder,
                width: 1.5,
              ),
              color: AppColors.deepBlack.withValues(alpha: 0.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isEnabled ? AppColors.textPrimaryDark : AppColors.textTertiaryDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (badgeCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.hintPurple,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark circle icon button (like "?" help button in reference).
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Semantics(
      button: true,
      label: 'Undo',
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedOpacity(
          opacity: isEnabled ? 1.0 : 0.3,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.elevatedSurface,
              border: Border.all(
                color: AppColors.cellBorder,
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: isEnabled ? AppColors.textPrimaryDark : AppColors.textTertiaryDark,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
