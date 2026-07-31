import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

/// Small widgets and helpers shared by the four comms screens. Nothing here is
/// general enough for `mobilling_ui` — it exists to keep the screens readable.

/// Renders the three states of an [AsyncValue] the way the rest of the staff
/// app does, so a comms tab that fails looks like a tickets tab that fails.
class CommsAsyncView<T> extends StatelessWidget {
  const CommsAsyncView({
    super.key,
    required this.value,
    required this.errorTitle,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final String errorTitle;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: errorTitle,
          message: error is ApiException ? error.message : null,
          actionLabel: onRetry == null ? null : 'Retry',
          onAction: onRetry,
        ),
        data: (data) => builder(context, data),
      );
}

/// Full-width segmented control for switching sections within one screen.
class SectionSelector<T> extends StatelessWidget {
  const SectionSelector({
    super.key,
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final List<(T value, String label)> sections;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final (value, label) in sections)
                ButtonSegment<T>(value: value, label: Text(label)),
            ],
            selected: {selected},
            onSelectionChanged: (values) => onSelected(values.first),
          ),
        ),
      );
}

/// A tinted pill whose text and colour are supplied separately.
///
/// [StatusChip] derives both from one raw status string, which is right for
/// document statuses but wrong for these modules: the planner's `posted` and
/// the pipeline's `order_complete` are unknown to its colour map, and remapping
/// them onto words it does know (`completed`) would fix the colour while
/// printing the wrong label. Here the caller decides both.
class CommsChip extends StatelessWidget {
  const CommsChip({
    super.key,
    required this.label,
    required this.color,
    this.dense = true,
  });

  final String label;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Spacing.sm : Spacing.sm + 2,
        vertical: dense ? 2 : Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: (dense
                ? theme.textTheme.labelSmall
                : theme.textTheme.labelMedium)
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A label/value line, as used in the detail sheets.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// A section heading inside a scrolling screen.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleSmall),
            ),
            ?trailing,
          ],
        ),
      );
}

/// Feedback for a completed action.
///
/// Takes the messenger rather than a [BuildContext] because every caller is
/// past an `await` by the time it reports, and a context captured before that
/// await may no longer be mounted.
void showCommsMessage(
  ScaffoldMessengerState messenger,
  String message, {
  bool isError = false,
}) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? const Color(0xFFC92A2A) : null,
    ),
  );
}

/// The message to show for a failed call — [ApiException] already carries the
/// server's validation text, and anything else is a bug we should not paper
/// over with a friendly lie.
String commsErrorText(Object error) =>
    error is ApiException ? error.message : 'Something went wrong.';
