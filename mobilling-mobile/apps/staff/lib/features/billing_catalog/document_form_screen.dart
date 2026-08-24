import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../common/pickers.dart';
import '../crm/crm_ui.dart'
    show CrmField, CrmMetaLine, CrmPickerField, CrmSheet, showCrmSheet;
import 'billing_catalog_providers.dart';

/// A figure as it should sit in a field being typed into, or in a caption
/// about a rate: `1`, not `1.00`, and blank rather than `0.00`.
/// [Formatting.amount] is for a figure being *read*, where the trailing zeros
/// are what keep a column of money aligned; here they are just noise.
String _plain(double? value) {
  if (value == null || value == 0) return '';
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

/// Raise (or amend) a document, then land on it.
///
/// Every entry point goes through here so the destination is the same one
/// everywhere: the document's own screen, where sending it, its PDF, WhatsApp
/// and the approval queue are all one tap away. Editing is the exception —
/// the caller is already looking at that document — so it only refreshes.
///
/// Pushed with [MaterialPageRoute] rather than a named route: `router.dart` is
/// not this change's to edit. Wiring a `GoRoute` later means replacing the
/// push below and nothing else, because the screen takes plain arguments.
Future<void> raiseDocument(
  BuildContext context, {
  DocumentType type = DocumentType.invoice,
  StaffDocument? document,
  StaffDocument? sourceInvoice,
  String? clientId,
  String? clientName,
  VoidCallback? onSaved,
}) async {
  final id = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => DocumentFormScreen(
        type: type,
        document: document,
        sourceInvoice: sourceInvoice,
        clientId: clientId,
        clientName: clientName,
      ),
    ),
  );
  if (id == null || !context.mounted) return;
  onSaved?.call();
  // An edit came from that document's own screen; pushing it again would
  // stack a second copy of the screen the user is already on.
  if (document != null) return;
  context.push('/documents/$id');
}

/// Raising a document from a phone.
///
/// The web builds this as a wide drawer with a per-row discount/tax matrix.
/// A phone has no room for a matrix and a field rep closing a sale has no
/// patience for one, so the same job is done as a short vertical form: who it
/// is for, what kind it is, then the lines — added one at a time through a
/// sheet, each becoming a row with its own money on the right edge.
///
/// The running total is pinned to the bottom rather than sitting at the end of
/// the list, because it is the figure the screen is about and it is the figure
/// that moves every time a line is added.
///
/// Pops with the new (or edited) document's id, so the caller can land on its
/// detail screen — where sending it, its PDF, WhatsApp and the approval queue
/// are all one tap away.
class DocumentFormScreen extends ConsumerStatefulWidget {
  const DocumentFormScreen({
    super.key,
    this.type = DocumentType.invoice,
    this.document,
    this.sourceInvoice,
    this.clientId,
    this.clientName,
  });

  /// What is being raised. Ignored when [document] is set — an existing
  /// document's kind is its own and the API offers no way to change it.
  final DocumentType type;

  /// Set to edit rather than raise. Every field, and every line, is seeded
  /// from it: `PUT /documents/{id}` replaces the item list wholesale, so a
  /// line this form does not send is a line that gets deleted.
  final StaffDocument? document;

  /// The invoice a credit note is being raised against. Forces the kind to
  /// [DocumentType.creditNote] and seeds the client and the lines from it, so
  /// "credit this invoice" is one tap plus a check of the figures.
  final StaffDocument? sourceInvoice;

  /// A client already known at the call site — from their own screen, say.
  final String? clientId;
  final String? clientName;

  bool get isEditing => document != null;

