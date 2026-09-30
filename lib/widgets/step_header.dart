import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// Mynugen-style step header: step X of Y, progress bar, optional title and subtitle.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.step,
    required this.totalSteps,
    this.title,
    this.subtitle,
    this.showProgress = true,
  });

  final int step;
  final int totalSteps;
  final String? title;
  final String? subtitle;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = totalSteps > 0 ? (step / totalSteps).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $step of $totalSteps',
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppPalette.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (showProgress) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppPalette.border,
              valueColor: const AlwaysStoppedAnimation<Color>(AppPalette.gold),
              minHeight: 6,
            ),
          ),
        ],
        if (title != null && title!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            title!,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppPalette.ink,
            ),
          ),
        ],
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppPalette.muted,
            ),
          ),
        ],
      ],
    );
  }
}
