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

export interface CollectionDashboard {
  summary: CollectionSummary;
  today_due: CollectionInvoice[];
  today_payments: CollectionPayment[];
  overdue: CollectionInvoice[];
  upcoming: CollectionInvoice[];
}

export const getCollectionDashboard = () =>
  api.get<{ data: CollectionDashboard }>('/collection/dashboard');
