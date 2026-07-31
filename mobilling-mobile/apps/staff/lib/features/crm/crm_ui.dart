import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared pieces across the CRM screens. These are field-work screens, so the
/// recurring shapes are: an async body, a filter strip, and one-tap contact.

/// Renders an AsyncValue with consistent loading / error / retry treatment.
class CrmAsyncView<T> extends StatelessWidget {
  const CrmAsyncView({
    super.key,
    required this.value,
    required this.builder,
    required this.errorTitle,
    required this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final String errorTitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: errorTitle,
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: onRetry,
        ),
        data: builder,
      );
}

/// Horizontal filter chips. `null` value means "all".
class FilterStrip extends StatelessWidget {
  const FilterStrip({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<(String?, String)> options;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.sm),
          itemCount: options.length,
          separatorBuilder: (context, index) =>
              const SizedBox(width: Spacing.sm),
          itemBuilder: (context, index) {
            final (value, label) = options[index];
            return FilterChip(
              label: Text(label),
              selected: selected == value,
              showCheckmark: false,
              onSelected: (_) => onSelect(value),
            );
          },
        ),
      );
}

/// Call / message buttons. The whole point of these screens is the phone in
/// your hand, so a number on screen should always be one tap from dialling.
class ContactRow extends StatelessWidget {
  const ContactRow({super.key, this.phone, this.compact = false});

  final String? phone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final number = phone;
    if (number == null || number.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    if (compact) {
      return IconButton(
        icon: const Icon(Icons.call_outlined),
        tooltip: 'Call $number',
        visualDensity: VisualDensity.compact,
        onPressed: () => launchUrl(Uri(scheme: 'tel', path: number)),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.call_outlined, size: 18),
            label: const Text('Call'),
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: number)),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.sms_outlined, size: 18),
            label: const Text('SMS'),
            onPressed: () => launchUrl(Uri(scheme: 'sms', path: number)),
          ),
        ),
      ],
    );
  }
}

/// A star rating input/display for satisfaction feedback.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.onChanged});

  final int? rating;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final value = rating ?? 0;
    final color = context.statusColors.attention;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
              color: star <= value ? color : null,
            ),
            onPressed: onChanged == null ? null : () => onChanged!(star),
          ),
      ],
    );
  }
}

/// Small label/value line used in the detail sheets.
class CrmDetailRow extends StatelessWidget {
  const CrmDetailRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

void showCrmMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}
