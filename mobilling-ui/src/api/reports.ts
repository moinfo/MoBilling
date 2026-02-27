import api from './axios';

// ─── Shared types ────────────────────────────────────────────

export interface DateRange {
  start_date: string;
  end_date: string;
}

// ─── 1. Revenue Summary ─────────────────────────────────────

export interface RevenueMonth {
  month: string;
  invoiced: number;
  collected: number;
}

export interface RevenueInvoice {
  id: string;
  document_number: string;
  client_name: string;
  date: string;
  total: number;
  paid: number;
  balance: number;
  status: string;
}

export interface RevenueSummary {
  months: RevenueMonth[];
  total_invoiced: number;
  total_collected: number;
  collection_rate: number;
  revenue_growth: number | null;
  invoices: RevenueInvoice[];
}

export const getRevenueSummary = (params: DateRange) =>
  api.get<RevenueSummary>('/reports/revenue-summary', { params });

// ─── 2. Outstanding & Aging ─────────────────────────────────

export interface AgingInvoice {
  id: string;
  document_number: string;
  client_name: string;
  total: number;
  paid: number;
  balance: number;
  due_date: string;
  days_overdue: number;
}

export interface OutstandingAging {
  bands: Record<string, AgingInvoice[]>;
  band_totals: Record<string, number>;
  total_outstanding: number;
  total_invoices: number;
}

export const getOutstandingAging = () =>
  api.get<OutstandingAging>('/reports/outstanding-aging');

// ─── 3. Client Statement ────────────────────────────────────

export interface StatementEntry {
  date: string;
  type: string;
  reference: string;
  debit: number;
  credit: number;
  balance: number;
}

export interface ClientStatement {
  client: { id: string; name: string; email: string };
  entries: StatementEntry[];
  total_debit: number;
  total_credit: number;
  closing_balance: number;
}

export const getClientStatement = (params: DateRange & { client_id: string }) =>
  api.get<ClientStatement>('/reports/client-statement', { params });

// ─── 4. Payment Collection ──────────────────────────────────

export interface PaymentMethodStat {
  method: string;
  count: number;
  total: number;
}

export interface DailyCollection {
  day: string;
  total: number;
  count: number;
}

export interface PaymentDetail {
  id: string;
  payment_date: string;
  amount: number;
  payment_method: string;
  reference: string | null;
  document_number: string | null;
  client_name: string | null;
}

export interface PaymentCollection {
  by_method: PaymentMethodStat[];
  daily_trend: DailyCollection[];
  total_collected: number;
  total_transactions: number;
  payments: PaymentDetail[];
}

export const getPaymentCollection = (params: DateRange) =>
  api.get<PaymentCollection>('/reports/payment-collection', { params });

// ─── 5. Expense Report ──────────────────────────────────────

export interface ExpenseSubCategory {
  name: string;
  total: number;
  count: number;
}

export interface ExpenseCategoryGroup {
  category: string;
  total: number;
  sub_categories: ExpenseSubCategory[];
}

export interface ExpenseMonthly {
  month: string;
  total: number;
}

export interface ExpenseDetail {
  id: string;
  expense_date: string;
  description: string;
  amount: number;
  category: string | null;
  sub_category: string | null;
  payment_method: string | null;
  reference: string | null;
}

export interface ExpenseReport {
  by_category: ExpenseCategoryGroup[];
  monthly_trend: ExpenseMonthly[];
  total_expenses: number;
  expenses: ExpenseDetail[];
}

export const getExpenseReport = (params: DateRange) =>
  api.get<ExpenseReport>('/reports/expense-report', { params });

// ─── 6. Profit & Loss ───────────────────────────────────────

export interface ProfitLossMonth {
  month: string;
  revenue: number;
  bill_payments: number;
  expenses: number;
  net_profit: number;
}

export interface ProfitLossEntry {
  date: string;
  type: string;
  description: string;
  client: string | null;
  amount: number;
}

export interface ProfitLoss {
  revenue: number;
  bill_payments: number;
  expenses: number;
  total_costs: number;
  net_profit: number;
  profit_margin: number;
  months: ProfitLossMonth[];
  entries: ProfitLossEntry[];
}

export const getProfitLoss = (params: DateRange) =>
  api.get<ProfitLoss>('/reports/profit-loss', { params });

// ─── 7. Statutory Compliance ────────────────────────────────

export interface ComplianceObligation {
  id: string;
  name: string;
  category: string;
  cycle: string;
  amount: number;
  next_due_date: string;
  days_until_due: number;
  status: string;
  paid_on_time: number;
  paid_late: number;
  unpaid: number;
}

export interface ComplianceSummary {
  total_active: number;
  overdue: number;
  due_soon: number;
  on_track: number;
  compliance_rate: number;
}

export interface StatutoryCompliance {
  summary: ComplianceSummary;
  obligations: ComplianceObligation[];
}

export const getStatutoryCompliance = () =>
  api.get<StatutoryCompliance>('/reports/statutory-compliance');

// ─── 8. Subscription Report ─────────────────────────────────

export interface UpcomingRenewal {
  client_name: string;
  product_name: string;
  label: string;
  next_bill_date: string;
  price: number;
  days_until: number;
}

export interface SubscriptionReport {
  by_status: { active: number; pending: number; cancelled: number };
  total_subscriptions: number;
  active_monthly_revenue: number;
  monthly_forecast: number;
  upcoming_renewals: UpcomingRenewal[];
}

export const getSubscriptionReport = () =>
  api.get<SubscriptionReport>('/reports/subscription-report');

// ─── 9. Collection Effectiveness ────────────────────────────

export interface EffectivenessMonth {
  month: string;
  total: number;
  promised: number;
  paid: number;
  no_answer: number;
}

export interface FollowupDetail {
  id: string;
  call_date: string;
  client_name: string | null;
  document_number: string | null;
  outcome: string;
  notes: string | null;
  promise_date: string | null;
  promise_amount: number | null;
  agent: string | null;
  status: string;
}

export interface CollectionEffectiveness {
  total_followups: number;
  by_outcome: Record<string, number>;
  promise_count: number;
  promises_fulfilled: number;
  fulfillment_rate: number;
  monthly_trend: EffectivenessMonth[];
  followups: FollowupDetail[];
}

export const getCollectionEffectiveness = (params: DateRange) =>
  api.get<CollectionEffectiveness>('/reports/collection-effectiveness', { params });

// ─── 10. Communication Log ──────────────────────────────────

export interface ChannelStat {
  channel: string;
  total: number;
  sent: number;
  failed: number;
  delivery_rate: number;
}

export interface TypeStat {
  type: string;
  total: number;
  sent: number;
  failed: number;
}

export interface DailyVolume {
  day: string;
  total: number;
  sent: number;
  failed: number;
}

export interface MessageDetail {
  id: string;
  created_at: string;
  channel: string;
  type: string;
  recipient: string;
  client_name: string | null;
  subject: string | null;
  status: string;
  error: string | null;
}

export interface CommunicationLogReport {
  by_channel: ChannelStat[];
  by_type: TypeStat[];
  daily_volume: DailyVolume[];
  total: number;
  total_sent: number;
  total_failed: number;
  overall_delivery_rate: number;
  messages: MessageDetail[];
}

export const getCommunicationLog = (params: DateRange) =>
  api.get<CommunicationLogReport>('/reports/communication-log', { params });
