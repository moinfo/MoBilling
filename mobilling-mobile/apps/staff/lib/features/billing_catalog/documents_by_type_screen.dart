import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../documents/documents_tab.dart' show StaffInvoiceCard;
import 'billing_catalog_providers.dart';

/// One screen for quotations, proforma invoices and credit notes.
///
/// All three are `documents` rows, but credit notes come from their own
/// endpoint — [DocumentKind.creditNote] routes through `/credit-notes` while
/// the others use `/documents?type=…`.
enum DocumentKind {
  quotation('quotation', 'Quotations', 'No quotations yet'),
  proforma('proforma', 'Proforma invoices', 'No proforma invoices yet'),
  creditNote('credit_note', 'Credit notes', 'No credit notes yet');

  const DocumentKind(this.type, this.title, this.emptyTitle);

  final String type;
  final String title;
  final String emptyTitle;
}

class DocumentsByTypeScreen extends ConsumerStatefulWidget {
  const DocumentsByTypeScreen({super.key, required this.kind});

  final DocumentKind kind;

  @override
  ConsumerState<DocumentsByTypeScreen> createState() =>
      _DocumentsByTypeScreenState();
}

class _DocumentsByTypeScreenState
    extends ConsumerState<DocumentsByTypeScreen> {
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
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _listKey.currentState?.reload());
  }

  Future<Paginated<StaffInvoiceRow>> _fetch(int page) {
    final search = _search.text.trim().isEmpty ? null : _search.text.trim();

    if (widget.kind == DocumentKind.creditNote) {
      return ref.read(billingCatalogServiceProvider).creditNotes(
            status: _status,
            search: search,
            page: page,
          );
    }
    return ref.read(staffServiceProvider).documents(
          type: widget.kind.type,
          status: _status,
          search: search,
          page: page,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.kind.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search number or client',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
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
                  onSelected: (_) {
                    setState(() => _status = value);
                    _listKey.currentState?.reload();
                  },
                );
              },
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: _fetch,
              itemBuilder: (context, doc) => InkWell(
                borderRadius: Radii.card,
                onTap: () => context.push('/documents/${doc.id}'),
                child: StaffInvoiceCard(document: doc),
              ),
              emptyIcon: Icons.description_outlined,
              emptyTitle: widget.kind.emptyTitle,
            ),
          ),
        ],
      ),
    );
  }
}
