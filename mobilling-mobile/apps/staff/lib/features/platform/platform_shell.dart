import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../navigation/admin_menu.dart';
import '../../providers.dart';
import '../auth/account_sheet.dart';
import '../auth/session_expired_sheet.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmCardList, CrmMetaLine;
import 'platform_providers.dart';

/// The platform super-admin home: the operator's own money, then the menu.
///
/// A super admin has no tenant, so there is no bottom bar to scope — the
/// whole shell is one scrolling console. It gets the same ink masthead and
/// money panel as the staff dashboard, because it answers the same kind of
/// question one level up: how is this business doing?
class PlatformHomeScreen extends ConsumerStatefulWidget {
  const PlatformHomeScreen({super.key});

  @override
  ConsumerState<PlatformHomeScreen> createState() => _PlatformHomeScreenState();
}

class _PlatformHomeScreenState extends ConsumerState<PlatformHomeScreen> {
  bool _promptOpen = false;

  Future<void> _promptReauthentication() async {
    if (_promptOpen) return;
    _promptOpen = true;
    try {
      await SessionExpiredSheet.show(context);
    } finally {
      _promptOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(platformDashboardProvider);
    final user = ref.watch(currentUserProvider);
    final theme = Theme.of(context);

    ref.listen<SessionStatus>(sessionStatusProvider, (previous, next) {
      if (next == SessionStatus.expired) _promptReauthentication();
    });

    final d = dashboard.valueOrNull;
    // The ink panel only exists once the totals are in; until then the
    // masthead keeps its own edge and the content starts on paper.
    final overlap = d != null;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Platform',
        title: 'Console',
        edge: !overlap,
        trailing: InkAvatar(
          name: user?.name ?? '',
          onTap: () => AccountSheet.show(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(platformDashboardProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: Spacing.xl - (overlap ? _MoneyPanel.overlap : 0),
          ),
          children: [
            if (d != null)
              _MoneyPanel(
                eyebrow: 'Platform · all time',
                label: 'SMS revenue',
                amount: d.totalSmsRevenue,
                strip: [
                  (
                    label: 'Tenants',
                    value:
                        '${Formatting.integer(d.activeTenants)}/'
                        '${Formatting.integer(d.totalTenants)}',
                    tone: null,
                  ),
                  (
                    label: 'Users',
                    value: Formatting.compact(d.totalUsers),
                    tone: null,
                  ),
                  (
                    label: 'SMS sold',
                    value: Formatting.compact(d.totalSmsSold),
                    tone: null,
                  ),
                ],
              ),
            // Layout keeps the panel's extra bottom padding; the paint moves
            // up by the overlap, and the list's bottom padding gives the same
            // amount back.
            Transform.translate(
              offset: Offset(0, overlap ? -_MoneyPanel.overlap : 0),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  Spacing.md,
                  overlap ? 0 : Spacing.md,
                  Spacing.md,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (d == null)
                      const Padding(
                        padding: EdgeInsets.all(Spacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      _RaisedFirst(
                        child: _StockCard(
                          dashboard: d,
                          onReview: () =>
                              context.push(AdminRoutes.smsPurchases),
                        ),
                      ),
                    const SizedBox(height: Spacing.lg),
                    const SectionHeader('Manage'),
                    const SizedBox(height: Spacing.sm),
                    Card(
                      child: Column(
                        children: [
                          for (final (i, entry) in adminMenu.indexed)
                            // Skip the dashboard itself — we're on it.
                            if (entry.path != AdminRoutes.home) ...[
                              if (i > 1) const Divider(height: 1),
                              ListTile(
                                leading: Icon(entry.icon, size: 20),
                                title: Text(
                                  entry.label,
                                  style: theme.textTheme.titleSmall,
                                ),
                                subtitle: entry.subtitle == null
                                    ? null
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          entry.subtitle!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                trailing: Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                  color: theme.colorScheme.outline,
                                ),
                                onTap: () => context.push(entry.path),
                              ),
                            ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The platform's own SMS stock, riding over the ink.
///
/// Running the reseller balance dry stops every tenant's messaging, so it is
/// the figure the console leads with after revenue — and purchases waiting on
/// a human sit in the same card, because they are the other thing only this
/// screen can act on.
class _StockCard extends StatelessWidget {
  const _StockCard({required this.dashboard, required this.onReview});

  final PlatformDashboard dashboard;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final balance = dashboard.masterSmsBalance;
    final low = balance != null && balance < 1000;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MASTER SMS BALANCE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  balance == null ? '—' : Formatting.integer(balance),
                  style: TextStyle(
                    fontSize: MoneyScale.headline.size,
                    fontWeight: FontWeight.w700,
                    letterSpacing: MoneyScale.headline.size * -0.02,
                    height: 1,
                    color: low ? status.overdue : scheme.onSurface,
                    fontFeatures: Type.figures,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Flexible(
                  child: CrmMetaLine(
                    balance == null
                        ? 'upstream balance unavailable'
                        : '${Formatting.integer(dashboard.smsEnabledTenants)} '
                              'tenants sending',
                    color: low ? status.overdue : null,
                  ),
                ),
              ],
            ),
            if (dashboard.pendingPurchases > 0) ...[
              const Divider(height: Spacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${Formatting.integer(dashboard.pendingPurchases)} SMS '
                      'purchase'
                      '${dashboard.pendingPurchases == 1 ? '' : 's'} '
                      'awaiting confirmation',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  TextButton(onPressed: onReview, child: const Text('Review')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A simple list screen used by the reference-data areas (plans, currencies,
/// SMS packages, permissions, role templates) — each is a short list where
/// the interesting content is the row itself.
///
/// [itemBuilder] returns a bare row; the scaffold gathers them onto one paper
/// card with hairlines between, which is how every list in this app is set.
class PlatformListScaffold<T> extends ConsumerWidget {
  const PlatformListScaffold({
    super.key,
    required this.title,
    required this.value,
    required this.itemBuilder,
    required this.onRetry,
    required this.emptyIcon,
    required this.emptyTitle,
    this.eyebrow = 'Platform',
    this.footnote,
    this.floatingActionButton,
  });

  final String title;

  /// The masthead eyebrow — 'Tenant' for the areas reached through one.
  final String eyebrow;
  final AsyncValue<List<T>> value;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final VoidCallback onRetry;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? footnote;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: ShellTopBar(eyebrow: eyebrow, title: title),
      floatingActionButton: floatingActionButton,
      body: CrmAsyncView(
        value: value,
        errorTitle: 'Could not load $title',
        onRetry: onRetry,
        builder: (items) => items.isEmpty
            ? StateMessage(icon: emptyIcon, title: emptyTitle)
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.xl,
                ),
                children: [
                  CrmCardList(
                    children: [
                      for (final item in items) itemBuilder(context, item),
                    ],
                  ),
                  if (footnote != null) ...[
                    const SizedBox(height: Spacing.md),
                    Text(
                      footnote!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private building blocks — the dashboard's ink devices, kept private here
// (candidates for mobilling_ui)
// ---------------------------------------------------------------------------

/// One figure in the money panel's strip.
typedef _StripFigure = ({String label, String value, Color? tone});

/// The platform's money, on ink.
///
/// The sign-in panel's composition: eyebrow pill, a display-face figure in
/// white, and the handoff's translucent stat strip beneath it for the figures
/// that explain it. The blue glow is left to the masthead above and only the
/// green one is drawn here, so the two panels read as a single surface.
class _MoneyPanel extends StatelessWidget {
  const _MoneyPanel({
    required this.eyebrow,
    required this.label,
    required this.amount,
    required this.strip,
  });

  final String eyebrow;
  final String label;
  final Object? amount;
  final List<_StripFigure> strip;

  /// How far the first paper card rides up over the panel's bottom edge.
  static const double overlap = 28;

  @override
  Widget build(BuildContext context) => InkPanel(
    rule: false,
    blueGlow: false,
    padding: const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.sm,
      Spacing.lg,
      Spacing.lg + overlap,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Reveal(child: EyebrowPill(eyebrow)),
        const SizedBox(height: Spacing.md),
        Reveal(
          delay: const Duration(milliseconds: 80),
          child: Text(
            label.toUpperCase(),
            style: Type.mono(10.5, tracking: 0.08, color: InkPanel.mutedText),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Reveal(
          delay: const Duration(milliseconds: 120),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Money(
              amount,
              scale: MoneyScale.display,
              display: true,
              color: Colors.white,
            ),
          ),
        ),
        if (strip.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          Reveal(
            delay: const Duration(milliseconds: 200),
            child: _StatStrip(figures: strip),
          ),
        ],
      ],
    ),
  );
}

/// The handoff's floating stat strip: translucent card, figures in the
/// display face, Plex Mono labels, hairline dividers between columns.
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.figures});

  final List<_StripFigure> figures;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: Spacing.sm,
      vertical: Spacing.md,
    ),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(Radii.cardRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
    ),
    child: IntrinsicHeight(
      child: Row(
        children: [
          for (final (i, f) in figures.indexed) ...[
            if (i > 0)
              VerticalDivider(
                width: 1,
                indent: 2,
                endIndent: 2,
                color: Colors.white.withValues(alpha: 0.14),
              ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      f.value,
                      style: Type.display(
                        22,
                        color: f.tone ?? Colors.white,
                      ).copyWith(fontFeatures: Type.figures),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    f.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.mono(
                      9.5,
                      tracking: 0.08,
                      color: InkPanel.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The first paper card, raised over the ink with the sign-in card's soft ink
/// shadow so the overlap reads as depth rather than as a misalignment.
class _RaisedFirst extends StatelessWidget {
  const _RaisedFirst({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: Radii.card,
      boxShadow: [
        BoxShadow(
          color: Brand.ink.withValues(alpha: 0.28),
          blurRadius: 44,
          offset: const Offset(0, 24),
          spreadRadius: -30,
        ),
      ],
    ),
    child: child,
  );
}
