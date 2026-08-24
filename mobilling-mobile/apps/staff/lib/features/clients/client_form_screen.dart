import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart' show CrmField;
import 'client_providers.dart';

/// Create or edit a client — the screen that closes the gap between meeting
/// someone and them existing in the system.
///
/// One form for both verbs, because `POST /clients` and `PUT /clients/{id}`
/// take the identical payload (`StoreClientRequest`). The five fields staff
/// actually fill on a phone sit at the top; the WHMCS-style structured name
/// and address are real columns the web collects, so they are here too — but
/// folded away, since a domain registration needs them and a walk-in does
/// not.
///
/// The API writes the whole validated payload on update, so the form is
/// seeded from the full record and always sends every field back. Seeding it
/// from a partial row would blank the columns this screen never showed.
class ClientFormScreen extends ConsumerStatefulWidget {
  const ClientFormScreen({super.key, this.existing});

  /// Null creates; anything else edits that record.
  final StaffClient? existing;

  @override
  ConsumerState<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends ConsumerState<ClientFormScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _taxId = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _companyName = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _postcode = TextEditingController();
  final _country = TextEditingController();

  bool _saving = false;
  String? _error;

  StaffClient? get _existing => widget.existing;

  bool get _isEdit => _existing != null;

  @override
  void initState() {
    super.initState();
    final client = _existing;
    if (client == null) return;
    _name.text = client.name;
    _email.text = client.email ?? '';
    _phone.text = client.phone ?? '';
    _address.text = client.address ?? '';
    _taxId.text = client.taxId ?? '';
    _firstName.text = client.firstName ?? '';
    _lastName.text = client.lastName ?? '';
    _companyName.text = client.companyName ?? '';
    _address1.text = client.address1 ?? '';
    _address2.text = client.address2 ?? '';
    _city.text = client.city ?? '';
    _state.text = client.state ?? '';
    _postcode.text = client.postcode ?? '';
    _country.text = client.country ?? '';
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _address,
      _taxId,
      _firstName,
      _lastName,
      _companyName,
      _address1,
      _address2,
      _city,
      _state,
      _postcode,
      _country,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// True when the record already carries structured details, so the fold
  /// starts open rather than hiding values the reader is here to check.
  bool get _hasDetails => [
    _firstName,
    _lastName,
    _companyName,
    _address1,
    _address2,
    _city,
    _state,
    _postcode,
    _country,
  ].any((c) => c.text.trim().isNotEmpty);

  String? _value(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  /// Catches locally only what the API would reject with a 422 anyway — a
  /// round trip to be told the country code is three letters is a round trip
  /// wasted on a phone connection.
  String? _validate() {
    if (_name.text.trim().isEmpty) return 'A name is required.';
    final email = _value(_email);
    if (email != null && !RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      return 'That email address does not look right.';
    }
    final country = _value(_country);
    if (country != null && country.length != 2) {
      return 'Country is a two-letter code, e.g. TZ.';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final input = ClientInput(
      name: _name.text.trim(),
      email: _value(_email),
      phone: _value(_phone),
      address: _value(_address),
      taxId: _value(_taxId),
      firstName: _value(_firstName),
      lastName: _value(_lastName),
      companyName: _value(_companyName),
      address1: _value(_address1),
      address2: _value(_address2),
      city: _value(_city),
      state: _value(_state),
      postcode: _value(_postcode),
      country: _value(_country),
    );

    try {
      final service = ref.read(staffServiceProvider);
      final existing = _existing;
      final saved = existing == null
          ? await service.createClient(input)
          : await service.updateClient(existing.id, input);

      // The list counters move on a create, and the profile behind this
      // screen is stale after either.
      ref.invalidate(clientCountersProvider);
      ref.invalidate(clientProfileProvider(saved.id));

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? '${saved.name} added.' : '${saved.name} saved.',
          ),
        ),
      );
      navigator.pop(saved);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: _isEdit ? _existing!.name : 'Clients',
        title: _isEdit ? 'Edit client' : 'New client',
      ),
      body: ListView(
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
          CrmField(
            label: 'Name',
            child: TextField(
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Person or company as invoiced',
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Email',
            child: TextField(
              controller: _email,
              enabled: !_saving,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'name@example.co.tz'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Phone',
            child: TextField(
              controller: _phone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: '+255 7xx xxx xxx'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Address',
            child: TextField(
              controller: _address,
              enabled: !_saving,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(hintText: 'Street, city'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Tax ID / TIN',
            child: TextField(
              controller: _taxId,
              enabled: !_saving,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'e.g. 123-456-789'),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: _hasDetails,
              shape: const RoundedRectangleBorder(side: BorderSide.none),
              collapsedShape: const RoundedRectangleBorder(
                side: BorderSide.none,
              ),
              title: Text(
                'Registrant details',
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Text(
                'Needed to register a domain in their name',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(
                Spacing.md,
                0,
                Spacing.md,
                Spacing.md,
              ),
              children: [
                CrmField(
                  label: 'First name',
                  child: TextField(
                    controller: _firstName,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Given name'),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Last name',
                  child: TextField(
                    controller: _lastName,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Family name'),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Company',
                  child: TextField(
                    controller: _companyName,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Registered company name',
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Address line 1',
                  child: TextField(
                    controller: _address1,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Street'),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Address line 2',
                  child: TextField(
                    controller: _address2,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Building, floor',
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'City',
                  child: TextField(
                    controller: _city,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Dar es Salaam',
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'State / region',
                  child: TextField(
                    controller: _state,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Region'),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Postcode',
                  child: TextField(
                    controller: _postcode,
                    enabled: !_saving,
                    autocorrect: false,
                    decoration: const InputDecoration(hintText: 'Postal code'),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Country',
                  child: TextField(
                    controller: _country,
                    enabled: !_saving,
                    autocorrect: false,
                    maxLength: 2,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseFormatter()],
                    decoration: const InputDecoration(
                      hintText: 'TZ',
                      counterText: '',
                      helperText: 'Two-letter code',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: _saving
                ? 'Saving…'
                : (_isEdit ? 'Save changes' : 'Add client'),
            busy: _saving,
            icon: _isEdit ? Icons.save_outlined : Icons.person_add_alt,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Email and phone are unique per company — if someone already has '
            'this number, search for them instead of creating a second '
            'record.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Upper-cases as you type. The API validates the country as a two-letter
/// code and stores it verbatim, so `tz` would round-trip as lower case and
/// disagree with every other record.
class UpperCaseFormatter extends TextInputFormatter {
  const UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => TextEditingValue(
    text: newValue.text.toUpperCase(),
    selection: newValue.selection,
    composing: TextRange.empty,
  );
}
