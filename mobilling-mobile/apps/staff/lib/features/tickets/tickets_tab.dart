import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';

/// The staff ticket queue.
class TicketsTab extends ConsumerStatefulWidget {
  const TicketsTab({super.key});

  @override
  ConsumerState<TicketsTab> createState() => _TicketsTabState();
}

class _TicketsTabState extends ConsumerState<TicketsTab> {
  String? _status;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('open', 'Open'),
    ('customer_reply', 'Customer reply'),
    ('answered', 'Answered'),
    ('closed', 'Closed'),
  ];

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider(_status));
    final theme = Theme.of(context);

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md, vertical: Spacing.sm),
            itemCount: _filters.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: Spacing.sm),
            itemBuilder: (context, index) {
              final (value, label) = _filters[index];
              return FilterChip(
                label: Text(label),
                selected: _status == value,
                showCheckmark: false,
                onSelected: (_) => setState(() => _status = value),
              );
            },
          ),
        ),
        Expanded(
          child: tickets.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => StateMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load tickets',
              message: error is ApiException ? error.message : null,
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(ticketsProvider(_status)),
            ),
            data: (items) => items.isEmpty
                ? const StateMessage(
                    icon: Icons.support_agent_outlined,
                    title: 'Queue is clear',
                  )
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(ticketsProvider(_status).future),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(Spacing.md),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: Spacing.sm),
                      itemBuilder: (context, index) {
                        final t = items[index];
                        return Card(
                          child: ListTile(
                            title: Text(t.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [
                                if (t.ticketNumber != null) t.ticketNumber!,
                                if (t.clientName != null) t.clientName!,
                                if (t.assigneeName != null)
                                  '→ ${t.assigneeName}',
                                if (t.lastReplyAt != null)
                                  Formatting.date(t.lastReplyAt),
                              ].join(' · '),
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: StatusChip(t.status, dense: true),
                            onTap: () =>
                                context.push(Routes.ticketPath(t.id)),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
