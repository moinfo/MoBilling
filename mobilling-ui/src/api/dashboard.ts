import api from './axios';

export interface MonthlyRevenue {
  month: string;
  invoiced: number;
  collected: number;
}

export interface InvoiceStatusItem {
  status: string;
  count: number;
}

export interface PaymentMethodItem {
  method: string;
  amount: number;
}

export interface TopClient {
  name: string;
  total: number;
  paid: number;
}

export interface SubscriptionStats {
  active: number;
  pending: number;
  cancelled: number;
}

export interface UpcomingRenewal {
  client_name: string;
  product_name: string;
  label: string;
  next_bill_date: string;
  price: number;
}

export interface StatutoryStats {
  total_active: number;
  overdue: number;
  due_soon: number;
}

export interface UrgentObligation {
  id: string;
  name: string;
  amount: string;
  next_due_date: string;
  days_remaining: number;
  cycle: string;
}

export interface CalendarItem {
  type: 'followup' | 'satisfaction' | 'appointment' | 'invoice' | 'bill' | 'statutory' | 'whatsapp' | 'field_followup';
  label: string;
  detail: string | null;
}

export interface CalendarDay {
  date: string;
  items: CalendarItem[];
}

export interface SystemRecordPropertyTotal {
  name: string;
  total: number;
}

export interface SystemRecordSystemBreakdown {
  name: string;
  subtotal: number;
  properties: SystemRecordPropertyTotal[];
}

export interface SystemRecordBankTotal {
  bank_account_id: string | null;
  bank_name: string;
  account_number: string | null;
  total: number;
}

export interface SystemRecordsBreakdown {
  total: number;
  systems: SystemRecordSystemBreakdown[];
  by_bank: SystemRecordBankTotal[];
}

export interface ExpiringDomain {
  id: string;
  name: string;
  client_name: string | null;
  expires_at: string;
  days_left: number;
  auto_renew: boolean;
}
export interface HostingDomainsSummary {
  can: { hosting: boolean; domains: boolean; tickets: boolean };
  hosting?: { total: number; active: number; suspended: number };
  domains?: { total: number; active: number; expiring_soon: number };
  open_tickets?: number;
  registrar_credit_total?: number | null;
  expiring_domains?: ExpiringDomain[];
}

export interface StaffPenaltyItem {
  id: string;
  report_type: 'daily' | 'weekly' | 'monthly';
  penalty_type: 'missing' | 'late';
  period_date: string;
  amount: number;
  notes: string | null;
}
export interface StaffPenaltiesSummary {
  month_label: string;
  month_total: number;
  count_this_month: number;
  items: StaffPenaltyItem[];
}

export interface DashboardSummary {
  staff_penalties?: StaffPenaltiesSummary | null;
  hosting_domains?: HostingDomainsSummary;
  total_expenses: number;
  total_receivable: number;
  total_received: number;
  outstanding: number;
  overdue_invoices: number;
  overdue_bills: number;
  total_clients: number;
  total_documents: number;
  total_whatsapp_contacts: number;
  total_field_visits: number;
  sms_balance?: number | null;
  sms_enabled?: boolean;
  recent_invoices: {
    id: string;
    document_number: string;
    client_name: string;
    total: string;
    status: string;
    date: string;
  }[];
  upcoming_bills: {
    id: string;
    name: string;
    amount: string;
    due_date: string;
    category: string;
  }[];
  monthly_revenue: MonthlyRevenue[];
  invoice_status_breakdown: InvoiceStatusItem[];
  payment_method_breakdown: PaymentMethodItem[];
  top_clients: TopClient[];
  subscription_stats: SubscriptionStats;
  upcoming_renewals: UpcomingRenewal[];
  statutory_stats: StatutoryStats;
  urgent_obligations: UrgentObligation[];
  calendar: CalendarDay[];
  system_records: SystemRecordsBreakdown;
}

export const getDashboardSummary = (month: number, year: number) =>
  api.get<DashboardSummary>('/dashboard/summary', { params: { month, year } });
