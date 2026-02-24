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
}

export const getExpenses = (params?: {
  search?: string;
  page?: number;
  sub_expense_category_id?: string;
  per_page?: number;
}) => api.get('/expenses', { params });

export const getExpense = (id: string) =>
  api.get<{ data: Expense }>(`/expenses/${id}`);

export const createExpense = (data: {
  sub_expense_category_id?: string | null;
  description: string;
  amount: number;
  expense_date: string;
  payment_method: string;
  control_number?: string;
  reference?: string;
  notes?: string;
  attachment?: File | null;
}) => {
  const formData = new FormData();
  if (data.sub_expense_category_id) formData.append('sub_expense_category_id', data.sub_expense_category_id);
  formData.append('description', data.description);
  formData.append('amount', String(data.amount));
  formData.append('expense_date', data.expense_date);
  formData.append('payment_method', data.payment_method);
  if (data.control_number) formData.append('control_number', data.control_number);
  if (data.reference) formData.append('reference', data.reference);
  if (data.notes) formData.append('notes', data.notes);
  if (data.attachment) formData.append('attachment', data.attachment);
  return api.post('/expenses', formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};

export const updateExpense = (id: string, data: {
  sub_expense_category_id?: string | null;
  description: string;
  amount: number;
  expense_date: string;
  payment_method: string;
  control_number?: string;
  reference?: string;
  notes?: string;
  attachment?: File | null;
}) => {
  const formData = new FormData();
  formData.append('_method', 'PUT');
  if (data.sub_expense_category_id) formData.append('sub_expense_category_id', data.sub_expense_category_id);
  formData.append('description', data.description);
  formData.append('amount', String(data.amount));
  formData.append('expense_date', data.expense_date);
  formData.append('payment_method', data.payment_method);
  if (data.control_number) formData.append('control_number', data.control_number);
  if (data.reference) formData.append('reference', data.reference);
  if (data.notes) formData.append('notes', data.notes);
  if (data.attachment) formData.append('attachment', data.attachment);
  return api.post(`/expenses/${id}`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};

export const deleteExpense = (id: string) =>
  api.delete(`/expenses/${id}`);
