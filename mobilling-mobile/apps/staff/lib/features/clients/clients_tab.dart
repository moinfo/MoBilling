import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';
import '../common/paged_list.dart';

/// Searchable client list. A tab body inside the home shell — the shell owns
/// the masthead, so this starts with the search.
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

  @override
  Widget build(BuildContext context) {
    return Column(
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
              Spacing.xl,
            ),
            itemBuilder: (context, client) => _ClientRow(client: client),
            emptyIcon: Icons.people_outline,
            emptyTitle: 'No clients found',
            emptyMessage: 'Try another name, email or phone number.',
          ),
        ),
      ],
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
          child: _Meta([
            if (client.phone != null) client.phone!,
            if (services > 0)
              '${Formatting.integer(services)} active ${services == 1 ? 'service' : 'services'}',
          ].join(' · ')),
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
