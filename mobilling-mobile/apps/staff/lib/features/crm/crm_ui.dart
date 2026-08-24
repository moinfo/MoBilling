import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared pieces across the CRM screens. These are field-work screens, so the
/// recurring shapes are: an async body, a filter strip, one-tap contact, and
/// the grouped list and bottom sheet every module here is built from.

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

/// Quiet filter chips in one row under the masthead. `null` value means
/// "all". The selected chip borrows signal blue — the colour this app keeps
/// for a choice — rather than a status hue that would say something about
/// the rows it filters.
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        itemCount: options.length,
        separatorBuilder: (context, index) => const SizedBox(width: Spacing.sm),
        itemBuilder: (context, index) {
          final (value, label) = options[index];
          final on = selected == value;
          return ChoiceChip(
            label: Text(label.toUpperCase()),
            labelStyle: theme.textTheme.labelSmall?.copyWith(
              color: on ? scheme.primary : scheme.onSurfaceVariant,
            ),
            selected: on,
            showCheckmark: false,
            selectedColor: scheme.primary.withValues(alpha: 0.10),
            backgroundColor: theme.cardTheme.color,
            side: BorderSide(
              color: on
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant,
            ),
            onSelected: (_) => onSelect(value),
          );
        },
      ),
    );
  }
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
        icon: Icon(
          Icons.call_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
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
///
/// [compact] draws the stars as plain 16px glyphs for a list row's trailing
/// column; the tappable size is for the sheet where a rating is entered.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.onChanged,
    this.compact = false,
  });

  final int? rating;
  final ValueChanged<int>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final value = rating ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final color = context.statusColors.attention;

    if (compact && onChanged == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            Icon(
              star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 16,
              color: star <= value ? color : scheme.outline,
            ),
        ],
      );
    }

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

/// Small label/value line used in the detail sheets: a mono eyebrow naming
/// the value, the value itself in the body face.
class CrmDetailRow extends StatelessWidget {
  const CrmDetailRow(this.label, this.value, {super.key});

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
            width: 116,
            child: Padding(
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

void showCrmMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// A group of rows on one paper card, hairlines between them — the list
/// shape the dashboard uses, so a list of calls and a list of invoices are
/// recognisably the same instrument.
class CrmCardList extends StatelessWidget {
  const CrmCardList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const Divider(height: 1),
          child,
        ],
      ],
    ),
  );
}

/// The mono metadata line under a row's title: `INV-1042 · 12 AUG 2026`.
/// Upper-cased here; pass references, dates and counts — never a sentence.
class CrmMetaLine extends StatelessWidget {
  const CrmMetaLine(this.text, {super.key, this.color});

  final String text;

  /// A status tone when the line itself is the news (`3D LATE`).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A dense status chip beside a [CrmMetaLine] — the subtitle row of every
/// list here, so the trailing column stays free for a figure.
class CrmStatusLine extends StatelessWidget {
  const CrmStatusLine({
    super.key,
    required this.status,
    required this.meta,
    this.tone,
  });

  final String? status;
  final String meta;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      StatusChip(status, dense: true),
      if (meta.isNotEmpty) ...[
        const SizedBox(width: Spacing.sm),
        Flexible(child: CrmMetaLine(meta, color: tone)),
      ],
    ],
  );
}

/// A form control under its label, as the sign-in form sets them: the label
/// above in the title face, the hint inside the field.
class CrmField extends StatelessWidget {
  const CrmField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: Spacing.sm),
      child,
    ],
  );
}

/// A read-only field that opens a picker — the date controls on the sheets.
/// [placeholder] sets the value in hint grey when nothing is chosen yet.
class CrmPickerField extends StatelessWidget {
  const CrmPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = false,
    this.icon = Icons.calendar_today_outlined,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool placeholder;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CrmField(
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(suffixIcon: Icon(icon, size: 18)),
          child: Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: placeholder
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
                  : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a bottom sheet the way every CRM sheet opens: drag handle, the
/// sheet radius, and room for the keyboard.
Future<T?> showCrmSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
  builder: builder,
);

/// The body of a CRM bottom sheet: an eyebrow naming the context (the
/// client, the module), the title in the display face, then the form.
/// Scrolls, and keeps its bottom edge above the keyboard.
class CrmSheet extends StatelessWidget {
  const CrmSheet({
    super.key,
    required this.title,
    required this.children,
    this.eyebrow,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        sheetBottomInset(context) + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (eyebrow != null && eyebrow!.isNotEmpty) ...[
              Text(
                eyebrow!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.xs),
            ],
            Text(
              title,
              style: Type.display(22, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: Spacing.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}
