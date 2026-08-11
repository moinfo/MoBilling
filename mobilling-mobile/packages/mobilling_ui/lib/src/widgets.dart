import 'package:flutter/material.dart';

import 'formatting.dart';
import 'theme.dart';

/// How large a [Money] readout is set. The ratios between the three parts
/// hold at every step, so a figure is recognisable as the same instrument
/// whether it is the hero of a dashboard or the trailing column of a list.
enum MoneyScale {
  /// The one figure a screen is about — an invoice total, a wallet balance.
  display(34),

  /// Section-level figures: a stat tile, a summary row. Sized so a
  /// seven-figure amount still fits a half-width tile without the tile's
  /// FittedBox having to shrink it — a grid where each tile picks its own
  /// size stops reading as a grid.
  headline(21),

  /// The trailing amount on a list row.
  row(16),

  /// Inside a chip, a table cell, or a two-line subtitle.
  dense(13);

  const MoneyScale(this.size);

  /// Point size of the integer part; everything else is derived from it.
  final double size;
}

/// The money readout — this app's signature.
///
/// A figure is not a sentence, so it is not set like one. The currency code
/// is small, wide-tracked and quiet because it rarely changes; the integer
/// part is large, tight and heavy because it is the thing being read; the
/// decimals step down because in a business that invoices in thousands, the
/// cents are a footnote you still have to be able to audit.
///
/// The three parts share an alphabetic baseline, which is what makes a column
/// of these line up as an instrument rather than as three columns of text.
/// Combined with [Type.figures] the digits are fixed-width, so a value can
/// change under a live refresh without the row reflowing.
class Money extends StatelessWidget {
  const Money(
    this.amount, {
    super.key,
    this.scale = MoneyScale.row,
    this.color,
    this.currencyCode,
    this.showCode = true,
  });

  /// num or String — the API sends both for the same field. See
  /// [Formatting.parts].
  final Object? amount;
  final MoneyScale scale;

  /// Overrides the integer part's colour. Use a [StatusColors] value to make
  /// a figure carry its own state; leave null everywhere else, because a
  /// screen where every number is coloured is a screen with no emphasis.
  final Color? color;

  /// Defaults to the tenant's currency.
  final String? currencyCode;

  /// Drop the code where a header or label already establishes the currency.
  final bool showCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = Formatting.parts(amount, currencyCode: currencyCode);

    final primary = color ?? theme.colorScheme.onSurface;
    // The quiet parts are the loud part, faded — so a coloured figure stays
    // one object instead of a number wearing two unrelated greys.
    final quiet = Color.alphaBlend(
      primary.withValues(alpha: 0.55),
      theme.colorScheme.surface,
    );

    final unit = scale.size;

    return Semantics(
      label: parts.plain,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (showCode) ...[
            Text(
              parts.code,
              style: TextStyle(
                fontFamily: Type.family,
                fontSize: (unit * 0.36).clamp(10, 14),
                fontWeight: FontWeight.w700,
                letterSpacing: Type.eyebrowTracking,
                color: quiet,
                height: 1,
              ),
            ),
            SizedBox(width: unit * 0.18),
          ],
          Text(
            parts.whole,
            style: TextStyle(
              fontFamily: Type.family,
              fontSize: unit,
              fontWeight: FontWeight.w700,
              // Large figures set at default tracking look loose; pulling them
              // in is what makes the number read as one quantity.
              letterSpacing: unit * -0.02,
              color: primary,
              height: 1,
              fontFeatures: Type.figures,
            ),
          ),
          Text(
            '.${parts.fraction}',
            style: TextStyle(
              fontFamily: Type.family,
              fontSize: unit * 0.58,
              fontWeight: FontWeight.w600,
              color: quiet,
              height: 1,
              fontFeatures: Type.figures,
            ),
          ),
        ],
      ),
    );
  }
}

