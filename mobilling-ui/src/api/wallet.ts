import api from './axios';

export interface WalletLedgerRow {
  id: string;
  type: 'topup' | 'debit' | 'refund';
  amount: number;
  balance_after: number;
  reference: string | null;
  notes: string | null;
  created_at: string;
}

export interface WalletPendingTopup {
  id: string;
  amount: number;
  method: 'pesapal' | 'lipa_number';
  reference: string;
  created_at: string;
}

export interface WalletStatus {
  balance: number;
  is_wallet_gated: boolean;
  pesapal_configured: boolean;
  ledger: WalletLedgerRow[];
  pending_topups: WalletPendingTopup[];
}

export const getWallet = () => api.get<{ data: WalletStatus }>('/wallet');

export const topupWalletPesapal = (amount: number) =>
  api.post<{ data: { topup_id: string; redirect_url: string | null }; message: string }>('/wallet/topup/pesapal', { amount });

export const topupWalletInvoice = (amount: number) =>
  api.post<{ data: { topup_id: string; reference: string }; message: string }>('/wallet/topup/invoice', { amount });

export const downloadWalletTopupInvoice = (topupId: string) =>
  api.get(`/wallet/topup/${topupId}/invoice`, { responseType: 'blob' });

export const getWalletTopupStatus = (topupId: string) =>
  api.get<{ data: { status: string; amount: number } }>(`/wallet/topup/${topupId}/status`);