  @override
  ConsumerState<DocumentFormScreen> createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends ConsumerState<DocumentFormScreen> {
  final _notes = TextEditingController();
  final _items = <DocumentItemInput>[];

  late DocumentType _type;
  String? _clientId;
  String? _clientName;
  late DateTime _date;
  DateTime? _dueDate;
  bool _busy = false;
  String? _error;

  /// The server's own fallback payment window: `approve()` dates an undated
  /// document 14 days out. Starting there means an invoice raised in the field
  /// can go overdue and be chased, rather than sitting undated forever.
  static const _paymentWindow = Duration(days: 14);

  @override
  void initState() {
    super.initState();
    final doc = widget.document;
    final source = widget.sourceInvoice;

    if (doc != null) {
      _type = DocumentType.fromWire(doc.type);
      _clientId = doc.clientId;
      _clientName = doc.clientName;
      _items.addAll(doc.items.map(DocumentItemInput.fromDocumentItem));
      _date = doc.date ?? DateTime.now();
      _dueDate = doc.dueDate;
      _notes.text = doc.notes ?? '';
      return;
    }

    _date = DateTime.now();
    if (source != null) {
      _type = DocumentType.creditNote;
      _clientId = source.clientId;
      _clientName = source.clientName;
      _items.addAll(source.items.map(DocumentItemInput.fromDocumentItem));
      _notes.text = 'Credit against ${source.documentNumber}';
      return;
    }

    _type = widget.type;
    _clientId = widget.clientId;
    _clientName = widget.clientName;
    if (_type == DocumentType.invoice) _dueDate = _date.add(_paymentWindow);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  DocumentTotals get _totals => DocumentTotals.of(_items);

  /// A credit note is dated but never due, and its endpoint does not accept a
  /// due date at all.
  bool get _hasDueDate => _type != DocumentType.creditNote;

  String get _title {
    final doc = widget.document;
    if (doc != null) return 'Edit ${doc.documentNumber}';
    return 'New ${_type.label.toLowerCase()}';
  }

  Future<void> _pickClient() async {
    final picked = await ClientPickerSheet.show(context);
    if (picked == null) return;
    setState(() {
      _clientId = picked.id;
      _clientName = picked.name;
    });
  }

  Future<void> _pickDate({required bool due}) async {
    final now = DateTime.now();
    final initial = due ? (_dueDate ?? _date.add(_paymentWindow)) : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // Back-dating a document is routine bookkeeping; forward-dating it much
      // beyond a year is a typo.
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (due) {
        _dueDate = picked;
      } else {
        _date = picked;
      }
    });
  }

  Future<void> _addItem() async {
    final item = await showCrmSheet<DocumentItemInput>(
      context: context,
      builder: (_) => _ItemSheet(eyebrow: _type.label),
    );
    if (item == null) return;
    setState(() => _items.add(item));
  }

  Future<void> _editItem(int index) async {
    final edited = await showCrmSheet<DocumentItemInput>(
      context: context,
      builder: (_) => _ItemSheet(eyebrow: _type.label, item: _items[index]),
    );
    if (edited == null) return;
    setState(() => _items[index] = edited);
  }

  /// Nothing has reached the server yet, so a removed line is offered back
  /// rather than confirmed away first — the cheapest correct treatment of a
  /// mistake on a draft.
  void _removeItem(int index) {
    final removed = _items[index];
    setState(() => _items.removeAt(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${removed.description}.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => setState(
              () => _items.insert(index.clamp(0, _items.length), removed),
            ),
          ),
        ),
      );
  }

  String? get _blocker {
    if (_clientId == null) return 'Choose the client this is for.';
    if (_items.isEmpty) return 'Add at least one line.';
    return null;
  }

  Future<void> _submit() async {
    final blocker = _blocker;
    if (blocker != null) {
      setState(() => _error = blocker);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final service = ref.read(billingCatalogServiceProvider);
    final notes = _notes.text.trim();
    try {
      final StaffDocument saved;
      if (widget.isEditing) {
        saved = await service.updateDocument(
          widget.document!.id,
          clientId: _clientId!,
          type: _type.wire,
          date: _date,
          dueDate: _hasDueDate ? _dueDate : null,
          notes: notes,
          items: _items,
        );
      } else if (_type == DocumentType.creditNote) {
        saved = await service.createCreditNote(
          clientId: _clientId!,
          sourceInvoiceId: widget.sourceInvoice?.id,
          date: _date,
          notes: notes,
          items: _items,
        );
      } else {
        saved = await service.createDocument(
          clientId: _clientId!,
          type: _type.wire,
          date: _date,
          dueDate: _dueDate,
          notes: notes,
          items: _items,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? '${saved.documentNumber} updated.'
                : '${saved.documentNumber} raised as a draft.',
          ),
        ),
      );
      Navigator.of(context).pop(saved.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = _totals;

    return Scaffold(
      appBar: ShellTopBar(eyebrow: 'Billing', title: _title),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],

          CrmPickerField(
            label: 'Client',
            value: _clientName ?? 'Choose a client',
            placeholder: _clientName == null,
            icon: Icons.person_outline,
            onTap: _busy ? null : _pickClient,
          ),

          // The kind is fixed once a document exists: the API has no way to
          // turn an invoice into a quotation, and `convert` runs the other
          // way round on the document itself.
          if (!widget.isEditing && _type != DocumentType.creditNote) ...[
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Kind',
              child: SegmentedButton<DocumentType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: DocumentType.invoice,
                    label: Text('Invoice'),
                  ),
                  ButtonSegment(
                    value: DocumentType.quotation,
                    label: Text('Quote'),
                  ),
                  ButtonSegment(
                    value: DocumentType.proforma,
                    label: Text('Proforma'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: _busy
                    ? null
                    : (choice) => setState(() {
                        _type = choice.first;
                        // Only an invoice is chased for payment, so only an
                        // invoice arrives with a payment window on it.
                        _dueDate = _type == DocumentType.invoice
                            ? (_dueDate ?? _date.add(_paymentWindow))
                            : null;
                      }),
              ),
            ),
          ],

          if (widget.sourceInvoice != null) ...[
            const SizedBox(height: Spacing.md),
            _SourceInvoiceNote(invoice: widget.sourceInvoice!),
          ],

          const SizedBox(height: Spacing.lg),
          const SectionHeader('Lines'),
          const SizedBox(height: Spacing.sm),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, item) in _items.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  Dismissible(
                    key: ObjectKey(item),
                    direction: DismissDirection.endToStart,
                    background: _DismissBackground(color: scheme.error),
                    onDismissed: (_) => _removeItem(i),
                    child: _ItemRow(
                      item: item,
                      onTap: _busy ? null : () => _editItem(i),
                      onLongPress: _busy ? null : () => _removeItem(i),
                    ),
                  ),
                ],
                if (_items.isNotEmpty) const Divider(height: 1),
                ListTile(
                  onTap: _busy ? null : _addItem,
                  leading: Icon(Icons.add_rounded, color: scheme.primary),
                  title: Text(
                    _items.isEmpty ? 'Add the first line' : 'Add a line',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                  subtitle: _items.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: CrmMetaLine('FROM THE CATALOGUE, OR TYPED'),
                        )
                      : null,
                ),
              ],
            ),
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Tap a line to change it, swipe it away to remove it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],

          const SizedBox(height: Spacing.lg),
          CrmPickerField(
            label: _type == DocumentType.creditNote ? 'Credit date' : 'Date',
            value: Formatting.date(_date),
            onTap: _busy ? null : () => _pickDate(due: false),
          ),
          if (_hasDueDate) ...[
            const SizedBox(height: Spacing.md),
            CrmPickerField(
              label: 'Due date',
              value: _dueDate == null
                  ? 'No due date'
                  : Formatting.date(_dueDate),
              placeholder: _dueDate == null,
              onTap: _busy ? null : () => _pickDate(due: true),
            ),
          ],

          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Notes',
            child: TextField(
              controller: _notes,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'Anything the client should read on the document',
                counterText: '',
              ),
            ),
          ),
        ],
      ),
      // Pinned rather than at the end of the list: the total is what the
      // screen is about, and it moves every time a line is added.
      bottomNavigationBar: _TotalBar(
        totals: totals,
        label: widget.isEditing
            ? 'Save changes'
            : 'Raise ${_type.article} ${_type.label.toLowerCase()}',
        // Named rather than merely disabling the button: a greyed button with
        // no reason beside it is a dead end.
        blocker: _blocker,
        busy: _busy,
        onSubmit: _busy || _blocker != null ? null : _submit,
      ),
    );
  }
}

