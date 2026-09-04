import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../common/pickers.dart';
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmDetailRow,
        CrmField,
        CrmPickerField,
        CrmSheet,
        CrmStatusLine,
        showCrmSheet;
import 'support_admin_providers.dart';

/// One client's services. Keyed by client id.
final AutoDisposeFutureProviderFamily<List<ClientServiceRow>, String>
clientServicesProvider = FutureProvider.autoDispose
    .family<List<ClientServiceRow>, String>(
      (ref, clientId) =>
          ref.watch(supportAdminServiceProvider).clientServices(clientId),
    );

/// One service's full record. Keyed by client_subscription id.
final AutoDisposeFutureProviderFamily<HostingServiceDetail, String>
hostingServiceProvider = FutureProvider.autoDispose
    .family<HostingServiceDetail, String>(
      (ref, subscriptionId) =>
          ref.watch(supportAdminServiceProvider).hostingService(subscriptionId),
    );

/// The plan-change offer. 422s when the service has no product or is still
/// billed in WHMCS, so the sheet renders the error message as the answer.
final AutoDisposeFutureProviderFamily<ServiceUpgradeOptions, String>
serviceUpgradeOptionsProvider = FutureProvider.autoDispose
    .family<ServiceUpgradeOptions, String>(
      (ref, subscriptionId) => ref
          .watch(supportAdminServiceProvider)
          .serviceUpgradeOptions(subscriptionId),
    );

/// The WHM package list for [serverId], or null when a picker cannot be
/// offered: no server assigned, no `hosting.settings`, or the server itself
/// refused. Callers fall back to typing the name, which is what the web does
/// when its own package query errors.
Future<List<String>?> _fetchServerPackages(WidgetRef ref, String? serverId) async {
  if (serverId == null || serverId.isEmpty) return null;
  final allowed =
      ref
          .read(sessionControllerProvider)
          .session
          ?.can(SupportAdminPermissions.hostingSettings) ??
      false;
  if (!allowed) return null;
  try {
    final packages = await ref
        .read(supportAdminServiceProvider)
        .serverPackages(serverId);
    return packages.isEmpty ? null : packages;
  } on ApiException {
    return null;
  }
}

/// Picks one WHM package name. [current] is kept in the list even when the
/// server no longer offers it, so an account on a retired package can still
/// see what it is on.
Future<String?> _pickPackage(
  BuildContext context, {
  required List<String> packages,
  required String? current,
  required String eyebrow,
}) {
  final options = <String>{
    if (current != null && current.isNotEmpty) current,
    ...packages,
  }.toList();

  return showCrmSheet<String>(
    context: context,
    builder: (sheetContext) => CrmSheet(
      eyebrow: eyebrow,
      title: 'WHM package',
      children: [
        for (final package in options)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(package),
            trailing: package == current ? const Icon(Icons.check) : null,
            onTap: () => Navigator.of(sheetContext).pop(package),
          ),
      ],
    ),
  );
}

/// The admin Products/Services tab — the web's `ServiceManagement.tsx`.
///
/// The web puts three stacked selects on one page: pick a client, pick one of
/// their services, then edit it in a two-column WHMCS grid. On a phone that
/// collapses into the shape this app uses everywhere else: a client picker,
/// that client's services as rows, and a pushed detail per service. The edit
/// form and the module commands live on the detail, where there is room for
/// them.
///
/// Everything here keys off the **client_subscription**. The subscription is
/// the billing record and exists whether or not anything was provisioned, so
/// a service with no hosting account is still editable — only the module
/// commands, which act on the cPanel account, go away.
class ManageServicesScreen extends ConsumerStatefulWidget {
  const ManageServicesScreen({super.key});

  @override
  ConsumerState<ManageServicesScreen> createState() =>
      _ManageServicesScreenState();
}

class _ManageServicesScreenState extends ConsumerState<ManageServicesScreen> {
  StaffClient? _client;

  Future<void> _pickClient() async {
    final picked = await ClientPickerSheet.show(context);
    if (picked != null && mounted) setState(() => _client = picked);
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final canRead =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(SupportAdminPermissions.clientSubscriptionsRead) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Web Services',
        title: 'Manage services',
        trailing: canRead
            ? InkActionButton(
                icon: Icons.person_search_outlined,
                tooltip: client == null ? 'Choose client' : 'Change client',
                onPressed: _pickClient,
              )
            : null,
      ),
      body: !canRead
          ? const StateMessage(
              icon: Icons.lock_outline,
              title: 'Not available',
              message:
                  'Managing services needs the client subscriptions read '
                  'permission.',
            )
          : client == null
          ? StateMessage(
              icon: Icons.tune_outlined,
              title: 'Choose a client',
              message:
                  'Their hosting and every other subscription appear here, '
                  'ready to edit.',
              actionLabel: 'Choose client',
              onAction: _pickClient,
            )
          : _ServicesList(client: client),
    );
  }
}

/// One client's services as hairline-divided rows. The domain titles the row
/// because that is what staff are told on the phone; the product and whether
/// anything exists on a server sit in the mono line under it.
class _ServicesList extends ConsumerWidget {
  const _ServicesList({required this.client});

