import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';

/// Open a new support ticket.
class NewTicketScreen extends ConsumerStatefulWidget {
  const NewTicketScreen({super.key});

  @override
  ConsumerState<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends ConsumerState<NewTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final List<PlatformFile> _attachments = [];

  // Values from Ticket::DEPARTMENTS / ::PRIORITIES.
  String _department = 'support';
  String _priority = 'medium';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    setState(() {
      _attachments.addAll(result.files.where((f) => f.path != null));
      while (_attachments.length > 5) {
        _attachments.removeLast();
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final ticket = await ref
          .read(portalServiceProvider)
          .createTicket(
            subject: _subject.text.trim(),
            message: _message.text.trim(),
            department: _department,
            priority: _priority,
            attachmentPaths: _attachments
                .map((f) => f.path!)
                .toList(growable: false),
          );
      ref.invalidate(portalTicketsProvider);
      if (!mounted) return;
      // Straight into the new thread — that's where the reply will arrive.
      context.pushReplacement(PortalRoutes.ticketPath(ticket.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('subject') ?? e.errorFor('message') ?? e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Support', title: 'New ticket'),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(Spacing.md),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: Spacing.md),
                ],
                FieldLabel('Subject'),
                const SizedBox(height: Spacing.sm),
                TextFormField(
                  controller: _subject,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'One line on what this is about',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter a subject'
                      : null,
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FieldLabel('Department'),
                          const SizedBox(height: Spacing.sm),
                          DropdownButtonFormField<String>(
                            initialValue: _department,
                            items: const [
                              DropdownMenuItem(
                                value: 'support',
                                child: Text('Support'),
                              ),
                              DropdownMenuItem(
                                value: 'billing',
                                child: Text('Billing'),
                              ),
                              DropdownMenuItem(
                                value: 'sales',
                                child: Text('Sales'),
                              ),
                            ],
                            onChanged: _submitting
                                ? null
                                : (v) => setState(() => _department = v!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FieldLabel('Priority'),
                          const SizedBox(height: Spacing.sm),
                          DropdownButtonFormField<String>(
                            initialValue: _priority,
                            items: const [
                              DropdownMenuItem(
                                value: 'low',
                                child: Text('Low'),
                              ),
                              DropdownMenuItem(
                                value: 'medium',
                                child: Text('Medium'),
                              ),
                              DropdownMenuItem(
                                value: 'high',
                                child: Text('High'),
                              ),
                            ],
                            onChanged: _submitting
                                ? null
                                : (v) => setState(() => _priority = v!),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                FieldLabel('How can we help?'),
                const SizedBox(height: Spacing.sm),
                TextFormField(
                  controller: _message,
                  enabled: !_submitting,
                  minLines: 5,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText:
                        'What happened, what you expected, and anything you '
                        'have already tried',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Describe the issue'
                      : null,
                ),
                const SizedBox(height: Spacing.md),
                if (_attachments.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: Spacing.xs,
                      runSpacing: Spacing.xs,
                      children: [
                        for (final (i, f) in _attachments.indexed)
                          InputChip(
                            label: Text(f.name),
                            onDeleted: () =>
                                setState(() => _attachments.removeAt(i)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _submitting ? null : _pick,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Attach files'),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Up to 5 files, 5 MB each.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                PrimaryButton(
                  label: 'Open ticket',
                  busy: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
                const SizedBox(height: Spacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
