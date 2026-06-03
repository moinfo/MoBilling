import api from './axios';

export interface Expense {
  id: string;
  sub_expense_category_id: string | null;
  sub_category?: {
    id: string;
    name: string;
    category: { id: string; name: string };
  };
  description: string;
  amount: string;
  expense_date: string;
  payment_method: string;
  control_number: string | null;
  reference: string | null;
  notes: string | null;
  attachment_url: string | null;
  // Petty cash linkage (nullable when not paid from petty cash)
  petty_cash_account_id: string | null;
  given_by_name: string | null;
  received_by_name: string | null;
  voucher_attachment_url: string | null;
}

export const getExpenses = (params?: {
  search?: string;
  page?: number;
  sub_expense_category_id?: string;
  per_page?: number;
  date_from?: string;
  date_to?: string;
}) => api.get('/expenses', { params });

export const getExpense = (id: string) =>
  api.get<{ data: Expense }>(`/expenses/${id}`);

export interface ExpensePayload {
  sub_expense_category_id?: string | null;
  description: string;
  amount: number;
  expense_date: string;
  payment_method: string;
  control_number?: string;
  reference?: string;
  notes?: string;
  attachment?: File | null;
  // Petty cash linkage — pass these when the expense is paid from petty cash.
  petty_cash_account_id?: string | null;
  given_by_name?: string;
  received_by_name?: string;
}

const buildExpenseFormData = (data: ExpensePayload, includeMethodOverride = false) => {
  const fd = new FormData();
  if (includeMethodOverride) fd.append('_method', 'PUT');
  if (data.sub_expense_category_id) fd.append('sub_expense_category_id', data.sub_expense_category_id);
  if (data.petty_cash_account_id) fd.append('petty_cash_account_id', data.petty_cash_account_id);
  fd.append('description', data.description);
  fd.append('amount', String(data.amount));
  fd.append('expense_date', data.expense_date);
  fd.append('payment_method', data.payment_method);
  if (data.control_number) fd.append('control_number', data.control_number);
  if (data.reference) fd.append('reference', data.reference);
  if (data.notes) fd.append('notes', data.notes);
  if (data.given_by_name !== undefined) fd.append('given_by_name', data.given_by_name);
  if (data.received_by_name !== undefined) fd.append('received_by_name', data.received_by_name);
  if (data.attachment) fd.append('attachment', data.attachment);
  return fd;
};

export const createExpense = (data: ExpensePayload) =>
  api.post('/expenses', buildExpenseFormData(data), {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export const updateExpense = (id: string, data: ExpensePayload) =>
  api.post(`/expenses/${id}`, buildExpenseFormData(data, true), {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export const deleteExpense = (id: string) =>
  api.delete(`/expenses/${id}`);

// Petty cash voucher per expense
export const downloadExpenseVoucher = (id: string) =>
  api.get(`/expenses/${id}/voucher`, { responseType: 'blob' });

export const uploadExpenseVoucher = (id: string, file: File) => {
  const fd = new FormData();
  fd.append('voucher', file);
  return api.post(`/expenses/${id}/voucher`, fd, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};
