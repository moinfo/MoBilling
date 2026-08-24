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

/// Full-width segmented control for switching sections within one screen —
/// the quiet filter row under the masthead, never a second coloured bar.
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
        style: SegmentedButton.styleFrom(
          textStyle: Theme.of(context).textTheme.labelMedium,
        ),
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
/// printing the wrong label. Here the caller decides both; the typesetting is
/// [StatusChip]'s, so the two are indistinguishable on screen.
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
  Widget build(BuildContext context) => Container(
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
      label.toUpperCase(),
      style: Type.mono(dense ? 9.5 : 10.5, tracking: 0.08, color: color),
    ),
  );
}

/// A label/value line, as used in the detail sheets: a mono eyebrow naming
/// the value, the value itself in the body face.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Padding(
              // Sits the eyebrow on the value's first line.
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// A section heading inside a scrolling screen: the app's eyebrow-and-rule
/// [SectionHeader], with the gap the brief asks for beneath it.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Spacing.sm),
    child: SectionHeader(text, trailing: trailing),
  );
}

/// The label above a form field, as the sign-in screen sets it.
class CommsFieldLabel extends StatelessWidget {
  const CommsFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);
}

/// A metadata line — `reference · date` — in the utility face, as a list
/// row's subtitle. Not upper-cased: these lines carry people's names.
class CommsMeta extends StatelessWidget {
  const CommsMeta(this.text, {super.key, this.maxLines = 1});

  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The head of a bottom sheet: an eyebrow naming the context, the title in
/// the display face, and room for a chip or an action at the far end.
class CommsSheetHeader extends StatelessWidget {
  const CommsSheetHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null && eyebrow!.isNotEmpty) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
              ],
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Type.display(22, color: theme.colorScheme.onSurface),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: Spacing.sm),
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: trailing,
          ),
        ],
      ],
    );
  }
}

/// The sheet shape every comms sheet uses.
const RoundedRectangleBorder commsSheetShape = RoundedRectangleBorder(
  borderRadius: Radii.sheet,
);

/// Feedback for a completed action.
///
/// Takes the messenger rather than a [BuildContext] because every caller is
/// past an `await` by the time it reports, and a context captured before that
/// await may no longer be mounted. Form errors do not come here — they go in
/// an [ErrorBanner] above the form.
void showCommsMessage(
  ScaffoldMessengerState messenger,
  String message, {
  bool isError = false,
}) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError
          ? Theme.of(messenger.context).colorScheme.error
          : null,
    ),
  );
}

/// The message to show for a failed call — [ApiException] already carries the
/// server's validation text, and anything else is a bug we should not paper
/// over with a friendly lie.
String commsErrorText(Object error) =>
    error is ApiException ? error.message : 'Something went wrong.';