  final StaffClient client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(clientServicesProvider(client.id));

    return CrmAsyncView(
      value: services,
      errorTitle: 'Could not load services',
      onRetry: () => ref.invalidate(clientServicesProvider(client.id)),
      builder: (rows) => RefreshIndicator(
        onRefresh: () => ref.refresh(clientServicesProvider(client.id).future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.xl,
          ),
          children: [
            SectionHeader(client.name),
            const SizedBox(height: Spacing.sm),
            if (rows.isEmpty)
              const SizedBox(
                height: 260,
                child: StateMessage(
                  icon: Icons.inventory_2_outlined,
                  title: 'No services',
                  message: 'This client has nothing subscribed yet.',
                ),
              )
            else
              CrmCardList(
                children: [for (final row in rows) _ServiceRow(row: row)],
              ),
          ],
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.row});

  final ClientServiceRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: () => context.push('/hosting/services/${row.id}'),
      title: Text(
        row.domain ?? row.productName,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: CrmStatusLine(
          status: row.status,
          meta: [
            row.productName,
            if (!row.hasAccount) 'no server account',
          ].join(' · '),
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail
// ---------------------------------------------------------------------------

/// One service: the WHMCS edit form as a phone form, with the module commands
/// behind the masthead's action button.
class ManageServiceDetailScreen extends ConsumerWidget {
  const ManageServiceDetailScreen({super.key, required this.subscriptionId});

  final String subscriptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(hostingServiceProvider(subscriptionId));
    final loaded = detail.valueOrNull;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: loaded?.clientName ?? 'Manage services',
        title: loaded?.title ?? 'Service',
        trailing: loaded == null
            ? null
            : InkActionButton(
                icon: Icons.bolt_outlined,
                tooltip: 'Actions',
                onPressed: () => _openCommands(context, loaded),
              ),
      ),
      body: CrmAsyncView(
        value: detail,
        errorTitle: 'Could not load the service',
        onRetry: () => ref.invalidate(hostingServiceProvider(subscriptionId)),
        builder: (data) => _ServiceForm(detail: data),
      ),
    );
  }

  /// The commands sheet answers with the follow-on that needs a screen of its
  /// own, and this opens it — the sheet is gone by then, so its own context
  /// would be defunct.
  Future<void> _openCommands(
    BuildContext context,
    HostingServiceDetail detail,
  ) async {
    final action = await showCrmSheet<String>(
      context: context,
      builder: (_) => _CommandsSheet(detail: detail),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'upgrade':
        await showCrmSheet<void>(
          context: context,
          builder: (_) => _UpgradeSheet(detail: detail),
        );
      case 'message':
        await showCrmSheet<void>(
          context: context,
          builder: (_) => _SendMessageSheet(detail: detail),
        );
      case 'client':
        context.push('/clients/${detail.clientId}');
      // No order document means no single invoice to open; the client's own
      // list is where the rest of them are.
      case 'invoice':
        context.push(
          detail.orderDocumentId == null
              ? '/clients/${detail.clientId}'
              : '/documents/${detail.orderDocumentId}',
        );
      // The record this screen is showing is gone.
      case 'deleted':
        context.pop();
    }
  }
}

/// The edit form. Seeded from the loaded record and re-seeded whenever a fresh
/// one arrives, so a save or a module command leaves the fields showing what
/// the server actually stored rather than what was typed.
class _ServiceForm extends ConsumerStatefulWidget {
  const _ServiceForm({required this.detail});

  final HostingServiceDetail detail;

