/// Account-area models: profile, portal users, credit wallet.
/// Shapes match `PortalProfileController` and `PortalCreditController`.
library;

import '../json.dart';

class PortalProfile {
  const PortalProfile({
    required this.id,
    required this.name,
    required this.role,
    this.email,
    this.phone,
    this.companyName,
    this.companyAddress,
    this.companyEmail,
    this.companyPhone,
    this.taxId,
  });

  final String id;
  final String name;
  final String role;
  final String? email;
  final String? phone;
  final String? companyName;
  final String? companyAddress;
  final String? companyEmail;
  final String? companyPhone;
  final String? taxId;

  bool get isAdmin => role == 'admin';

  factory PortalProfile.fromJson(Map<String, dynamic> json) {
    final user = json.object('user') ?? json;
    final client = json.object('client');
    return PortalProfile(
      id: user.id(),
      name: user.strOr('name', '—'),
      role: user.strOr('role', 'viewer'),
      email: user.str('email'),
      phone: user.str('phone'),
      companyName: client?.str('name'),
      companyAddress: client?.str('address'),
      companyEmail: client?.str('email'),
      companyPhone: client?.str('phone'),
      taxId: client?.str('tax_id'),
    );
  }
}

class PortalUser {
  const PortalUser({
    required this.id,
    required this.name,
    required this.role,
    required this.isActive,
    this.email,
    this.phone,
    this.lastLoginAt,
  });

  final String id;
  final String name;

  /// admin | viewer (staff-side calls the non-admin role 'viewer'; login
  /// responses call it 'user' — treat anything but 'admin' as viewer).
  final String role;
  final bool isActive;
  final String? email;
  final String? phone;
  final DateTime? lastLoginAt;

  bool get isAdmin => role == 'admin';

  factory PortalUser.fromJson(Map<String, dynamic> json) => PortalUser(
        id: json.id(),
        name: json.strOr('name', '—'),
        role: json.strOr('role', 'viewer'),
        isActive: json.flag('is_active', fallback: true),
        email: json.str('email'),
        phone: json.str('phone'),
        lastLoginAt: json.date('last_login_at'),
      );
}

class CreditWallet {
  const CreditWallet({required this.balance, required this.ledger});

  final double balance;
  final List<CreditEntry> ledger;

  factory CreditWallet.fromJson(Map<String, dynamic> json) => CreditWallet(
        balance: json.money('balance'),
        ledger: json.list('ledger', CreditEntry.fromJson),
      );
}

class CreditEntry {
  const CreditEntry({
    required this.id,
    required this.type,
    required this.amount,
    this.notes,
    this.createdAt,
  });

  final String id;

  /// topup | apply | refund … (topup_pending rows are filtered server-side).
  final String type;
  final double amount;
  final String? notes;
  final DateTime? createdAt;

  /// Money coming *into* the wallet (top-ups) vs going out (applied to
  /// invoices).
  bool get isDeposit => type == 'topup' || type == 'refund';

  factory CreditEntry.fromJson(Map<String, dynamic> json) => CreditEntry(
        id: json.id(),
        type: json.strOr('type', 'topup'),
        amount: json.money('amount'),
        notes: json.str('notes'),
        createdAt: json.date('created_at'),
      );
}
