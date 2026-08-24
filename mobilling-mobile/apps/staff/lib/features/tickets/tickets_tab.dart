import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';

/// The staff ticket queue. A tab body inside the home shell — the shell owns
/// the masthead, so this starts with the status filter.
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

    return Column(
      children: [
        // One quiet row of choices under the masthead.
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm + 2,
            ),
            itemCount: _filters.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: Spacing.sm),
            itemBuilder: (context, index) {
              final (value, label) = _filters[index];
              return ChoiceChip(
                label: Text(label.toUpperCase()),
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
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(ticketsProvider(_status)),
            ),
            data: (items) => items.isEmpty
                ? StateMessage(
                    icon: Icons.support_agent_outlined,
                    title: 'Queue is clear',
                    message: _status == null
                        ? 'New tickets from clients land here.'
                        : 'Nothing with this status right now.',
                    actionLabel: _status == null ? null : 'Show all tickets',
                    onAction: _status == null
                        ? null
                        : () => setState(() => _status = null),
                  )
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(ticketsProvider(_status).future),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.md,
                        Spacing.sm,
                        Spacing.md,
                        Spacing.xl,
                      ),
                      children: [
                        Card(
                          child: Column(
                            children: [
                              for (final (i, t) in items.indexed) ...[
                                if (i > 0) const Divider(height: 1),
                                _TicketTile(ticket: t),
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
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket});

  final StaffTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = ticket;

    return ListTile(
      title: Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Spacing.xs),
          Row(
            children: [
              StatusChip(t.status, dense: true),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: _Meta([
                  if (t.ticketNumber != null) t.ticketNumber!,
                  if (t.lastReplyAt != null) Formatting.date(t.lastReplyAt),
                ].join(' · ')),
              ),
            ],
          ),
          if (t.clientName != null || t.assigneeName != null) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (t.clientName != null) t.clientName!,
                if (t.assigneeName != null) '→ ${t.assigneeName}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push(Routes.ticketPath(t.id)),
    );
  }
}

/// A mono metadata line — ticket number · last reply — in the eyebrow
/// register.
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
