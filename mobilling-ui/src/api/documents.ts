import api from './axios';
import { Client } from './clients';

export interface DocumentItem {
  id?: string;
  product_service_id: string | null;
  item_type: 'product' | 'service';
  description: string;
  quantity: number;
  price: number;
  tax_percent: number;
  tax_amount?: number;
  total?: number;
  unit: string;
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
  tax_amount: string;
  total: string;
  notes: string | null;
  status: string;
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

export const getDocuments = (params?: { type?: string; search?: string; page?: number; status?: string }) =>
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

// Payments In
export const createPaymentIn = (data: {
  document_id: string;
  amount: number;
  payment_date: string;
  payment_method: string;
  reference?: string;
  notes?: string;
}) => api.post('/payments-in', data);
