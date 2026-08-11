import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';

/// Support hub: tickets, announcements and the knowledgebase in one tab,
/// switched by a segmented control — three thin lists don't each deserve a
/// bottom-nav slot.
class SupportTab extends ConsumerStatefulWidget {
  const SupportTab({super.key});

  @override
  ConsumerState<SupportTab> createState() => _SupportTabState();
}

enum _Section { tickets, news, help }

class _SupportTabState extends ConsumerState<SupportTab> {
  _Section _section = _Section.tickets;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
          child: SegmentedButton<_Section>(
            segments: const [
              ButtonSegment(
                  value: _Section.tickets,
                  label: Text('Tickets'),
                  icon: Icon(Icons.support_agent_outlined, size: 18)),
              ButtonSegment(
                  value: _Section.news,
                  label: Text('News'),
                  icon: Icon(Icons.campaign_outlined, size: 18)),
              ButtonSegment(
                  value: _Section.help,
                  label: Text('Help'),
                  icon: Icon(Icons.menu_book_outlined, size: 18)),
            ],
            selected: {_section},
            onSelectionChanged: (s) => setState(() => _section = s.first),
            showSelectedIcon: false,
          ),
        ),
        Expanded(
          child: switch (_section) {
            _Section.tickets => const _TicketsList(),
            _Section.news => const _AnnouncementsList(),
            _Section.help => const _KnowledgebaseList(),
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tickets
// ---------------------------------------------------------------------------

class _TicketsList extends ConsumerWidget {
  const _TicketsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(portalTicketsProvider);

    return Scaffold(
      body: tickets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load tickets',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(portalTicketsProvider),
        ),
        data: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.support_agent_outlined,
                title: 'No tickets yet',
                message:
                    'Need a hand? Open a ticket and support will reply here.',
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(portalTicketsProvider.future),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(Spacing.md),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) =>
                      _TicketRow(ticket: items[index]),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-ticket',
        onPressed: () => context.push(PortalRoutes.newTicket),
        icon: const Icon(Icons.add),
        label: const Text('New ticket'),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket});

  final PortalTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: Radii.card,
        onTap: () => context.push(PortalRoutes.ticketPath(ticket.id)),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.subject,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  StatusChip(ticket.status, dense: true),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                [
                  if (ticket.ticketNumber != null) ticket.ticketNumber!,
                  ticket.department,
                  if (ticket.lastReplyAt != null)
                    Formatting.date(ticket.lastReplyAt),
                  if (ticket.repliesCount != null)
                    '${ticket.repliesCount} repl${ticket.repliesCount == 1 ? 'y' : 'ies'}',
                ].join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Announcements
// ---------------------------------------------------------------------------

class _AnnouncementsList extends ConsumerWidget {
  const _AnnouncementsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcements = ref.watch(portalAnnouncementsProvider);

    return announcements.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load announcements',
        message: error is ApiException ? error.message : null,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(portalAnnouncementsProvider),
      ),
      data: (items) => items.isEmpty
          ? const StateMessage(
              icon: Icons.campaign_outlined,
              title: 'No announcements',
              message: 'News from your service provider will appear here.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(portalAnnouncementsProvider.future),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final a = items[index];
                  return Card(
                    child: ExpansionTile(
                      shape: const Border(),
                      title: Text(a.title),
                      subtitle: Text(Formatting.date(a.publishedAt)),
                      childrenPadding: const EdgeInsets.fromLTRB(
                          Spacing.md, 0, Spacing.md, Spacing.md),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(htmlToPlainText(a.body)),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Knowledgebase
// ---------------------------------------------------------------------------

class _KnowledgebaseList extends ConsumerStatefulWidget {
  const _KnowledgebaseList();

  @override
  ConsumerState<_KnowledgebaseList> createState() =>
      _KnowledgebaseListState();
}

class _KnowledgebaseListState extends ConsumerState<_KnowledgebaseList> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final kb = ref.watch(portalKnowledgebaseProvider(_search.isEmpty ? null : _search));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.xs, Spacing.md, Spacing.xs),
          child: TextField(
            onSubmitted: (v) => setState(() => _search = v.trim()),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search help articles',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: kb.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => StateMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load help articles',
              message: error is ApiException ? error.message : null,
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(
                  portalKnowledgebaseProvider(_search.isEmpty ? null : _search)),
            ),
            data: (categories) => categories.isEmpty
                ? StateMessage(
                    icon: Icons.menu_book_outlined,
                    title: _search.isEmpty
                        ? 'No articles yet'
                        : 'Nothing matched "$_search"',
                  )
                : ListView(
                    padding: const EdgeInsets.all(Spacing.md),
                    children: [
                      for (final category in categories) ...[
                        Text(category.name,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: Spacing.sm),
                        Card(
                          child: Column(
                            children: [
                              for (final (i, article)
                                  in category.articles.indexed) ...[
                                if (i > 0) const Divider(height: 1),
                                ListTile(
                                  dense: true,
                                  title: Text(article.title),
                                  subtitle: article.excerpt == null
                                      ? null
                                      : Text(article.excerpt!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => context
                                      .push(PortalRoutes.kbPath(article.slug)),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: Spacing.md),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