  @override
  ConsumerState<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends ConsumerState<_ServiceForm> {
  final _domain = TextEditingController();
  final _dedicatedIp = TextEditingController();
  final _username = TextEditingController();
  final _package = TextEditingController();
  final _quantity = TextEditingController();
  final _firstPayment = TextEditingController();
  final _recurring = TextEditingController();
  final _promoCode = TextEditingController();

  String? _productServiceId;
  String? _status;
  String? _serverId;
  String? _paymentMethod;
  DateTime? _startDate;
  DateTime? _nextDueDate;
  DateTime? _terminationDate;

  /// "Recalc" on the web: the server re-derives the recurring amount from the
  /// product's current price and ignores whatever is in the field, so the
  /// field is disabled while this is on.
  bool _recalculate = false;

  bool _saving = false;
  bool _loadingPackages = false;
  String? _error;

  HostingServiceDetail get detail => widget.detail;

  /// Whether anything differs from the loaded record. The discard control only
  /// earns its place once there is something to discard.
  bool get _dirty {
    final d = detail;
    return _recalculate ||
        _productServiceId != d.productServiceId ||
        _status != d.status ||
        _serverId != d.serverId ||
        _paymentMethod != d.paymentMethod ||
        _startDate != d.startDate ||
        _nextDueDate != d.nextDueDate ||
        _terminationDate != d.terminationDate ||
        _trimmed(_domain) != d.domain ||
        _trimmed(_dedicatedIp) != d.dedicatedIp ||
        _trimmed(_username) != d.username ||
        _trimmed(_package) != d.package ||
        _trimmed(_promoCode) != d.promoCode ||
        int.tryParse(_quantity.text.trim()) != d.quantity ||
        _amount(_firstPayment) != d.firstPaymentAmount ||
        _amount(_recurring) != d.recurringAmount;
  }

  @override
  void initState() {
    super.initState();
    _seed(widget.detail);
  }

  @override
  void didUpdateWidget(_ServiceForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new instance means a fresh fetch — after a save, or after a module
    // command changed the record underneath us.
    if (!identical(oldWidget.detail, widget.detail)) _seed(widget.detail);
  }

  @override
  void dispose() {
    _domain.dispose();
    _dedicatedIp.dispose();
    _username.dispose();
    _package.dispose();
    _quantity.dispose();
    _firstPayment.dispose();
    _recurring.dispose();
    _promoCode.dispose();
    super.dispose();
  }

  void _seed(HostingServiceDetail d) {
    _domain.text = d.domain ?? '';
    _dedicatedIp.text = d.dedicatedIp ?? '';
    _username.text = d.username ?? '';
    _package.text = d.package ?? '';
    _quantity.text = d.quantity.toString();
    _firstPayment.text = d.firstPaymentAmount == null
        ? ''
        : Formatting.amount(d.firstPaymentAmount);
    _recurring.text = d.recurringAmount == null
        ? ''
        : Formatting.amount(d.recurringAmount);
    _promoCode.text = d.promoCode ?? '';
    _productServiceId = d.productServiceId;
    _status = d.status;
    _serverId = d.serverId;
    _paymentMethod = d.paymentMethod;
    _startDate = d.startDate;
    _nextDueDate = d.nextDueDate;
    _terminationDate = d.terminationDate;
    _recalculate = false;
    _error = null;
  }

  /// Fields carry grouped digits once seeded, so strip anything that is not
  /// part of the number before sending it back.
  double? _amount(TextEditingController controller) {
    final text = controller.text.replaceAll(RegExp(r'[^0-9.\-]'), '').trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  String? _trimmed(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save() async {
    final productId = _productServiceId;
    final status = _status;
    if (productId == null || status == null) {
      setState(() => _error = 'Choose the product and the status first.');
      return;
    }
    final quantity = int.tryParse(_quantity.text.trim()) ?? 0;
    if (quantity < 1) {
      setState(() => _error = 'Quantity must be at least 1.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(supportAdminServiceProvider)
          .updateHostingService(
            detail.id,
            productServiceId: productId,
            status: status,
            quantity: quantity,
            domain: _trimmed(_domain),
            dedicatedIp: _trimmed(_dedicatedIp),
            username: _trimmed(_username),
            package: _trimmed(_package),
            serverId: _serverId,
            startDate: _startDate,
            firstPaymentAmount: _amount(_firstPayment),
            // Ignored server-side when recalculating; sending it anyway would
            // only be confusing if the flag were ever dropped.
            recurringAmount: _recalculate ? null : _amount(_recurring),
            nextDueDate: _nextDueDate,
            terminationDate: _terminationDate,
            paymentMethod: _paymentMethod,
            promoCode: _trimmed(_promoCode),
            recalculate: _recalculate,
          );
      // The PUT answers with the saved record, but re-reading through the
      // provider is what keeps the list behind this screen honest too.
      ref.invalidate(hostingServiceProvider(detail.id));
      ref.invalidate(clientServicesProvider(detail.clientId));
      messenger.showSnackBar(const SnackBar(content: Text('Service saved.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The package belongs to whichever server the form is pointing at, not to
  /// whichever one provisioned it — changing both at once is exactly how a
  /// service gets moved.
  Future<void> _choosePackage() async {
    setState(() => _loadingPackages = true);
    final packages = await _fetchServerPackages(
      ref,
      _serverId ?? detail.hostingAccount?.serverId,
    );
    if (!mounted) return;
    setState(() => _loadingPackages = false);

    if (packages == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The server could not list its packages — type the name instead.',
          ),
        ),
      );
      return;
    }
    final picked = await _pickPackage(
      context,
      packages: packages,
      current: _trimmed(_package),
      eyebrow: detail.clientName,
    );
    if (picked != null && mounted) setState(() => _package.text = picked);
  }

  Future<void> _pickDate(
    DateTime? current,
    ValueChanged<DateTime?> onPicked,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _pickOption({
    required String title,
    required List<(String, String)> options,
    required String? selected,
    required ValueChanged<String?> onPicked,
    bool clearable = false,
  }) async {
    final picked = await showCrmSheet<String?>(
      context: context,
      builder: (sheetContext) => CrmSheet(
        eyebrow: detail.clientName,
        title: title,
        children: [
          if (clearable)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('None'),
              trailing: selected == null ? const Icon(Icons.check) : null,
              // A null pop is indistinguishable from a dismiss, so clearing
              // uses a sentinel the caller maps back to null.
              onTap: () => Navigator.of(sheetContext).pop(''),
            ),
          for (final (value, label) in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              trailing: value == selected ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(sheetContext).pop(value),
            ),
        ],
      ),
    );
    if (picked != null) onPicked(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canUpdate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(SupportAdminPermissions.clientSubscriptionsUpdate) ??
        false;
    final options = detail.options;
    final account = detail.hostingAccount;

    String productLabel(String? id) {
      for (final p in options.products) {
        if (p.id == id) return p.name;
      }
      return id == null ? 'Choose product' : '—';
    }

    String serverLabel(String? id) {
      for (final s in options.servers) {
        if (s.id == id) return s.label;
      }
      return id == null ? 'None' : (account?.serverHost ?? '—');
    }

    return ListView(
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
        _StatusHeader(detail: detail),
        const SizedBox(height: Spacing.lg),
        const SectionHeader('Service'),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Product / service',
          value: productLabel(_productServiceId),
          placeholder: _productServiceId == null,
          icon: Icons.inventory_2_outlined,
          onTap: !canUpdate || _saving
              ? null
              : () => _pickOption(
                  title: 'Product / service',
                  options: [for (final p in options.products) (p.id, p.name)],
                  selected: _productServiceId,
                  onPicked: (v) => setState(() => _productServiceId = v),
                ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Status',
          value: _status ?? 'Choose status',
          placeholder: _status == null,
          icon: Icons.flag_outlined,
          onTap: !canUpdate || _saving
              ? null
              : () => _pickOption(
                  title: 'Status',
                  options: [for (final s in options.statuses) (s, s)],
                  selected: _status,
                  onPicked: (v) => setState(() => _status = v),
                ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Server',
          value: serverLabel(_serverId),
          placeholder: _serverId == null,
          icon: Icons.dns_outlined,
          onTap: !canUpdate || _saving
              ? null
              : () => _pickOption(
                  title: 'Server',
                  options: [for (final s in options.servers) (s.id, s.label)],
                  selected: _serverId,
                  clearable: true,
                  onPicked: (v) => setState(() => _serverId = v),
                ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Domain',
          child: TextField(
            controller: _domain,
            enabled: canUpdate && !_saving,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'example.co.tz'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Dedicated IP',
          child: TextField(
            controller: _dedicatedIp,
            enabled: canUpdate && !_saving,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'None'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Username',
          child: TextField(
            controller: _username,
            enabled: canUpdate && !_saving,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'cPanel user'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'cPanel package',
          child: TextField(
            controller: _package,
            enabled: canUpdate && !_saving,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'Package name'),
          ),
        ),
        // The server's own list when we may ask for it; typing stays available
        // either way, because a package the server has since dropped still has
        // to be nameable.
        if (canUpdate)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.dns_outlined, size: 18),
              label: Text(
                _loadingPackages ? 'Loading packages…' : 'Choose from server',
              ),
              onPressed: _saving || _loadingPackages ? null : _choosePackage,
            ),
          ),
        const SizedBox(height: Spacing.lg),
        const SectionHeader('Billing'),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Registration date',
          value: _startDate == null ? 'Not set' : Formatting.date(_startDate),
          placeholder: _startDate == null,
          onTap: !canUpdate || _saving
              ? null
              : () => _pickDate(
                  _startDate,
                  (v) => setState(() => _startDate = v),
                ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Quantity',
          child: TextField(
            controller: _quantity,
            enabled: canUpdate && !_saving,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '1'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'First payment',
          child: TextField(
            controller: _firstPayment,
            enabled: canUpdate && !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '0.00'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Recurring amount',
          child: TextField(
            controller: _recurring,
            enabled: canUpdate && !_saving && !_recalculate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '0.00'),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _recalculate,
          onChanged: !canUpdate || _saving
              ? null
              : (v) => setState(() => _recalculate = v),
          title: const Text('Recalculate on save'),
          subtitle: Text(
            'Take the recurring amount from the product price × quantity.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        CrmPickerField(
          label: 'Next due date',
          value: _nextDueDate == null
              ? 'Not set'
              : Formatting.date(_nextDueDate),
          placeholder: _nextDueDate == null,
          onTap: !canUpdate || _saving
              ? null
              : () => _pickDate(
                  _nextDueDate,
                  (v) => setState(() => _nextDueDate = v),
                ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Termination date',
          value: _terminationDate == null
              ? 'Not set'
              : Formatting.date(_terminationDate),
          placeholder: _terminationDate == null,
          onTap: !canUpdate || _saving
              ? null
              : () => _pickDate(
                  _terminationDate,
                  (v) => setState(() => _terminationDate = v),
                ),
        ),
        if (_terminationDate != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _terminationDate = null),
              child: const Text('Clear termination date'),
            ),
          ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Payment method',
          value: _paymentMethod ?? 'None',
          placeholder: _paymentMethod == null,
          icon: Icons.account_balance_wallet_outlined,
          onTap: !canUpdate || _saving
              ? null
              : () => _pickOption(
                  title: 'Payment method',
                  options: [for (final m in options.paymentMethods) (m, m)],
                  selected: _paymentMethod,
                  clearable: true,
                  onPicked: (v) => setState(() => _paymentMethod = v),
                ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Promotion code',
          child: TextField(
            controller: _promoCode,
            enabled: canUpdate && !_saving,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'None'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        // Set by the product, not by this form — the web shows it read-only
        // too, and changing the product is how it moves.
        CrmDetailRow(
          'Billing cycle',
          (detail.billingCycle ?? '—').replaceAll('_', ' '),
        ),
        if (canUpdate) ...[
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: _saving ? 'Saving…' : 'Save changes',
            busy: _saving,
            icon: Icons.save_outlined,
            onPressed: _saving ? null : _save,
          ),
          // Typing does not go through setState, so the edited-ness of the
          // text fields has to be watched directly for this to appear.
          ListenableBuilder(
            listenable: Listenable.merge([
              _domain,
              _dedicatedIp,
              _username,
              _package,
              _quantity,
              _firstPayment,
              _recurring,
              _promoCode,
            ]),
            builder: (context, _) => _dirty
                ? TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _seed(detail)),
                    child: const Text('Discard changes'),
                  )
                : const SizedBox.shrink(),
          ),
        ],
        if (detail.metrics.isNotEmpty) ...[
          const SizedBox(height: Spacing.xl),
          const SectionHeader('Metric statistics'),
          const SizedBox(height: Spacing.sm),
          CrmCardList(
            children: [
              for (final metric in detail.metrics)
                ListTile(
                  dense: true,
                  // Whether cPanel is tracking the metric at all — a disabled
                  // one reads as "no usage" otherwise, which is a different
                  // thing entirely.
                  leading: Icon(
                    metric.enabled
                        ? Icons.check_circle_outline
                        : Icons.remove_circle_outline,
                    size: 18,
                    color: metric.enabled
                        ? context.statusColors.settled
                        : context.statusColors.inactive,
                  ),
                  title: Text(metric.metric, style: theme.textTheme.bodyMedium),
                  subtitle: metric.lastUpdate == null
                      ? null
                      : Text(
                          'Updated ${Formatting.dateTime(metric.lastUpdate)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                  trailing: Text(
                    metric.usage ?? '—',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The record's identity above the form: status, whether a server account
/// exists at all, and the certificate when something has looked.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.detail});

  final HostingServiceDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final account = detail.hostingAccount;
    final ssl = detail.ssl;

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusChip(detail.status, dense: true),
        if (account == null)
          Text(
            'NO SERVER ACCOUNT',
            style: theme.textTheme.labelSmall?.copyWith(color: status.inactive),
          )
        else ...[
          if (account.status != detail.status)
            StatusChip(account.status, dense: true),
          if (account.notOnWhm)
            Text(
              'NOT ON WHM',
              style: theme.textTheme.labelSmall?.copyWith(
                color: status.attention,
              ),
            ),
          if (account.serverHost != null)
            Text(
              account.serverHost!.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
        if (!ssl.unknown)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ssl.valid! ? Icons.lock_outline : Icons.lock_open_outlined,
                size: 14,
                color: ssl.valid! ? status.settled : status.inactive,
              ),
              const SizedBox(width: 4),
              Text(
                ssl.valid!
                    ? 'SSL${ssl.issuer == null ? '' : ' · ${ssl.issuer}'}'
                          .toUpperCase()
                    : 'NO SSL',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Module commands
// ---------------------------------------------------------------------------

/// The web's action bar, "More" menu and Module Commands row, gathered into
/// one sheet — a phone masthead has no room for eight buttons.
///
/// The commands split in two: the ones that key off the subscription
/// (`/hosting-services/*` on `client_subscriptions.update`) and the ones that
/// key off the cPanel account (`/hosting-accounts/*` on the `hosting.*`
/// permissions). Each is gated on exactly the permission its route enforces,
/// and the account ones disappear entirely when nothing was provisioned.
class _CommandsSheet extends ConsumerStatefulWidget {
  const _CommandsSheet({required this.detail});

  final HostingServiceDetail detail;

  @override
  ConsumerState<_CommandsSheet> createState() => _CommandsSheetState();
}

class _CommandsSheetState extends ConsumerState<_CommandsSheet> {
  bool _busy = false;

  HostingServiceDetail get detail => widget.detail;

  /// Every command reports the API's own message and re-reads the record —
  /// suspend/terminate change the status the form is showing.
  Future<void> _run(
    Future<String?> Function() action, {
    required String fallbackMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final message = await action();
      ref.invalidate(hostingServiceProvider(detail.id));
      ref.invalidate(clientServicesProvider(detail.clientId));
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? fallbackMessage)),
      );
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(sessionControllerProvider).session;
    bool can(String permission) => session?.can(permission) ?? false;

    final canUpdate = can(SupportAdminPermissions.clientSubscriptionsUpdate);
    final canSso = can(SupportAdminPermissions.hostingSso);
    final canSuspend = can(SupportAdminPermissions.hostingSuspend);
    final canTerminate = can(SupportAdminPermissions.hostingTerminate);
    final canChangePackage = can(SupportAdminPermissions.hostingChangePackage);
    final canCreate = can(SupportAdminPermissions.hostingCreate);
    final canDelete = can(SupportAdminPermissions.clientSubscriptionsDelete);

    final account = detail.hostingAccount;
    final service = ref.read(supportAdminServiceProvider);

    return CrmSheet(
      eyebrow: detail.clientName,
      title: detail.title,
      children: [
        if (account == null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: Text(
              canCreate
                  ? 'Nothing is provisioned on a server for this service yet. '
                        'Creating it makes the cPanel account from the '
                        'product, server and package on the form.'
                  : 'Nothing is provisioned on a server for this service, so '
                        'the module commands have nothing to act on.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (canCreate)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.add_circle_outline,
                color: context.statusColors.settled,
              ),
              title: const Text('Create on server'),
              subtitle: const Text('Provisions the cPanel account'),
              enabled: !_busy,
              onTap: () async {
                final ok = await _confirm(
                  title: 'Create the account?',
                  body:
                      'A cPanel account is created on the server for '
                      '${detail.title}, and the client is sent the welcome '
                      'message with its login.',
                  verb: 'Create',
                );
                if (!ok) return;
                await _run(
                  () => service.provisionSubscription(detail.id),
                  fallbackMessage: 'Provisioning queued.',
                );
              },
            ),
          const Divider(height: Spacing.lg),
        ],
        if (account != null) ...[
          if (canSso && account.isActive && account.isOnServer)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.login),
              title: const Text('Log in to cPanel'),
              enabled: !_busy,
              onTap: () => _run(() async {
                final url = await service.hostingSsoUrl(account.id);
                if (url.isNotEmpty) {
                  await launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                }
                return 'Opening cPanel…';
              }, fallbackMessage: 'Opening cPanel…'),
            ),
          if (canSuspend)
            account.isSuspended
                ? ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.play_circle_outline,
                      color: context.statusColors.settled,
                    ),
                    title: const Text('Unsuspend'),
                    enabled: !_busy,
                    onTap: () => _run(() async {
                      await service.unsuspendHosting(account.id);
                      return null;
                    }, fallbackMessage: 'Account unsuspended.'),
                  )
                : ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.pause_circle_outline,
                      color: scheme.error,
                    ),
                    title: Text(
                      'Suspend',
                      style: TextStyle(color: scheme.error),
                    ),
                    enabled: !_busy,
                    onTap: () async {
                      final ok = await _confirm(
                        title: 'Suspend ${detail.title}?',
                        body: 'The site goes offline until it is unsuspended.',
                        verb: 'Suspend',
                      );
                      if (!ok) return;
                      await _run(() async {
                        await service.suspendHosting(account.id);
                        return null;
                      }, fallbackMessage: 'Account suspended.');
                    },
                  ),
          if (canTerminate)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
              title: Text('Terminate', style: TextStyle(color: scheme.error)),
              enabled: !_busy,
              onTap: () async {
                final ok = await _confirm(
                  title: 'Terminate ${detail.title}?',
                  body:
                      'The cPanel account and everything on it is deleted at '
                      'the server. This cannot be undone.',
                  verb: 'Terminate',
                );
                if (!ok) return;
                await _run(
                  () => service.terminateHosting(account.id),
                  fallbackMessage: 'Termination queued.',
                );
              },
            ),
          if (canChangePackage) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Change package'),
              subtitle: const Text('On the server, not the billing plan'),
              enabled: !_busy,
              onTap: () async {
                final package = await _askPackage(
                  account.serverId ?? detail.serverId,
                );
                if (package == null || package.isEmpty) return;
                await _run(
                  () => service.changeHostingPackage(account.id, package),
                  fallbackMessage: 'Package change queued.',
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key_outlined),
              title: const Text('Change password'),
              enabled: !_busy,
              onTap: () async {
                final password = await _prompt(
                  title: 'Change cPanel password',
                  label: 'New password',
                  hint: 'At least 8 characters',
                  initial: '',
                  action: 'Change password',
                  obscure: true,
                  minLength: 8,
                );
                if (password == null || password.isEmpty) return;
                await _run(
                  () => service.changeHostingPassword(account.id, password),
                  fallbackMessage: 'cPanel password changed.',
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.password_outlined),
              title: const Text('Reset password & send welcome'),
              subtitle: const Text('The new password goes to the client only'),
              enabled: !_busy,
              onTap: () async {
                final ok = await _confirm(
                  title: 'Reset password?',
                  body:
                      'A new cPanel password is set on the server and sent to '
                      'the client with the welcome message.',
                  verb: 'Reset',
                );
                if (!ok) return;
                await _resetAndReveal(account.id);
              },
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync),
            title: const Text('Refresh usage'),
            enabled: !_busy,
            onTap: () => _run(() async {
              await service.refreshHostingUsage(account.id);
              return null;
            }, fallbackMessage: 'Usage refreshed from the server.'),
          ),
          const Divider(height: Spacing.lg),
        ],
        if (canUpdate) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.swap_vert),
            title: const Text('Upgrade / downgrade'),
            enabled: !_busy,
            onTap: () => Navigator.of(context).pop('upgrade'),
          ),
          if (account != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mark_email_read_outlined),
              title: const Text('Resend welcome message'),
              enabled: !_busy,
              onTap: () => _run(
                () => service.resendServiceWelcome(detail.id),
                fallbackMessage: 'Welcome message sent.',
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline),
            title: const Text('Send message'),
            enabled: !_busy,
            onTap: () => Navigator.of(context).pop('message'),
          ),
        ],
        const Divider(height: Spacing.lg),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: const Text('Client profile'),
          onTap: () => Navigator.of(context).pop('client'),
        ),
        // Always offered: with no order document there is still the client's
        // own invoice list to fall back to, which is the question being asked.
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(
            detail.orderDocumentId == null ? 'Client invoices' : 'Order invoice',
          ),
          onTap: () => Navigator.of(context).pop('invoice'),
        ),
        if (canDelete) ...[
          const Divider(height: Spacing.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: scheme.error),
            title: Text(
              'Delete service record',
              style: TextStyle(color: scheme.error),
            ),
            enabled: !_busy,
            onTap: () async {
              final ok = await _confirm(
                title: 'Delete this service?',
                body: account == null
                    ? 'The billing record for ${detail.title} is removed. '
                          'This cannot be undone.'
                    : 'The billing record for ${detail.title} is removed, but '
                          'the cPanel account keeps running unbilled — '
                          'terminate it first if it should go too. This '
                          'cannot be undone.',
                verb: 'Delete',
              );
              if (!ok) return;
              await _delete();
            },
          ),
        ],
      ],
    );
  }

  /// Deleting leaves nothing for the detail screen behind this sheet to show,
  /// so the sheet reports it and the screen pops itself.
  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(supportAdminServiceProvider)
          .deleteClientSubscription(detail.id);
      ref.invalidate(clientServicesProvider(detail.clientId));
      messenger.showSnackBar(const SnackBar(content: Text('Service deleted.')));
      navigator.pop('deleted');
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The server's package list when it can be had, the typed field when it
  /// cannot — a service on a server we may not query still has to be movable.
  Future<String?> _askPackage(String? serverId) async {
    final packages = await _fetchServerPackages(ref, serverId);
    if (!mounted) return null;
    if (packages != null) {
      return _pickPackage(
        context,
        packages: packages,
        current: detail.package,
        eyebrow: detail.clientName,
      );
    }
    return _prompt(
      title: 'Change package',
      label: 'WHM package name',
      hint: 'e.g. reseller_business',
      initial: detail.package ?? '',
      action: 'Change package',
    );
  }

  /// Reset, then show what the server generated. This response is the only
  /// place the password ever appears — [_run] would close the sheet before it
  /// could be read, so this handles its own busy state and pops afterwards.
  Future<void> _resetAndReveal(String accountId) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await ref
          .read(supportAdminServiceProvider)
          .resetHostingWelcome(accountId);
      ref.invalidate(hostingServiceProvider(detail.id));
      final password = result.password;
      if (!mounted) return;
      if (password == null || password.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Password reset and welcome sent.'),
          ),
        );
      } else {
        await _revealPassword(password);
      }
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revealPassword(String password) => showCrmSheet<void>(
    context: context,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return CrmSheet(
        eyebrow: detail.title,
        title: 'New cPanel password',
        children: [
          Text(
            'Set on the server and emailed to the client. Note it now — it is '
            'not shown again.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: SelectableText(
              password,
              textAlign: TextAlign.center,
              style: Type.mono(
                18,
                tracking: 0.08,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Copy and close',
            icon: Icons.copy_outlined,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: password));
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
        ],
      );
    },
  );

