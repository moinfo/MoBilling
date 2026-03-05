import api from './axios';

export interface CollectionInvoice {
  id: string;
  document_number: string;
  client_name: string;
  client_id: string;
  total: number;
  paid_amount: number;
  balance_due: number;
  status: string;
  due_date?: string;
  days_overdue?: number;
  days_until_due?: number;
}

export interface CollectionPayment {
  id: string;
  amount: number;
  payment_method: string | null;
  reference: string | null;
  document_number: string | null;
  client_name: string | null;
}

export interface CollectionSummary {
  total_outstanding: number;
  total_invoiced: number;
  total_partial_paid: number;
  unpaid_count: number;
  today_due: number;
  today_due_paid: number;
  today_collected: number;
  today_balance: number;
  overdue_total: number;
  overdue_paid: number;
  overdue_balance: number;
  month_target: number;
  month_collected: number;
  month_balance: number;
}

export interface AgingBreakdown {
  current: number;
  '1_30': number;
  '31_60': number;
  '61_90': number;
  over_90: number;
}

export interface CallPlanEntry {
  document_id: string;
  document_number: string;
  client_name: string;
  client_phone: string | null;
  balance: number;
  due_date: string;
  type: 'reminder' | 'due_date' | 'overdue_urgent' | 'overdue_followup' | 'followup';
  label: string;
  has_followup: boolean;
}

export type CallPlan = Record<string, CallPlanEntry[]>;

export interface CollectionDashboard {
  summary: CollectionSummary;
  aging: AgingBreakdown;
  today_due: CollectionInvoice[];
  today_payments: CollectionPayment[];
  overdue: CollectionInvoice[];
  upcoming: CollectionInvoice[];
  call_plan: CallPlan;
}

export const getCollectionDashboard = () =>
  api.get<{ data: CollectionDashboard }>('/collection/dashboard');
