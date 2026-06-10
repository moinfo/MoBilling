import api from './axios';

export interface BankAccount {
  id: string;
  bank_name: string;
  account_number: string;
  is_active: boolean;
  created_at: string;
}

export interface BankAccountPayload {
  bank_name: string;
  account_number: string;
  is_active?: boolean;
}

export const getBankAccounts = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/bank-accounts', { params });

export const createBankAccount = (data: BankAccountPayload) =>
  api.post('/bank-accounts', data);

export const updateBankAccount = (id: string, data: BankAccountPayload) =>
  api.put(`/bank-accounts/${id}`, data);

export const deleteBankAccount = (id: string) =>
  api.delete(`/bank-accounts/${id}`);
