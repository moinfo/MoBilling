/// Route paths for the client-portal shell.
///
/// Kept separate from the staff [Routes] for two reasons: every path is
/// namespaced under `/portal` so a client and a staff route can never collide
/// (both shells have a "ticket detail", and they are different screens), and
/// the two classes would otherwise define `ticketPath` with different
/// meanings — a name that resolves differently depending on which import won
/// is exactly the kind of ambiguity that produces a wrong screen at runtime.
abstract final class PortalRoutes {
  static const home = '/portal';
  static const register = '/portal/register';
  static const payments = '/portal/payments';
  static const statement = '/portal/statement';
  static const store = '/portal/store';
  static const configureOrder = '/portal/store/configure';
  static const domainSearch = '/portal/domain-search';
  static const profile = '/portal/profile';
  static const portalUsers = '/portal/users';
  static const credit = '/portal/credit';
  static const reseller = '/portal/reseller';

  /// `new` must be registered before `:id` — go_router matches in order.
  static const newTicket = '/portal/tickets/new';

  static String invoicePath(String id) => '/portal/invoices/$id';
  static String ticketPath(String id) => '/portal/tickets/$id';
  static String kbPath(String slug) => '/portal/kb/$slug';
  static String hostingPath(String id) => '/portal/hosting/$id';
  static String domainPath(String id) => '/portal/domains/$id';
}

/// Hand-off from sign-in to the OTP/registration screen.
///
/// Carried when `/auth/login` answers 449 — the code is already in the user's
/// inbox, so the register screen opens straight on the code step rather than
/// asking for an address the server just verified.
class RegisterArgs {
  const RegisterArgs({required this.email, this.clientName});

  final String email;

  /// The company the backend matched, shown as reassurance that the code went
  /// to the right account.
  final String? clientName;
}
