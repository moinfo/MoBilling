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
  // Strict-imprest flag — present on expense items only. When false, the
  // expense's voucher hasn't been signed/attached yet, so it does NOT
  // reduce the verified balance (but DOES count toward committed cash).
  voucher_attached?: boolean;
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
  // Verified balance — the official remaining float. Only signed-voucher
  // expenses reduce this. Shown as the headline number.
  balance: string;
  // Committed balance — what is physically left in the till after ALL
  // expenses (signed or pending). Used by the insufficient-funds guard.
  committed_balance: string;
  // Sum of expenses that have not yet had their signed voucher attached.
  // verified - pending = committed.
  pending_vouchers: {
    count: number;
    total: string;
  };
  history: PettyCashHistoryItem[];
  reconciliations: PettyCashReconciliation[];
}

export const getPettyCash = () =>
  api.get<PettyCashIndexResponse>('/petty-cash');

// Reference is auto-generated server-side (PC-YYYY-NNNN per tenant), so
// the caller doesn't pass one.
export const createPettyCashTransaction = (data: {
  type: 'top_up' | 'return';
  amount: number;
  transaction_date: string;
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
