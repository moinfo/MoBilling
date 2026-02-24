import api from './axios';

export interface SubExpenseCategory {
  id: string;
  expense_category_id: string;
  name: string;
  is_active: boolean;
}

export interface ExpenseCategory {
  id: string;
  name: string;
  is_active: boolean;
  sub_categories: SubExpenseCategory[];
}

export interface ExpenseCategoryFormData {
  expense_category_id?: string | null;
  name: string;
  is_active?: boolean;
}

export const getExpenseCategories = () =>
  api.get<{ data: ExpenseCategory[] }>('/expense-categories');

export const createExpenseCategory = (data: ExpenseCategoryFormData) =>
  api.post('/expense-categories', data);

export const updateExpenseCategory = (id: string, data: ExpenseCategoryFormData) =>
  api.put(`/expense-categories/${id}`, data);

export const deleteExpenseCategory = (id: string) =>
  api.delete(`/expense-categories/${id}`);
