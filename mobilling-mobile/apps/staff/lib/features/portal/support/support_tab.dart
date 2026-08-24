import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';

/// Support hub: tickets, announcements and the knowledgebase in one tab,
/// switched by a segmented control — three thin lists don't each deserve a
/// bottom-nav slot. A tab body inside the portal shell, so the masthead is
/// the shell's and the only chrome here is the quiet filter row.
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
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            Spacing.xs,
          ),
          child: SegmentedButton<_Section>(
            segments: const [
              ButtonSegment(value: _Section.tickets, label: Text('Tickets')),
              ButtonSegment(value: _Section.news, label: Text('News')),
              ButtonSegment(value: _Section.help, label: Text('Help')),
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

/// The mono metadata line under a list title: `reference · department · date`,
/// upper-cased because it names rather than says.
class _MetaLine extends StatelessWidget {
  const _MetaLine(this.parts);

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      parts.join(' · ').toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
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
    final theme = Theme.of(context);

    return Scaffold(
      // No app bar: this is a body inside the portal shell. The scaffold is
      // here only to hang the new-ticket action off.
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
            ? StateMessage(
                icon: Icons.support_agent_outlined,
                title: 'No tickets yet',
                message:
                    'Need a hand? Open a ticket and support will reply here.',
                actionLabel: 'Open a ticket',
                onAction: () => context.push(PortalRoutes.newTicket),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(portalTicketsProvider.future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xxl + Spacing.lg,
                  ),
                  children: [
                    const SectionHeader('Your tickets'),
                    const SizedBox(height: Spacing.sm),
                    Card(
                      child: Column(
                        children: [
                          for (final (i, ticket) in items.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              title: Text(
                                ticket.subject,
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: Spacing.xs),
                                child: Row(
                                  children: [
                                    StatusChip(ticket.status, dense: true),
                                    const SizedBox(width: Spacing.sm),
                                    Flexible(
                                      child: _MetaLine([
                                        if (ticket.ticketNumber != null)
                                          ticket.ticketNumber!,
                                        ticket.department,
                                        if (ticket.repliesCount != null)
                                          '${ticket.repliesCount} '
                                              'repl${ticket.repliesCount == 1 ? 'y' : 'ies'}',
                                      ]),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: ticket.lastReplyAt == null
                                  ? Icon(
                                      Icons.chevron_right,
                                      color: theme.colorScheme.outline,
                                    )
                                  : Text(
                                      Formatting.date(
                                        ticket.lastReplyAt,
                                      ).toUpperCase(),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface,
                                          ),
                                    ),
                              onTap: () => context.push(
                                PortalRoutes.ticketPath(ticket.id),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
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

// ---------------------------------------------------------------------------
// Announcements
// ---------------------------------------------------------------------------

class _AnnouncementsList extends ConsumerWidget {
  const _AnnouncementsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcements = ref.watch(portalAnnouncementsProvider);
    final theme = Theme.of(context);

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
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  const SectionHeader('Latest news'),
                  const SizedBox(height: Spacing.sm),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, a) in items.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ExpansionTile(
                            shape: const Border(),
                            collapsedShape: const Border(),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: Spacing.md,
                            ),
                            title: Text(
                              a.title,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: Spacing.xs),
                              child: _MetaLine([
                                Formatting.date(a.publishedAt),
                              ]),
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              Spacing.md,
                              0,
                              Spacing.md,
                              Spacing.md,
                            ),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                htmlToPlainText(a.body),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                ],
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
  ConsumerState<_KnowledgebaseList> createState() => _KnowledgebaseListState();
}

class _KnowledgebaseListState extends ConsumerState<_KnowledgebaseList> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kb = ref.watch(
      portalKnowledgebaseProvider(_search.isEmpty ? null : _search),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.xs,
            Spacing.md,
            Spacing.xs,
          ),
          child: TextField(
            onSubmitted: (v) => setState(() => _search = v.trim()),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search help articles',
              prefixIcon: Icon(Icons.search, size: 20),
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
                portalKnowledgebaseProvider(_search.isEmpty ? null : _search),
              ),
            ),
            data: (categories) => categories.isEmpty
                ? StateMessage(
                    icon: Icons.menu_book_outlined,
                    title: _search.isEmpty
                        ? 'No articles yet'
                        : 'Nothing matched “$_search”',
                    message: _search.isEmpty
                        ? 'Guides from your service provider will appear here.'
                        : 'Try a shorter phrase, or open a ticket and ask us.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(Spacing.md),
                    children: [
                      for (final (c, category) in categories.indexed) ...[
                        if (c > 0) const SizedBox(height: Spacing.lg),
                        SectionHeader(category.name),
                        const SizedBox(height: Spacing.sm),
                        Card(
                          child: Column(
                            children: [
                              for (final (i, article)
                                  in category.articles.indexed) ...[
                                if (i > 0) const Divider(height: 1),
                                ListTile(
                                  title: Text(
                                    article.title,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  subtitle: article.excerpt == null
                                      ? null
                                      : Padding(
                                          padding: const EdgeInsets.only(
                                            top: Spacing.xs,
                                          ),
                                          child: Text(
                                            article.excerpt!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                  trailing: Icon(
                                    Icons.chevron_right,
                                    color: theme.colorScheme.outline,
                                  ),
                                  onTap: () => context.push(
                                    PortalRoutes.kbPath(article.slug),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: Spacing.xl),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
