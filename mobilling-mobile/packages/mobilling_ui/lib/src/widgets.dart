import 'package:flutter/material.dart';

import 'theme.dart';

/// A coloured pill for a document, service or domain status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});

  final String? status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final color = colors.forStatus(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Spacing.sm : Spacing.sm + 2,
        vertical: dense ? 2 : Spacing.xs,
      ),
      decoration: BoxDecoration(
        // Tinted rather than filled: a list of invoices is mostly statuses, and
        // solid blocks of colour turn a scannable list into a stripe of noise.
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        StatusColors.label(status),
        style: (dense
                ? Theme.of(context).textTheme.labelSmall
                : Theme.of(context).textTheme.labelMedium)
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Full-screen placeholder for an empty list, an error, or a blocked action.
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: Spacing.md),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                message!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Spacing.lg),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline banner for a recoverable error above otherwise-usable content.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: Radii.card,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// A labelled figure, as used across the dashboard summary.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.emphasis,
    this.icon,
  });

  final String label;
  final String value;

  /// Optional accent — used to make an outstanding balance read as urgent
  /// without turning every figure into a colour.
  final Color? emphasis;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: Spacing.xs),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: emphasis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
