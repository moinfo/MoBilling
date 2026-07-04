import api from './axios';
import { Document, DocumentItem } from './documents';

export interface CreditNoteItemInput {
  product_service_id: string | null;
  item_type: 'product' | 'service';
  description: string;
  quantity: number;
  price: number;
  discount_type: 'percent' | 'flat';
  discount_value: number;
  tax_percent: number;
  unit: string;
}

export interface CreateCreditNoteData {
  client_id: string;
  source_invoice_id?: string | null;
  cancel_source_invoice?: boolean;
  date?: string | null;
  notes?: string;
  items: CreditNoteItemInput[];
}

export const getCreditNotes = (params?: {
  search?: string; page?: number; status?: string; per_page?: number;
  date_from?: string; date_to?: string; client_id?: string;
}) => api.get('/credit-notes', { params });

export const getCreditNote = (id: string) =>
  api.get<{ data: Document }>(`/credit-notes/${id}`);

export const createCreditNote = (data: CreateCreditNoteData) =>
  api.post<{ data: Document }>('/credit-notes', data);

export const issueCreditNote = (id: string, cancelSourceInvoice = false) =>
  api.post(`/credit-notes/${id}/issue`, { cancel_source_invoice: cancelSourceInvoice });

export const deleteCreditNote = (id: string) =>
  api.delete(`/credit-notes/${id}`);

export const downloadCreditNotePdf = (id: string) =>
  api.get(`/credit-notes/${id}/pdf`, { responseType: 'blob' });

// Prefill a credit note from an existing invoice's line items.
export const creditNoteItemsFromInvoice = (invoice: Document): CreditNoteItemInput[] =>
  (invoice.items || []).map((item: DocumentItem) => ({
    product_service_id: item.product_service_id || null,
    item_type: item.item_type,
    description: item.description,
    quantity: Number(item.quantity),
    price: Number(item.price),
    discount_type: item.discount_type || 'percent',
    discount_value: Number(item.discount_value || 0),
    tax_percent: Number(item.tax_percent || 0),
    unit: item.unit || '',
  }));