/// The running total and the one button that commits it.
///
/// Subtotal, discount and tax are only named when they are not zero: on the
/// common line — a quantity at a price, no discount, no VAT — three rows of
/// duplicate figures would bury the one that matters.
class _TotalBar extends StatelessWidget {
  const _TotalBar({
    required this.totals,
    required this.label,
    required this.blocker,
    required this.busy,
    required this.onSubmit,
  });

  final DocumentTotals totals;
  final String label;

  /// What is still missing, when something is — shown beside the button it
  /// is holding shut.
  final String? blocker;
  final bool busy;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final breakdown = [
      if (totals.discount > 0) 'LESS ${Formatting.amount(totals.discount)}',
      if (totals.tax > 0) 'TAX ${Formatting.amount(totals.tax)}',
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (breakdown.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          CrmMetaLine(breakdown),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Money(totals.total, scale: MoneyScale.headline),
                    ),
                  ),
                ],
              ),
              if (blocker != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  blocker!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.md),
              PrimaryButton(label: label, busy: busy, onPressed: onSubmit),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the draft: what it is on the left, what it comes to on the
/// right, so a screenful of lines reads as one column of money.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, this.onTap, this.onLongPress});

  final DocumentItemInput item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      '${Formatting.amount(item.quantity)}'
          '${item.unit == null || item.unit!.isEmpty ? '' : ' ${item.unit}'}'
          ' × ${Formatting.amount(item.price)}',
      // A discount set on the web is not editable here, but it is spending
      // the client's money — it does not get to be invisible.
      if (item.discountAmount > 0)
        'less ${Formatting.amount(item.discountAmount)}',
      if ((item.taxPercent ?? 0) > 0) '${_plain(item.taxPercent)}% tax',
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      title: Text(
        item.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: CrmMetaLine(meta),
      ),
      trailing: Money(item.lineTotal, showCode: false),
    );
  }
}

/// What sits behind a line as it is swiped away.
class _DismissBackground extends StatelessWidget {
  const _DismissBackground({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    color: color.withValues(alpha: 0.12),
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: Spacing.lg),
    child: Icon(Icons.delete_outline, color: color),
  );
}

