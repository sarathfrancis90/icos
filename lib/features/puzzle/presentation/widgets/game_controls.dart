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
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: Icons.undo_rounded,
            label: 'Undo',
            onPressed: isPlaying && hasPath ? onUndo : null,
          ),
          _ControlButton(
            icon: Icons.refresh_rounded,
            label: 'Reset',
            onPressed: isPlaying && hasPath ? onReset : null,
          ),
          _ControlButton(
            icon: Icons.lightbulb_outline_rounded,
            label: 'Hint',
            badgeCount: gameState.hintsUsed,
            color: AppColors.hintPurple,
            onPressed: isPlaying ? onHint : null,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badgeCount = 0,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final int badgeCount;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final iconColor = isEnabled
        ? (color ?? Theme.of(context).colorScheme.primary)
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3);

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSizes.sm + 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: badgeCount > 0,
                label: Text('$badgeCount'),
                child: Icon(icon, size: 28, color: iconColor),
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: iconColor,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
