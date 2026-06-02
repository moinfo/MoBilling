import api from './axios';

export interface PettyCashAccount {
  id: string;
  name: string;
  opening_balance: string;
  is_active: boolean;
}

export type PettyCashHistoryKind =
  | 'top_up'
  | 'return'
  | 'adjustment_in'
  | 'adjustment_out'
  | 'expense';

export interface PettyCashHistoryItem {
  id: string;
  kind: PettyCashHistoryKind;
  date: string;
  amount: string;
  description: string;
  reference: string | null;
  notes: string | null;
  reconciliation_id?: string | null;
  category?: string | null;
  sub_category?: string | null;
  created_by?: string | null;
  created_at: string;
}

export interface PettyCashReconciliation {
  id: string;
  reconciled_at: string;
  ledger_balance: string;
  counted_balance: string;
  difference: string;
  resolution: 'accepted' | 'investigating';
  notes: string | null;
  created_by?: { id: string; name: string } | null;
}

export interface PettyCashIndexResponse {
  account: PettyCashAccount;
  balance: string;
  history: PettyCashHistoryItem[];
  reconciliations: PettyCashReconciliation[];
}

export const getPettyCash = () =>
  api.get<PettyCashIndexResponse>('/petty-cash');

export const createPettyCashTransaction = (data: {
  type: 'top_up' | 'return';
  amount: number;
  transaction_date: string;
  reference?: string;
  notes?: string;
  given_by_name?: string;
  received_by_name?: string;
}) => api.post('/petty-cash/transactions', data);

export const createPettyCashReconciliation = (data: {
  counted_balance: number;
  reconciled_at?: string;
  resolution: 'accepted' | 'investigating';
  notes?: string;
}) => api.post('/petty-cash/reconciliations', data);

// Voucher PDF download — returns a Blob (browser handles the file download).
export const downloadPettyCashTransactionVoucher = (id: string) =>
  api.get(`/petty-cash/transactions/${id}/voucher`, { responseType: 'blob' });

export const uploadPettyCashTransactionVoucher = (id: string, file: File) => {
  const fd = new FormData();
  fd.append('voucher', file);
  return api.post(`/petty-cash/transactions/${id}/voucher`, fd, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};
