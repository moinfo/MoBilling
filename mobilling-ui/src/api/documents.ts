import api from './axios';
import { Client } from './clients';

export interface DocumentItem {
  id?: string;
  product_service_id: string | null;
  item_type: 'product' | 'service';
  description: string;
  quantity: number;
  price: number;
  discount_type: 'percent' | 'flat';
  discount_value: number;
  tax_percent: number;
  tax_amount?: number;
  total?: number;
  unit: string;
  service_from?: string | null;
  service_to?: string | null;
}

export interface Document {
  id: string;
  type: 'quotation' | 'proforma' | 'invoice';
  document_number: string;
  client: Client;
  client_id: string;
  parent_id: string | null;
  date: string;
  due_date: string | null;
  subtotal: string;
  discount_amount: string;
  tax_amount: string;
  total: string;
  notes: string | null;
  status: string;
  overdue_stage: string | null;
  reminder_count: number;
  paid_amount: number;
  balance_due: number;
  items: DocumentItem[];
  payments?: Payment[];
  created_at: string;
}

export interface Payment {
  id: string;
  document_id: string;
  amount: string;
  payment_date: string;
  payment_method: string;
  reference: string | null;
  notes: string | null;
  created_at: string;
}

export interface DocumentFormData {
  client_id: string;
  type: 'quotation' | 'proforma' | 'invoice';
  date: string;
  due_date: string | null;
  notes: string;
  items: DocumentItem[];
}

export const getDocuments = (params?: { type?: string; search?: string; page?: number; status?: string; per_page?: number; date_from?: string; date_to?: string }) =>
  api.get('/documents', { params });

export const getDocument = (id: string) =>
  api.get<{ data: Document }>(`/documents/${id}`);

export const createDocument = (data: DocumentFormData) =>
  api.post('/documents', data);

export const updateDocument = (id: string, data: DocumentFormData) =>
  api.put(`/documents/${id}`, data);

export const deleteDocument = (id: string) =>
  api.delete(`/documents/${id}`);

export const convertDocument = (id: string, targetType: string) =>
  api.post(`/documents/${id}/convert`, { target_type: targetType });

export const downloadPdf = (id: string) =>
  api.get(`/documents/${id}/pdf`, { responseType: 'blob' });

export const sendDocument = (id: string) =>
  api.post(`/documents/${id}/send`);

export const submitForApproval = (id: string) =>
  api.patch(`/documents/${id}/submit-for-approval`);

export const approveDocument = (id: string) =>
  api.patch(`/documents/${id}/approve`);

export const rejectDocument = (id: string, reason?: string) =>
  api.patch(`/documents/${id}/reject`, { reason });

export const updateDocumentDueDate = (id: string, due_date: string) =>
  api.patch(`/documents/${id}/due-date`, { due_date });

export const returnDocumentToDraft = (id: string) =>
  api.patch(`/documents/${id}/return-to-draft`);

// Payments In
export const getPaymentsIn = (params?: { document_id?: string; page?: number; per_page?: number; search?: string; date_from?: string; date_to?: string }) =>
  api.get('/payments-in', { params });

export const createPaymentIn = (data: {
  document_id: string;
  amount: number;
  payment_date: string;
  payment_method: string;
  reference?: string;
  notes?: string;
}) => api.post('/payments-in', data);

export const updatePaymentIn = (id: string, data: {
  document_id: string;
  amount: number;
  payment_date: string;
  payment_method: string;
  reference?: string;
  notes?: string;
}) => api.put(`/payments-in/${id}`, data);

export const deletePaymentIn = (id: string) =>
  api.delete(`/payments-in/${id}`);

export const resendReceipt = (id: string) =>
  api.post(`/payments-in/${id}/resend-receipt`);

export const resendInvoice = (documentId: string) =>
  api.post(`/documents/${documentId}/send`);

export const remindUnpaid = (documentIds: string[], channel: 'email' | 'sms' | 'whatsapp' | 'both') =>
  api.post('/documents/remind-unpaid', { document_ids: documentIds, channel });

export const cancelDocument = (id: string) =>
  api.patch(`/documents/${id}/cancel`);

export const uncancelDocument = (id: string) =>
  api.patch(`/documents/${id}/uncancel`);

export const removeDocumentItem = (documentId: string, itemId: string) =>
  api.delete(`/documents/${documentId}/items/${itemId}`);

export const mergeInvoices = (documentIds: string[]) =>
  api.post<{ data: Document; message: string }>('/documents/merge', { document_ids: documentIds });

// Next Bills
export interface NextBillItem {
  subscription_id: string;
  client_id: string;
  client_name: string;
  client_email: string;
  product_service_id: string;
  product_service_name: string;
  billing_cycle: string;
  price: string;
  quantity: number;
  last_billed: string | null;
  next_bill: string | null;
  is_overdue: boolean;
}

export const getNextBills = () =>
  api.get<{ data: NextBillItem[] }>('/next-bills');
