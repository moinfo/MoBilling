import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers.dart';
import '../../router.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show FilterStrip;
import 'client_form_screen.dart';
import 'client_providers.dart';

/// `StaffService.clients` takes no `sort` query param, so anything but the
/// default asks this screen to pull one large batch and order it in memory
/// rather than page normally — see `_ClientsTabState._fetchClients`.
enum _ClientSort { name, subscriptions, amount, newest }

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
  _ClientSort _sort = _ClientSort.name;
  String? _subsFilter; // null | 'with' | 'without'

  static const _subsFilters = <(String?, String)>[
    (null, 'All'),
    ('with', 'With Subscriptions'),
    ('without', 'No Subscriptions'),
  ];

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

  String? get _searchTerm =>
      _search.text.trim().isEmpty ? null : _search.text.trim();

  /// The plain paged fetch when nothing needs in-memory work, or the batch
  /// behind both the sort/filter fallback and the exports below.
  Future<List<StaffClient>> _bulkFetch() async {
    final page = await ref
        .read(staffServiceProvider)
        .clients(search: _searchTerm, perPage: 500);
    return switch (_subsFilter) {
      'with' => page.items
          .where((c) => c.activeSubscriptionsCount > 0)
          .toList(),
      'without' => page.items
          .where((c) => c.activeSubscriptionsCount == 0)
          .toList(),
      _ => page.items,
    };
  }

  Future<Paginated<StaffClient>> _fetchClients(int page) async {
    if (_sort == _ClientSort.name && _subsFilter == null) {
      return ref
          .read(staffServiceProvider)
          .clients(search: _searchTerm, page: page);
    }
    // Sorted/filtered view: one batch, ordered here, presented as a single
    // complete page so the list doesn't try to load a "page 2" of it.
    if (page > 1) return Paginated<StaffClient>.single(const []);
    final items = await _bulkFetch();
    switch (_sort) {
      case _ClientSort.subscriptions:
        items.sort(
          (a, b) =>
              b.activeSubscriptionsCount.compareTo(a.activeSubscriptionsCount),
        );
      case _ClientSort.amount:
        items.sort((a, b) => b.subscriptionTotal.compareTo(a.subscriptionTotal));
      case _ClientSort.newest:
        items.sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
      case _ClientSort.name:
        break;
    }
    return Paginated<StaffClient>.single(items);
  }

  Future<void> _shareText(String content, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], subject: filename);
  }

  String get _todayStamp => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _exportCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final clients = await _bulkFetch();
      String esc(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
      final rows = [
        [
          'Name',
          'Email',
          'Phone',
          'Address',
          'TIN',
          'Active Subscriptions',
          'Subscription Amount',
        ].join(','),
        for (final c in clients)
          [
            esc(c.name),
            esc(c.email),
            esc(c.phone),
            esc(c.address),
            esc(c.taxId),
            c.activeSubscriptionsCount,
            c.subscriptionTotal,
          ].join(','),
      ];
      await _shareText(rows.join('\n'), 'clients-$_todayStamp.csv');
    } on ApiException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _exportVcf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final clients = await _bulkFetch();
      final cards = clients.map((c) {
        final parts = c.name.trim().split(RegExp(r'\s+'));
        final last = parts.length > 1 ? parts.removeLast() : '';
        final first = parts.join(' ');
        return [
          'BEGIN:VCARD',
          'VERSION:3.0',
          'FN:${c.name}',
          'N:$last;$first;;;',
          if (c.email != null) 'EMAIL:${c.email}',
          if (c.phone != null) 'TEL;TYPE=CELL:${c.phone}',
          if (c.address != null) 'ADR;TYPE=WORK:;;${c.address};;;;',
          'END:VCARD',
        ].join('\r\n');
      });
      await _shareText(cards.join('\r\n'), 'clients-$_todayStamp.vcf');
    } on ApiException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  PopupMenuItem<String> _sortItem(String value, String label, _ClientSort key) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            _sort == key
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 16,
          ),
          const SizedBox(width: Spacing.sm),
          Text(label),
        ],
      ),
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
              decoration: InputDecoration(
                hintText: 'Search name, email or phone',
                prefixIcon: const Icon(Icons.search, size: 20),
                // Sort and export share this one menu rather than each
                // claiming their own row — both are occasional, not primary.
                suffixIcon: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  itemBuilder: (context) => [
                    _sortItem('sort_name', 'Name (A–Z)', _ClientSort.name),
                    _sortItem(
                      'sort_subscriptions',
                      'Most subscriptions',
                      _ClientSort.subscriptions,
                    ),
                    _sortItem(
                      'sort_amount',
                      'Highest sub. amount',
                      _ClientSort.amount,
                    ),
                    _sortItem(
                      'sort_newest',
                      'Newest first',
                      _ClientSort.newest,
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'export_csv',
                      child: Text('Export CSV'),
                    ),
                    const PopupMenuItem(
                      value: 'export_vcf',
                      child: Text('Export VCF'),
                    ),
                  ],
                  onSelected: (value) {
                    switch (value) {
                      case 'sort_name':
                        setState(() => _sort = _ClientSort.name);
                        break;
                      case 'sort_subscriptions':
                        setState(() => _sort = _ClientSort.subscriptions);
                        break;
                      case 'sort_amount':
                        setState(() => _sort = _ClientSort.amount);
                        break;
                      case 'sort_newest':
                        setState(() => _sort = _ClientSort.newest);
                        break;
                      case 'export_csv':
                        _exportCsv();
                        return;
                      case 'export_vcf':
                        _exportVcf();
                        return;
                    }
                    _listKey.currentState?.reload();
                  },
                ),
              ),
            ),
          ),
          FilterStrip(
            options: _subsFilters,
            selected: _subsFilter,
            onSelect: (v) {
              setState(() => _subsFilter = v);
              _listKey.currentState?.reload();
            },
          ),
          const _ClientCounters(),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: _fetchClients,
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
            label: 'Idle',
            value: Formatting.integer(counters.withoutSubscriptions),
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
