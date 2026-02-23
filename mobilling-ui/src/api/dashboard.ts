import api from './axios';

export interface DashboardSummary {
  total_receivable: number;
  total_received: number;
  outstanding: number;
  overdue_invoices: number;
  overdue_bills: number;
  total_clients: number;
  total_documents: number;
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
}

export const getDashboardSummary = () =>
  api.get<DashboardSummary>('/dashboard/summary');
