import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';
import '../common/paged_list.dart';

/// Searchable client list.
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
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _listKey.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Search name, email or phone',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            fetch: (page) => ref.read(staffServiceProvider).clients(
                  search: _search.text.trim().isEmpty
                      ? null
                      : _search.text.trim(),
                  page: page,
                ),
            itemBuilder: (context, client) => _ClientRow(client: client),
            emptyIcon: Icons.people_outline,
            emptyTitle: 'No clients found',
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
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(client.name.isEmpty ? '?' : client.name[0].toUpperCase()),
        ),
        title: Text(client.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (client.phone != null) client.phone!,
            if (client.activeSubscriptionsCount > 0)
              '${client.activeSubscriptionsCount} active service${client.activeSubscriptionsCount == 1 ? '' : 's'}',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: client.subscriptionTotal > 0
            ? Text(Formatting.amount(client.subscriptionTotal),
                style: theme.textTheme.labelLarge)
            : null,
        onTap: () => context.push(
          '${Routes.clientPath(client.id)}?name=${Uri.encodeComponent(client.name)}',
        ),
      ),
    );
  }
}