/// The company mark, drawn from the package's own asset.
///
/// Deliberately unadorned — no circle, no card, no shadow behind it. The mark
/// already has its own geometry; framing it just makes two shapes fight.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/moinfotech-logo.png',
        package: 'mobilling_ui',
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Moinfotech',
      );
}

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

/// The heading that separates one group of content from the next.
///
/// Eyebrow plus a rule that runs to the edge. The rule is what does the
/// separating, so the cards below need no heavier framing of their own —
/// which is what keeps a screen of five sections from reading as five
/// competing boxes. Shared across all three shells so a staff screen and a
/// client screen are recognisably the same product.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;

  /// An optional action at the far end — "See all", a filter. Sits after the
  /// rule so the rule still visibly divides.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: Type.eyebrowTracking,
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ),
        if (trailing != null) ...[
          const SizedBox(width: Spacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

/// One column of a [StatRail].
class StatRailItem {
  const StatRailItem({
    required this.label,
    required this.value,
    this.emphasis,
    this.onTap,
  });

  /// Kept to one word where possible — four of these share a phone's width,
  /// and a truncated label is worse than a terse one.
  final String label;
  final String value;

  /// Colour the figure only when its value is itself the news: unpaid
  /// invoices when there are some, open tickets when there are some.
  final Color? emphasis;

  final VoidCallback? onTap;
}

/// A row of small counts, set as one instrument panel rather than as several
/// cards.
///
/// A count is a single digit most of the time. Giving each one a card spends
/// a third of the screen restating what four short words and four numbers
/// could say in one strip — and pushes the content people actually came for
/// below the fold. The dividers do the separating that four card edges were
/// doing, at a fraction of the height.
class StatRail extends StatelessWidget {
  const StatRail({super.key, required this.items});

  final List<StatRailItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: SizedBox(
        height: 74,
        child: Row(
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  indent: Spacing.md,
                  endIndent: Spacing.md,
                  color: theme.colorScheme.outlineVariant,
                ),
              Expanded(
                child: InkWell(
                  onTap: item.onTap,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.value,
                        style: TextStyle(
                          fontFamily: Type.family,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: item.emphasis ?? theme.colorScheme.onSurface,
                          fontFeatures: Type.figures,
                        ),
                      ),
                      const SizedBox(height: Spacing.xs + 2),
                      Text(
                        item.label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: Type.eyebrowTracking,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A labelled figure, as used across the dashboard summary.
///
/// The label is set as an eyebrow — small, tracked, upper-case — so that it
/// reads as the *name of* the figure rather than as a competing line of text.
/// That is the only place in the app upper-case is used.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.emphasis,
    this.icon,
  })  : amount = null,
        currencyCode = null;

  /// A tile whose figure is money. Prefer this over passing a pre-formatted
  /// string: it routes through [Money], so the amount is typeset like every
  /// other amount in the app instead of like a caption that happens to
  /// contain digits.
  const StatTile.money({
    super.key,
    required this.label,
    required this.amount,
    this.emphasis,
    this.icon,
    this.currencyCode,
  }) : value = null;

  final String label;

  /// A non-monetary figure — a count, a date, a percentage.
  final String? value;

  /// Set by [StatTile.money].
  final Object? amount;
  final String? currencyCode;

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
                  Icon(icon, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: Type.eyebrowTracking,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: amount != null
                  ? Money(
                      amount,
                      scale: MoneyScale.headline,
                      color: emphasis,
                      currencyCode: currencyCode,
                    )
                  : Text(
                      value!,
                      // Matched to the money readout by construction, so a
                      // count tile and an amount tile sit at the same weight
                      // in the same grid.
                      style: TextStyle(
                        fontFamily: Type.family,
                        fontSize: MoneyScale.headline.size,
                        fontWeight: FontWeight.w700,
                        letterSpacing: MoneyScale.headline.size * -0.02,
                        height: 1,
                        color: emphasis ?? theme.colorScheme.onSurface,
                        fontFeatures: Type.figures,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
