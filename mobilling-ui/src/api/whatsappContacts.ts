import api from './axios';

export type WaLabel =
  | 'lead'
  | 'new_customer'
  | 'new_order'
  | 'follow_up'
  | 'pending_payment'
  | 'paid'
  | 'order_complete';

export type WaSource = 'whatsapp_ad' | 'direct' | 'referral' | 'other';

export interface WhatsappContact {
  id: string;
  name: string;
  phone: string;
  label: WaLabel;
  is_important: boolean;
  source: WaSource;
  campaign_id: string | null;
  campaign: { id: string; name: string } | null;
  notes: string | null;
  next_followup_date: string | null;
  assigned_to: string | null;
  client_id: string | null;
  client: { id: string; name: string } | null;
  assigned_user: { id: string; name: string } | null;
  created_at: string;
}

export interface WaStats {
  total: number;
  converted: number;
  by_label: Record<WaLabel, number>;
  by_source: Record<WaSource, number>;
}

export const LABEL_META: Record<WaLabel, { label: string; color: string }> = {
  lead:            { label: 'Lead',            color: 'violet' },
  new_customer:    { label: 'New Customer',    color: 'blue' },
  new_order:       { label: 'New Order',       color: 'yellow' },
  follow_up:       { label: 'Follow Up',       color: 'teal' },
  pending_payment: { label: 'Pending Payment', color: 'orange' },
  paid:            { label: 'Paid',            color: 'grape' },
  order_complete:  { label: 'Order Complete',  color: 'green' },
};

export const SOURCE_META: Record<WaSource, string> = {
  whatsapp_ad: 'WhatsApp Ad',
  direct:      'Direct',
  referral:    'Referral',
  other:       'Other',
};

export const LABEL_ORDER: WaLabel[] = [
  'lead', 'new_customer', 'new_order', 'follow_up', 'pending_payment', 'paid', 'order_complete',
];

export const getContacts = (params?: Record<string, string>) =>
  api.get<WhatsappContact[]>('/whatsapp-contacts', { params });

export const getStats = () =>
  api.get<WaStats>('/whatsapp-contacts/stats');

export interface ExistingClientMatch {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
}

export const createContact = (data: Partial<WhatsappContact>) =>
  api.post<{ contact: WhatsappContact; existing_client: ExistingClientMatch | null }>('/whatsapp-contacts', data);

export const updateContact = (id: string, data: Partial<WhatsappContact>) =>
  api.put<WhatsappContact>(`/whatsapp-contacts/${id}`, data);

export const deleteContact = (id: string) =>
  api.delete(`/whatsapp-contacts/${id}`);

export const convertToClient = (id: string, data: { client_id?: string; client_name?: string; client_email?: string; client_phone?: string }) =>
  api.post<WhatsappContact>(`/whatsapp-contacts/${id}/convert`, data);
