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

export interface WalletStatus {
  balance: number;
  is_wallet_gated: boolean;
  pesapal_configured: boolean;
  ledger: WalletLedgerRow[];
}

export const getWallet = () => api.get<{ data: WalletStatus }>('/wallet');

export const topupWalletPesapal = (amount: number) =>
  api.post<{ data: { topup_id: string; redirect_url: string | null }; message: string }>('/wallet/topup/pesapal', { amount });

export const getWalletTopupStatus = (topupId: string) =>
  api.get<{ data: { status: string; amount: number } }>(`/wallet/topup/${topupId}/status`);