/// Says what a credit note seeded from an invoice is actually going to do —
/// the wallet is not credited by raising it, only by issuing it afterwards.
class _SourceInvoiceNote extends StatelessWidget {
  const _SourceInvoiceNote({required this.invoice});

  final StaffDocument invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CrmMetaLine('CREDITING ${invoice.documentNumber}'),
            const SizedBox(height: Spacing.xs),
            Text(
              'Its lines are copied below — trim them to credit part of it. '
              'The client is credited when the note is issued, not now.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line, added or amended.
///
/// A line can be seeded from the catalogue — which fills the price, the tax
/// and the unit as the catalogue has them — or simply typed, which is what a
/// rep quoting something bespoke actually needs. Either way the four figures
/// that matter are on one screen with the line's own total under them, so the
/// arithmetic is checked before the line joins the document.
class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.eyebrow, this.item});

  final String eyebrow;

  /// The line being amended; null when adding.
  final DocumentItemInput? item;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final DocumentItemInput _draft =
      widget.item?.copy() ??
      DocumentItemInput(description: '', quantity: 1, price: 0);

  late final _description = TextEditingController(text: _draft.description);
  late final _quantity = TextEditingController(text: _plain(_draft.quantity));
  late final _price = TextEditingController(text: _plain(_draft.price));
  late final _tax = TextEditingController(text: _plain(_draft.taxPercent));

  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _price.dispose();
    _tax.dispose();
    super.dispose();
  }

  /// Amounts are typed with the grouping separators the rest of the app
  /// prints, so they are stripped before parsing rather than rejected.
  double? _number(TextEditingController controller) {
    final text = controller.text.replaceAll(',', '').trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  /// Keeps the draft in step with the fields so the line total below them is
  /// always the total of what is on screen.
  void _sync() {
    setState(() {
      _draft.description = _description.text.trim();
      _draft.quantity = _number(_quantity) ?? 0;
      _draft.price = _number(_price) ?? 0;
      _draft.taxPercent = _number(_tax);
    });
  }

  Future<void> _fromCatalogue() async {
    final product = await ProductPickerSheet.show(context);
    if (product == null || !mounted) return;
    final seeded = DocumentItemInput.fromProduct(product);
    setState(() {
      // The line keeps whatever discount and service period it already had —
      // the catalogue has nothing to say about either.
      _draft
        ..description = seeded.description
        ..quantity = _draft.quantity > 0 ? _draft.quantity : 1
        ..price = seeded.price
        ..itemType = seeded.itemType
        ..productServiceId = seeded.productServiceId
        ..taxPercent = seeded.taxPercent
        ..unit = seeded.unit;
      _description.text = _draft.description;
      _quantity.text = _plain(_draft.quantity);
      _price.text = _plain(_draft.price);
      _tax.text = _plain(_draft.taxPercent);
    });
  }

  void _save() {
    _sync();
    if (_draft.description.isEmpty) {
      setState(() => _error = 'Say what this line is for.');
      return;
    }
    // The API's own floor: a zero-quantity line is not a line.
    if (_draft.quantity < 0.01) {
      setState(() => _error = 'The quantity must be at least 0.01.');
      return;
    }
    if (_draft.price < 0) {
      setState(() => _error = 'A price cannot be negative.');
      return;
    }
    if ((_draft.taxPercent ?? 0) < 0 || (_draft.taxPercent ?? 0) > 100) {
      setState(() => _error = 'Tax must be between 0 and 100 percent.');
      return;
    }
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CrmSheet(
      eyebrow: widget.eyebrow,
      title: widget.item == null ? 'Add a line' : 'Change this line',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        OutlinedButton.icon(
          onPressed: _fromCatalogue,
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: Text(
            _draft.productServiceId == null
                ? 'Pick from the catalogue'
                : 'Pick a different product',
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Description',
          child: TextField(
            controller: _description,
            maxLines: 2,
            minLines: 1,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _sync(),
            decoration: const InputDecoration(
              hintText: 'What is being charged for',
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CrmField(
                label: 'Quantity',
                child: TextField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _sync(),
                  decoration: InputDecoration(
                    hintText: '1',
                    suffixText: _draft.unit,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: CrmField(
                label: 'Unit price',
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _sync(),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixText: '${Formatting.tenantCurrency} ',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Tax',
          child: TextField(
            controller: _tax,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _sync(),
            decoration: const InputDecoration(
              hintText: 'None',
              suffixText: '%',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        // The line's own figure, so the arithmetic is checked here rather than
        // discovered in the total afterwards.
        Row(
          children: [
            Expanded(
              child: Text(
                'LINE TOTAL',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Money(_draft.lineTotal, scale: MoneyScale.headline),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: widget.item == null ? 'Add line' : 'Save line',
          onPressed: _save,
        ),
      ],
    );
  }
}
