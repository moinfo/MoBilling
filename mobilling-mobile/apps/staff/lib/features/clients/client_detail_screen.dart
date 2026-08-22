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
class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({
    super.key,
    required this.clientId,
    this.clientName,
  });

  final String clientId;
  final String? clientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(clientName ?? 'Client')),
      body: PagedListView(
        fetch: (page) => ref
            .read(staffServiceProvider)
            .documents(clientId: clientId, page: page),
        itemBuilder: (context, doc) => InkWell(
          borderRadius: Radii.card,
          onTap: () => context.push('/documents/${doc.id}'),
          child: StaffInvoiceCard(document: doc),
        ),
        emptyIcon: Icons.receipt_long_outlined,
        emptyTitle: 'No invoices for this client',
      ),
    );
  }
}

/// Call / email action row used where a client's contacts are shown.
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
        if (phone != null && email != null)
          const SizedBox(width: Spacing.sm),
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
