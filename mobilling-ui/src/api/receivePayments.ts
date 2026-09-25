import api from './axios';

export interface UnpaidInvoice {
  id: string;
  document_number: string;
  status: 'sent' | 'overdue' | 'partial';
  date: string | null;
  due_date: string | null;
  is_overdue: boolean;
  total: number;
  paid_amount: number;
  balance_due: number;
  client: { id: string; name: string; phone: string | null; credit_balance: number } | null;
}

export interface OfflineMethod { value: string; label: string; reference_required: boolean }

export interface RecordedPayment {
  id: string; amount: number; payment_method: string; reference: string | null; payment_date: string;
  created_at: string; client_name: string | null; document_number: string | null; undoable: boolean; has_proof: boolean;
}

export interface ParsedMessage {
  parsed: { amount: number | null; reference: string | null; phone: string | null; name: string | null; invoice_number: string | null };
  suggestions: { id: string; document_number: string; client_name: string | null; balance_due: number }[];
}

export interface RecordResult {
  message: string;
  replayed: boolean;
  excess_credit: number;
  invoices: { document_id: string; document_number: string; amount: number; balance_after: number; status: string; payment_id: string }[];
  payment_ids: string[];
}

export const getReceiveOptions = () =>
  api.get<{ methods: OfflineMethod[]; can_undo: boolean; undo_minutes: number }>('/receive-payments/options');

export const getUnpaidInvoices = (params: Record<string, string | number | boolean | undefined>) =>
  api.get('/receive-payments/invoices', { params });

export const getRecentRecorded = () => api.get<{ data: RecordedPayment[] }>('/receive-payments/recent');

export const parsePaymentMessage = (text: string) => api.post<ParsedMessage>('/receive-payments/parse', { text });

export const recordOfflinePayment = (fd: FormData) => api.post<RecordResult>('/receive-payments', fd);

export const undoRecordedPayment = (id: string) => api.delete(`/receive-payments/${id}`);
