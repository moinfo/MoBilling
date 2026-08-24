import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../documents/documents_tab.dart' show StaffInvoiceCard;

/// A client's invoices, with one-tap call/email.
///
/// Kept intentionally lean: the staff app is a companion for the person in
/// the field or on the phone — full client editing stays on the web.
class ClientDetailScreen extends ConsumerStatefulWidget {
  const ClientDetailScreen({
    super.key,
    required this.clientId,
    this.clientName,
  });

  final String clientId;

  /// Passed when arriving from the clients list. Absent on a deep link — a
  /// push notification, a shared URL — which is why [_resolved] exists.
  final String? clientName;

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen> {
  /// The name read off the first invoice, for the deep-link case. Without it
  /// the masthead says "Client" and nothing on the screen says whose
  /// invoices these are — the rows no longer repeat the name.
  String? _resolved;

  String get _clientId => widget.clientId;

  @override
  Widget build(BuildContext context) {
    final title = widget.clientName ?? _resolved ?? 'Client';

    return Scaffold(
      appBar: ShellTopBar(eyebrow: 'Billing', title: title),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
            child: SectionHeader('Invoices'),
          ),
          Expanded(
            child: PagedListView(
              fetch: (page) async {
                final result = await ref
                    .read(staffServiceProvider)
                    .documents(clientId: _clientId, page: page);
                // Name the client from the data we already have, once.
                final name = result.items.isEmpty
                    ? null
                    : result.items.first.clientName;
                if (mounted &&
                    widget.clientName == null &&
                    _resolved == null &&
                    name != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _resolved = name);
                  });
                }
                return result;
              },
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.md,
                Spacing.xl,
              ),
              itemBuilder: (context, doc) => InkWell(
                borderRadius: Radii.card,
                onTap: () => context.push('/documents/${doc.id}'),
                // The masthead already names the client; repeating it on
                // every row would leave the invoice itself unidentified.
                child: StaffInvoiceCard(document: doc, showClient: false),
              ),
              emptyIcon: Icons.receipt_long_outlined,
              emptyTitle: 'No invoices for this client',
              emptyMessage: 'Invoices raised for them will appear here.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Call / email action row used where a client's contacts are shown.
///
/// Secondary actions in the theme's outlined button, the icon quiet — the
/// word is the action; the icon only disambiguates the two.
class ContactActions extends StatelessWidget {
  const ContactActions({super.key, this.phone, this.email});

  final String? phone;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (phone != null)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.call_outlined, size: 18),
              label: const Text('Call'),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
            ),
          ),
        if (phone != null && email != null) const SizedBox(width: Spacing.sm),
        if (email != null)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.mail_outline, size: 18),
              label: const Text('Email'),
              onPressed: () => launchUrl(Uri(scheme: 'mailto', path: email)),
            ),
          ),
      ],
    );
  }
}
