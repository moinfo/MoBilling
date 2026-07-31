import 'package:flutter_test/flutter_test.dart';
import 'package:mobilling_api/mobilling_api.dart';

void main() {
  group('PortalDashboard', () {
    test('parses the mixed string/number money fields the backend emits', () {
      // Faithful to PortalDashboardController::summary — the uncast ->sum()
      // fields arrive as STRINGS while their PHP-arithmetic sibling and the
      // hand-cast row fields arrive as numbers. This mix is the whole reason
      // parsing is tolerant; if this test fails the dashboard crashes.
      final dash = PortalDashboard.fromJson({
        'credit_balance': 2500.0,
        'services_count': 3,
        'domains_count': 2,
        'tickets_count': 1,
        'unpaid_invoices_count': 2,
        'expiring_domains_count': 0,
        'overdue_count': 1,
        'total_invoiced': '125000.00', // string: uncast sum()
        'total_paid': '100000.00', // string: uncast sum()
        'total_balance': 25000, // number: PHP subtraction
        'client_info': {
          'company': 'Acme Ltd',
          'contact': 'Asha',
          'email': 'billing@acme.co.tz',
          'address': null,
          'phone': '+255700000001',
        },
        'recent_services': [
          {
            'id': 's1',
            'product': 'Web Hosting',
            'label': 'acme.co.tz',
            'status': 'active',
            'hosting_account_id': 'h1',
          },
          {
            'id': 's2',
            'product': 'SSL',
            'label': null,
            'status': 'pending',
            'hosting_account_id': null,
          },
        ],
        'contacts': [
          {'id': 'c2', 'name': 'Juma', 'email': 'juma@acme.co.tz', 'role': 'user'},
        ],
        'recent_tickets': [
          {
            'id': 't1',
            'ticket_number': 'TKT-001',
            'subject': 'DNS issue',
            'status': 'open',
            'last_reply_at': '2026-07-28T09:15:00.000000Z',
          },
        ],
        'announcements': [
          {
            'id': 'a1',
            'title': 'Maintenance window',
            'excerpt': 'Saturday 02:00–04:00 EAT…',
            'published_at': '2026-07-25T12:00:00.000000Z',
          },
        ],
        'recent_invoices': [
          {
            'id': 'i1',
            'document_number': 'INV-0042',
            'description': 'Web Hosting — acme.co.tz',
            'date': '2026-07-01',
            'due_date': '2026-07-15',
            'total': 50000.0,
            'paid': 25000.0,
            'balance': 25000.0,
            'status': 'partial',
          },
        ],
        'recent_payments': [
          {
            'id': 'p1',
            'payment_date': '2026-07-10T00:00:00.000000Z',
            'amount': 25000.0,
            'payment_method': 'mpesa',
            'reference': 'QX12ABC',
            'document_number': 'INV-0042',
          },
        ],
        'upcoming_subscriptions': [
          {
            'id': 's1',
            'service': 'Web Hosting',
            'label': 'acme.co.tz',
            'price': 50000.0,
            'quantity': 1,
            'schedule': 'Yearly',
            'next_invoice_date': '2027-07-01',
          },
        ],
      });

      expect(dash.totalInvoiced, 125000.0);
      expect(dash.totalPaid, 100000.0);
      expect(dash.totalBalance, 25000.0);
      expect(dash.clientInfo?.company, 'Acme Ltd');
      expect(dash.clientInfo?.address, isNull);
      expect(dash.recentServices, hasLength(2));
      expect(dash.recentServices[1].hostingAccountId, isNull);
      expect(dash.recentInvoices.single.status, 'partial');
      expect(dash.recentPayments.single.documentNumber, 'INV-0042');
      expect(dash.upcomingSubscriptions.single.nextInvoiceDate?.year, 2027);
    });

    test('an empty payload parses to a usable zero-state', () {
      final dash = PortalDashboard.fromJson(const {});
      expect(dash.totalBalance, 0);
      expect(dash.recentInvoices, isEmpty);
      expect(dash.clientInfo, isNull);
    });
  });

  group('InvoiceSummary', () {
    test('reads the paginated-index shape (raw model + appended fields)', () {
      // The index returns the Eloquent model: decimal:2 casts are STRINGS and
      // the computed fields are appended as numbers.
      final row = InvoiceSummary.fromJson({
        'id': 'i1',
        'document_number': 'INV-0042',
        'type': 'invoice',
        'date': '2026-07-01T00:00:00.000000Z',
        'due_date': '2026-07-15T00:00:00.000000Z',
        'subtotal': '50000.00',
        'total': '50000.00', // string: decimal cast
        'status': 'overdue',
        'paid_amount': 25000.0, // number: appended with round()
        'balance_due': 25000.0,
        'items': [
          {'id': 'it1', 'description': 'Web Hosting — acme.co.tz'},
        ],
      });

      expect(row.total, 50000.0);
      expect(row.paid, 25000.0);
      expect(row.balance, 25000.0);
      expect(row.description, 'Web Hosting — acme.co.tz');
      expect(row.dueDate?.day, 15);
    });

    test('prefers dashboard-shape paid/balance keys when present', () {
      final row = InvoiceSummary.fromJson({
        'id': 'i1',
        'document_number': 'INV-0042',
        'total': 100.0,
        'paid': 60.0,
        'balance': 40.0,
        'status': 'partial',
      });
      expect(row.paid, 60.0);
      expect(row.balance, 40.0);
    });
  });

  group('PortalDocument', () {
    test('parses the show() shape with panels and offline methods', () {
      final doc = PortalDocument.fromJson({
        'id': 'i1',
        'document_number': 'INV-0042',
        'type': 'invoice',
        'status': 'partial',
        'date': '2026-07-01T00:00:00.000000Z',
        'due_date': '2026-07-15T00:00:00.000000Z',
        'subtotal': '42372.88',
        'discount_amount': '0.00',
        'tax_amount': '7627.12',
        'total': '50000.00',
        'notes': null,
        'paid_amount': 25000.0,
        'balance_due': 25000.0,
        'late_fee': 0.0,
        'items': [
          {
            'id': 'it1',
            'description': 'Web Hosting — acme.co.tz',
            'quantity': '1.00',
            'price': '42372.88',
            'total': '42372.88',
            'service_from': '2026-07-01',
            'service_to': '2027-06-30',
          },
        ],
        'payments': [
          {
            'id': 'p1',
            'amount': '25000.00', // raw model: string
            'payment_date': '2026-07-10T00:00:00.000000Z',
            'payment_method': 'mpesa',
            'reference': 'QX12ABC',
          },
        ],
        'invoiced_to': {
          'name': 'Acme Ltd',
          'address': 'Dar es Salaam',
          'email': 'billing@acme.co.tz',
          'phone': null,
          'tax_id': '123-456-789',
        },
        'pay_to': {'name': 'Moinfotech', 'email': 'info@moinfotech.co.tz'},
        'payment_methods': [
          {'name': 'CRDB Bank', 'details': 'A/C 0150-XXXX — Moinfotech Ltd'},
          {'name': 'M-Pesa', 'details': 'Lipa namba 5555555'},
        ],
      });

      expect(doc.total, 50000.0);
      expect(doc.taxAmount, closeTo(7627.12, 0.001));
      expect(doc.isPayable, isTrue);
      expect(doc.items.single.serviceTo?.year, 2027);
      expect(doc.payments.single.amount, 25000.0);
      expect(doc.invoicedTo?.taxId, '123-456-789');
      expect(doc.paymentMethods, hasLength(2));
    });

    test('isPayable is false once settled', () {
      final doc = PortalDocument.fromJson({
        'id': 'i1',
        'status': 'paid',
        'total': '50000.00',
        'paid_amount': 50000.0,
        'balance_due': 0.0,
      });
      expect(doc.isPayable, isFalse);
    });
  });

  group('PaymentSummary', () {
    test('reads the paginated raw-model shape with nested document', () {
      final p = PaymentSummary.fromJson({
        'id': 'p1',
        'amount': '25000.00', // decimal:2 cast → string
        'payment_date': '2026-07-10T00:00:00.000000Z',
        'payment_method': 'bank',
        'reference': null,
        'document_id': 'i1',
        'document': {'id': 'i1', 'document_number': 'INV-0042', 'type': 'invoice'},
      });

      expect(p.amount, 25000.0);
      expect(p.documentNumber, 'INV-0042');
      expect(p.documentId, 'i1');
      expect(p.reference, isNull);
    });
  });

  group('CheckoutSession / InvoicePaymentStatus', () {
    test('parses a checkout response', () {
      final s = CheckoutSession.fromJson({
        'payment_id': 'pp1',
        'redirect_url': 'https://pay.pesapal.com/iframe?x=1',
        'order_tracking_id': 'OT-123',
      });
      expect(s.paymentId, 'pp1');
      expect(s.redirectUrl, contains('pesapal'));
    });

    test('a declined checkout has no redirect url', () {
      final s = CheckoutSession.fromJson({'payment_id': 'pp1'});
      expect(s.redirectUrl, isNull);
    });

    test('status transitions map to the settled flags', () {
      final pending = InvoicePaymentStatus.fromJson({
        'status': 'pending',
        'amount': '25000.00',
      });
      expect(pending.isSettled, isFalse);
      expect(pending.amount, 25000.0);

      final done = InvoicePaymentStatus.fromJson({
        'status': 'completed',
        'amount': 25000.0,
        'confirmation_code': 'QX99ZZZ',
        'payment_method': 'MpesaTZ',
        'completed_at': '2026-07-30T10:00:00.000000Z',
      });
      expect(done.isCompleted, isTrue);
      expect(done.confirmationCode, 'QX99ZZZ');

      final failed = InvoicePaymentStatus.fromJson({
        'status': 'failed',
        'amount': 25000.0,
      });
      expect(failed.isFailed, isTrue);
      expect(failed.isSettled, isTrue);
    });
  });

  group('Statement', () {
    test('parses entries with the server-side running balance', () {
      final s = Statement.fromJson({
        'entries': [
          {
            'date': '2026-07-01',
            'type': 'invoice',
            'reference': 'INV-0042',
            'description': 'Invoice INV-0042',
            'debit': 50000.0,
            'credit': 0,
            'balance': 50000.0,
          },
          {
            'date': '2026-07-10',
            'type': 'payment',
            'reference': 'QX12ABC',
            'description': 'Payment - mpesa',
            'debit': 0,
            'credit': 25000.0,
            'balance': 25000.0,
          },
        ],
        'total_debits': 50000.0,
        'total_credits': 25000.0,
        'closing_balance': 25000.0,
      });

      expect(s.entries, hasLength(2));
      expect(s.entries.last.isPayment, isTrue);
      expect(s.entries.last.balance, 25000.0);
      expect(s.closingBalance, 25000.0);
    });
  });
}
