import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show FilterStrip;
import '../documents/documents_tab.dart' show StaffInvoiceCard;
import 'billing_catalog_providers.dart';
import 'document_form_screen.dart';

/// One screen for quotations, proforma invoices and credit notes.
///
/// All three are `documents` rows, but credit notes come from their own
/// endpoint — [DocumentKind.creditNote] routes through `/credit-notes` while
/// the others use `/documents?type=…`.
enum DocumentKind {
  quotation(
    'quotation',
    'Quotations',
    'No quotations yet',
    'Quotes raised for clients appear here.',
  ),
  proforma(
    'proforma',
    'Proforma invoices',
    'No proforma invoices yet',
    'Proformas raised for clients appear here.',
  ),
  creditNote(
    'credit_note',
    'Credit notes',
    'No credit notes yet',
    'Credits raised against invoices appear here.',
  );

  const DocumentKind(this.type, this.title, this.emptyTitle, this.emptyMessage);

  final String type;
  final String title;
  final String emptyTitle;
  final String emptyMessage;

  /// What the form should raise from this list's `+`.
  DocumentType get documentType => DocumentType.fromWire(type);

  /// Singular, for the masthead's tooltip.
  String get newLabel => 'New ${documentType.label.toLowerCase()}';
}

class DocumentsByTypeScreen extends ConsumerStatefulWidget {
  const DocumentsByTypeScreen({super.key, required this.kind});

  final DocumentKind kind;

  @override
  ConsumerState<DocumentsByTypeScreen> createState() =>
      _DocumentsByTypeScreenState();
}

class _DocumentsByTypeScreenState extends ConsumerState<DocumentsByTypeScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _status;

  /// Quotations and proformas move through accepted/rejected; credit notes
  /// only draft → issued, so the filter set differs by kind.
  List<(String?, String)> get _filters => switch (widget.kind) {
    DocumentKind.creditNote => const [
      (null, 'All'),
      ('draft', 'Draft'),
      ('sent', 'Issued'),
    ],
    _ => const [
      (null, 'All'),
      ('draft', 'Draft'),
      ('pending_approval', 'Awaiting approval'),
      ('sent', 'Sent'),
      ('accepted', 'Accepted'),
      ('rejected', 'Rejected'),
      ('cancelled', 'Cancelled'),
    ],
  };

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

  Future<Paginated<StaffInvoiceRow>> _fetch(int page) {
    final search = _search.text.trim().isEmpty ? null : _search.text.trim();

    if (widget.kind == DocumentKind.creditNote) {
      return ref
          .read(billingCatalogServiceProvider)
          .creditNotes(status: _status, search: search, page: page);
    }
    return ref
        .read(staffServiceProvider)
        .documents(
          type: widget.kind.type,
          status: _status,
          search: search,
          page: page,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Both `POST /documents` and `POST /credit-notes` are gated on
    // documents.create, so one check covers all three lists.
    final creatable =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(BillingCatalogPermissions.documentsCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: widget.kind.title,
        trailing: creatable
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: widget.kind.newLabel,
                onPressed: () => raiseDocument(
                  context,
                  type: widget.kind.documentType,
                  onSaved: () => _listKey.currentState?.reload(),
                ),
              )
            : null,
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search number or client',
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _listKey.currentState?.reload();
          },
        ),
      ),
      body: Column(
        children: [
          FilterStrip(
            options: _filters,
            selected: _status,
            onSelect: (value) {
              setState(() => _status = value);
              _listKey.currentState?.reload();
            },
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: _fetch,
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.xs,
                Spacing.md,
                Spacing.xl,
              ),
              itemBuilder: (context, doc) => StaffInvoiceCard(
                document: doc,
                onTap: () => context.push('/documents/${doc.id}'),
              ),
              emptyIcon: Icons.description_outlined,
              emptyTitle: widget.kind.emptyTitle,
              emptyMessage: widget.kind.emptyMessage,
            ),
          ),
        ],
      ),
    );
  }
}