  Future<bool> _confirm({
    required String title,
    required String body,
    required String verb,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(verb),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// One-field dialog for the two commands that need a value typed. Returns
  /// null when dismissed.
  Future<String?> _prompt({
    required String title,
    required String label,
    required String hint,
    required String initial,
    required String action,
    bool obscure = false,
    int minLength = 1,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          autocorrect: false,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          // The confirm button follows the field, so a too-short password
          // can't be submitted only for the API to reject it.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => FilledButton(
              onPressed: value.text.trim().length < minLength
                  ? null
                  : () => Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(action),
            ),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

// ---------------------------------------------------------------------------
// Upgrade / downgrade
// ---------------------------------------------------------------------------

/// The plan-change offer: every plan in the same product group with what the
/// move costs today. A change that costs something raises a prorated invoice
/// and applies when it is paid; anything else applies now.
class _UpgradeSheet extends ConsumerStatefulWidget {
  const _UpgradeSheet({required this.detail});

  final HostingServiceDetail detail;

  @override
  ConsumerState<_UpgradeSheet> createState() => _UpgradeSheetState();
}

class _UpgradeSheetState extends ConsumerState<_UpgradeSheet> {
  String? _picked;
  bool _busy = false;
  String? _error;

  Future<void> _apply(ServiceUpgradePlan plan, String mode) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await ref
          .read(supportAdminServiceProvider)
          .applyServiceUpgrade(
            widget.detail.id,
            productServiceId: plan.id,
            mode: mode,
          );
      ref.invalidate(hostingServiceProvider(widget.detail.id));
      ref.invalidate(clientServicesProvider(widget.detail.clientId));
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final options = ref.watch(serviceUpgradeOptionsProvider(widget.detail.id));

    return CrmSheet(
      eyebrow: widget.detail.clientName,
      title: 'Upgrade / downgrade',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        options.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Spacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          // A 422 here is the answer, not a failure: no product, or the
          // service is still billed in WHMCS during parallel operation.
          error: (error, _) => ErrorBanner(
            message: error is ApiException
                ? error.message
                : 'Upgrade and downgrade are not available for this service.',
          ),
          data: (offer) {
            final plans = offer.plans.where((p) => !p.isCurrent).toList();
            ServiceUpgradePlan? picked;
            for (final plan in plans) {
              if (plan.id == _picked) picked = plan;
            }
            // A final local, so the closures below see it promoted.
            final chosen = picked;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CrmDetailRow('Current plan', offer.currentPlanName),
                CrmDetailRow(
                  'Recurring',
                  Formatting.currency(offer.currentPlanPrice),
                ),
                CrmDetailRow(
                  'Next due',
                  offer.nextDueDate == null
                      ? '—'
                      : Formatting.date(offer.nextDueDate),
                ),
                const SizedBox(height: Spacing.md),
                if (plans.isEmpty)
                  Text(
                    'There is no other plan in this product group.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else
                  CrmCardList(
                    children: [
                      for (final plan in plans)
                        ListTile(
                          onTap: _busy
                              ? null
                              : () => setState(() => _picked = plan.id),
                          trailing: plan.id == _picked
                              ? const Icon(Icons.check)
                              : null,
                          title: Text(
                            plan.name,
                            style: theme.textTheme.titleSmall,
                          ),
                          subtitle: Text(
                            [
                              plan.direction.toUpperCase(),
                              Formatting.currency(plan.price),
                              if (plan.proratedDue > 0)
                                'DUE NOW ${Formatting.amount(plan.proratedDue)}'
                              else if (plan.proratedCredit > 0)
                                'CREDIT ${Formatting.amount(plan.proratedCredit)}'
                              else
                                'NO CHARGE',
                            ].join(' · '),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: plan.direction == 'upgrade'
                                  ? status.pending
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (chosen != null) ...[
                  const SizedBox(height: Spacing.md),
                  Text(
                    chosen.proratedDue > 0
                        ? 'A prorated invoice for '
                              '${Formatting.currency(chosen.proratedDue)} is '
                              'created; the plan changes when it is paid. '
                              'Applying now skips the charge.'
                        : chosen.proratedCredit > 0
                        ? 'The plan switches now, recurring becomes '
                              '${Formatting.currency(chosen.price)}, and '
                              '${Formatting.currency(chosen.proratedCredit)} '
                              'is credited to the wallet.'
                        : 'The plan switches now and recurring becomes '
                              '${Formatting.currency(chosen.price)}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  PrimaryButton(
                    label: chosen.proratedDue > 0
                        ? 'Create prorated invoice'
                        : 'Apply change',
                    busy: _busy,
                    onPressed: _busy
                        ? null
                        : () => _apply(
                            chosen,
                            chosen.proratedDue > 0 ? 'invoice' : 'immediate',
                          ),
                  ),
                  if (chosen.proratedDue > 0)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _apply(chosen, 'immediate'),
                      child: const Text('Apply now without charging'),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Free-form message
// ---------------------------------------------------------------------------

/// Emails the client under the tenant's branding. Subject and body are both
/// required, and the API caps them at 255 and 20 000 characters.
class _SendMessageSheet extends ConsumerStatefulWidget {
  const _SendMessageSheet({required this.detail});

  final HostingServiceDetail detail;

  @override
  ConsumerState<_SendMessageSheet> createState() => _SendMessageSheetState();
}

class _SendMessageSheetState extends ConsumerState<_SendMessageSheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final subject = _subject.text.trim();
    final body = _body.text.trim();
    if (subject.isEmpty || body.isEmpty) {
      setState(() => _error = 'A subject and a message are both required.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final message = await ref
          .read(supportAdminServiceProvider)
          .sendServiceMessage(widget.detail.id, subject: subject, body: body);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Message sent.')),
      );
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CrmSheet(
      eyebrow: widget.detail.clientName,
      title: 'Send message',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Subject',
          child: TextField(
            controller: _subject,
            enabled: !_sending,
            maxLength: 255,
            decoration: const InputDecoration(hintText: 'What it is about'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Message',
          child: TextField(
            controller: _body,
            enabled: !_sending,
            minLines: 5,
            maxLines: 12,
            maxLength: 20000,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(hintText: 'Write the message'),
          ),
        ),
        Text(
          'Emailed to the client under your company branding.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _sending ? 'Sending…' : 'Send message',
          busy: _sending,
          icon: Icons.mail_outline,
          onPressed: _sending ? null : _send,
        ),
      ],
    );
  }
}
