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

export interface DashboardSummary {
  total_expenses: number;
  total_receivable: number;
  total_received: number;
  outstanding: number;
  overdue_invoices: number;
  overdue_bills: number;
  total_clients: number;
  total_documents: number;
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
}

export const getDashboardSummary = () =>
  api.get<DashboardSummary>('/dashboard/summary');
