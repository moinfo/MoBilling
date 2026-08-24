import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

/// Reads for the client module. Each one is keyed by client id and disposed
/// with the screen, so leaving a profile and coming back re-reads rather than
/// showing a record that has since been edited elsewhere.
///
/// Every provider carries an explicit type annotation; see `providers.dart`
/// for why.

/// The counters above the client list. Not keyed — one set per tenant.
final AutoDisposeFutureProvider<ClientCounters> clientCountersProvider =
    FutureProvider.autoDispose<ClientCounters>(
      (ref) => ref.watch(staffServiceProvider).clientStats(),
    );

/// The whole 360 payload for one client: the record, the money summary,
/// subscriptions, invoices, domains, tickets and hosting in a single call.
final AutoDisposeFutureProviderFamily<ClientProfile, String>
clientProfileProvider = FutureProvider.autoDispose
    .family<ClientProfile, String>(
      (ref, clientId) =>
          ref.watch(staffServiceProvider).clientProfile(clientId),
    );

/// Additional contacts. The profile carries a copy, but this is the list the
/// contacts editor writes against, so it re-reads on its own after a save
/// without pulling the whole profile down again.
final AutoDisposeFutureProviderFamily<List<ClientContact>, String>
clientContactsProvider = FutureProvider.autoDispose
    .family<List<ClientContact>, String>(
      (ref, clientId) =>
          ref.watch(staffServiceProvider).clientContacts(clientId),
    );

/// Balance plus ledger. Needs `credit.manage`; callers gate on it, because a
/// 403 here would otherwise read as a broken wallet rather than a missing
/// permission.
final AutoDisposeFutureProviderFamily<ClientCreditLedger, String>
clientCreditProvider = FutureProvider.autoDispose
    .family<ClientCreditLedger, String>(
      (ref, clientId) => ref.watch(staffServiceProvider).clientCredit(clientId),
    );

/// What the system actually sent this client, with delivery status.
final AutoDisposeFutureProviderFamily<List<ClientCommunication>, String>
clientCommunicationsProvider = FutureProvider.autoDispose
    .family<List<ClientCommunication>, String>(
      (ref, clientId) => ref
          .watch(staffServiceProvider)
          .clientCommunications(clientId, limit: 50),
    );

/// Satisfaction call history. Behind `menu.satisfaction_calls`, which most
/// billing roles do not hold — the section is dropped rather than shown
/// empty when they don't.
final AutoDisposeFutureProviderFamily<List<SatisfactionCall>, String>
clientSatisfactionProvider = FutureProvider.autoDispose
    .family<List<SatisfactionCall>, String>(
      (ref, clientId) =>
          ref.watch(staffServiceProvider).clientSatisfactionCalls(clientId),
    );
