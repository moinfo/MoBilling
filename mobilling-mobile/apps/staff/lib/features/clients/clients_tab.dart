import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';
import '../common/paged_list.dart';
import 'client_form_screen.dart';
import 'client_providers.dart';

/// Searchable client list. A tab body inside the home shell — the shell owns
/// the masthead, so this starts with the search.
///
/// It also owns the "new client" action, on its own Scaffold: the shell's
/// masthead belongs to whichever tab is showing, so a create button up there
/// would have to be wired through the shell for every tab that wants one.
class ClientsTab extends ConsumerStatefulWidget {
  const ClientsTab({super.key});

  @override
  ConsumerState<ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends ConsumerState<ClientsTab> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  /// The path from "met someone" to "they exist in the system". The list and
  /// the counters both move when it succeeds.
  Future<void> _newClient() async {
    final created = await Navigator.of(context).push<StaffClient>(
      MaterialPageRoute(builder: (_) => const ClientFormScreen()),
    );
    if (created == null || !mounted) return;
    ref.invalidate(clientCountersProvider);
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(Permissions.clientsCreate) ??
        false;

    return Scaffold(
      // The shell owns the masthead and the bottom bar; this scaffold exists
      // only to hang the create action off, so it must not paint a second
      // ground over the shell's.
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.sm,
            ),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search name, email or phone',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
          const _ClientCounters(),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) => ref
                  .read(staffServiceProvider)
                  .clients(
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    page: page,
                  ),
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.md,
                // Room for the create button to float clear of the last row.
                Spacing.xxl + Spacing.lg,
              ),
              itemBuilder: (context, client) => _ClientRow(client: client),
              emptyIcon: Icons.people_outline,
              emptyTitle: 'No clients found',
              emptyMessage: 'Try another name, email or phone number.',
            ),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              heroTag: 'new-client',
              onPressed: _newClient,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('New client'),
            )
          : null,
    );
  }
}

/// The counters the web puts above its client table. Silent while loading and
/// on failure: they are context for the list, never the reason the screen
/// exists, so a 403 or a slow call must not push the list down or block it.
class _ClientCounters extends ConsumerWidget {
  const _ClientCounters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counters = ref.watch(clientCountersProvider).valueOrNull;
    if (counters == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.sm),
      child: StatRail(
        items: [
          StatRailItem(
            label: 'Clients',
            value: Formatting.integer(counters.totalClients),
          ),
          StatRailItem(
            label: 'Buying',
            value: Formatting.integer(counters.withSubscriptions),
          ),
          StatRailItem(
            label: 'Services',
            value: Formatting.integer(counters.activeSubscriptions),
          ),
          StatRailItem(
            label: 'New',
            value: Formatting.integer(counters.newThisMonth),
          ),
          // Only present when the role may see money on this page.
          if (counters.subscriptionValue != null)
            StatRailItem(
              label: 'Value',
              value: Formatting.compact(counters.subscriptionValue),
            ),
        ],
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client});

  final StaffClient client;

  @override
  Widget build(BuildContext context) {
    final services = client.activeSubscriptionsCount;

    return Card(
      child: ListTile(
        leading: _Initial(client.name),
        title: Text(client.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: _Meta(
            [
              if (client.phone != null) client.phone!,
              if (services > 0)
                '${Formatting.integer(services)} active ${services == 1 ? 'service' : 'services'}',
            ].join(' · '),
          ),
        ),
        // Monthly recurring value — the one figure a client row is about.
        trailing: client.subscriptionTotal > 0
            ? Money(client.subscriptionTotal)
            : null,
        onTap: () => context.push(
          '${Routes.clientPath(client.id)}?name=${Uri.encodeComponent(client.name)}',
        ),
      ),
    );
  }
}

/// The client's initial in the masthead avatar's rounded square, translated
/// onto paper: a quiet container instead of a tinted circle.
class _Initial extends StatelessWidget {
  const _Initial(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Type.display(16, weight: 700, color: scheme.onSurface),
      ),
    );
  }
}

/// A mono metadata line — phone · services — in the eyebrow register.
class _Meta extends StatelessWidget {
  const _Meta(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
