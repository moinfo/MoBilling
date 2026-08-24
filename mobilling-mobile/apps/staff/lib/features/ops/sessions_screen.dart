import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart' show CrmAsyncView, FilterStrip;
import 'ops_providers.dart';

/// Who is still signed in — staff and client portal logins alike — with
/// one-tap revoke.
///
/// Sanctum tokens never expire here and deactivating an account doesn't
/// revoke its existing tokens, so a leaver can keep a working session until
/// someone revokes it from this screen.
class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _type;
  String? _activeFilter; // 'active' | 'inactive' | null

  static const _typeFilters = <(String?, String)>[
    (null, 'Everyone'),
    ('staff', 'Staff'),
    ('client', 'Clients'),
  ];

  SessionsFilter get _filter => SessionsFilter(
    type: _type,
    active: switch (_activeFilter) {
      'active' => true,
      'inactive' => false,
      _ => null,
    },
    search: _search.text.trim().isEmpty ? null : _search.text.trim(),
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(sessionsProvider(_filter));
    final status = context.statusColors;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Account',
        title: 'Active sessions',
        trailing: InkActionButton(
          icon: Icons.cleaning_services_outlined,
          tooltip: 'Revoke sessions on deactivated accounts',
          onPressed: () => _bulkRevoke(context, page.valueOrNull?.summary),
        ),
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search name, email or client',
          onChanged: _onSearchChanged,
        ),
      ),
      body: Column(
        children: [
          FilterStrip(
            options: _typeFilters,
            selected: _type,
            onSelect: (v) => setState(() => _type = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, 0),
            child: SegmentedButton<String?>(
              segments: const [
                ButtonSegment(value: null, label: Text('All')),
                ButtonSegment(value: 'active', label: Text('Active')),
                ButtonSegment(value: 'inactive', label: Text('Deactivated')),
              ],
              selected: {_activeFilter},
              onSelectionChanged: (s) =>
                  setState(() => _activeFilter = s.first),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Expanded(
            child: CrmAsyncView(
              value: page,
              errorTitle: 'Could not load sessions',
              onRetry: () => ref.invalidate(sessionsProvider(_filter)),
              builder: (data) => RefreshIndicator(
                onRefresh: () => ref.refresh(sessionsProvider(_filter).future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.sm,
                    Spacing.md,
                    Spacing.xl,
                  ),
                  children: [
                    StatRail(
                      items: [
                        StatRailItem(
                          label: 'Sessions',
                          value: Formatting.integer(data.summary.total),
                        ),
                        StatRailItem(
                          label: 'On deactivated',
                          value: Formatting.integer(data.summary.onInactive),
                          emphasis: data.summary.onInactive > 0
                              ? status.overdue
                              : null,
                        ),
                        StatRailItem(
                          label: 'Never used',
                          value: Formatting.integer(data.summary.neverUsed),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.lg),
                    const SectionHeader('Signed in'),
                    const SizedBox(height: Spacing.sm),
                    if (data.sessions.isEmpty)
                      const SizedBox(
                        height: 240,
                        child: StateMessage(
                          icon: Icons.devices_other_outlined,
                          title: 'No sessions match',
                          message: 'Try another name, or widen the filters.',
                        ),
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (final (i, s) in data.sessions.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              _SessionRow(
                                session: s,
                                onRevoke: () => _revoke(context, s),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(BuildContext context, ActiveSession s) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign out ${s.ownerName}?'),
        content: const Text(
          'Their current session ends immediately. They can sign in again if their account is active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke session'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    try {
      await ref.read(opsServiceProvider).revokeSession(s.id);
      ref.invalidate(sessionsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Session revoked.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _bulkRevoke(
    BuildContext context,
    SessionsSummary? summary,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    var includeNeverUsed = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Revoke stale sessions?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Every session on a deactivated account is revoked — '
                '${Formatting.integer(summary?.onInactive ?? 0)} right now. '
                'Sessions on active accounts are never touched.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Also revoke never-used tokens'),
                subtitle: Text(
                  '${Formatting.integer(summary?.neverUsed ?? 0)} of them',
                ),
                value: includeNeverUsed,
                onChanged: (v) => setState(() => includeNeverUsed = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Revoke sessions'),
            ),
          ],
        ),
      ),
    );
    if (!(confirmed ?? false)) return;
    try {
      final message = await ref
          .read(opsServiceProvider)
          .revokeInactiveSessions(includeNeverUsed: includeNeverUsed);
      ref.invalidate(sessionsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Sessions revoked.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// One token: owner, an account-state chip, and a mono line saying whose it
/// is and when it last spoke to the API. A deactivated owner turns the line
/// orange — that row is the reason this screen exists.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.onRevoke});

  final ActiveSession session;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final s = session;

    return ListTile(
      dense: true,
      title: Text(
        s.ownerName,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            StatusChip(
              s.effectivelyActive ? 'active' : 'deactivated',
              dense: true,
            ),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                [
                  s.isStaff ? 'Staff' : 'Client · ${s.clientName ?? '—'}',
                  s.neverUsed
                      ? 'never used'
                      : 'used ${Formatting.dateTime(s.lastUsedAt)}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: s.effectivelyActive
                      ? theme.colorScheme.onSurfaceVariant
                      : status.overdue,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.logout_rounded, size: 20),
        tooltip: 'Revoke session',
        onPressed: onRevoke,
      ),
    );
  }
}
