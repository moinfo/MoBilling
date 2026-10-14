import api from './axios';

export interface Broadcast {
  id: string;
  channel: 'email' | 'sms' | 'whatsapp' | 'both';
  subject: string | null;
  body: string | null;
  sms_body: string | null;
  whatsapp_body: string | null;
  whatsapp_image_url: string | null;
  total_recipients: number;
  sent_count: number;
  failed_count: number;
  sent_client_ids: string[] | null;
  failed_client_ids: string[] | null;
  retry_of_broadcast_id: string | null;
  in_progress: boolean;
  sender?: { id: string; name: string };
  created_at: string;
}

export type BroadcastSource = 'mobilling' | 'mosms_contacts';

export interface MosmsContact {
  phone: string | null;
  name: string | null;
  email: string | null;
}

export interface SendBroadcastPayload {
  channel: 'email' | 'sms' | 'whatsapp' | 'both';
  sources?: BroadcastSource[];
  subject?: string;
  body?: string;
  sms_body?: string;
  whatsapp_body?: string;
  whatsapp_image?: File | null;
  client_ids?: string[];
  contact_phones?: string[];
}

export interface BroadcastRecipient {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
  reason: string | null;
}

export interface BroadcastPreviewRecipient {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
}

export interface BroadcastPreviewResponse {
  total: number;
  duplicates_removed: number;
  recipients: BroadcastPreviewRecipient[];
}

export const getBroadcasts = (params?: { page?: number; per_page?: number }) =>
  api.get('/broadcasts', { params });

export const sendBroadcast = (data: SendBroadcastPayload) => {
  if (!data.whatsapp_image) {
    return api.post('/broadcasts', data);
  }

  const form = new FormData();
  form.append('channel', data.channel);
  (data.sources ?? []).forEach((s) => form.append('sources[]', s));
  if (data.subject) form.append('subject', data.subject);
  if (data.body) form.append('body', data.body);
  if (data.sms_body) form.append('sms_body', data.sms_body);
  if (data.whatsapp_body) form.append('whatsapp_body', data.whatsapp_body);
  form.append('whatsapp_image', data.whatsapp_image);
  (data.client_ids ?? []).forEach((id) => form.append('client_ids[]', id));
  (data.contact_phones ?? []).forEach((p) => form.append('contact_phones[]', p));

  return api.post('/broadcasts', form, { headers: { 'Content-Type': 'multipart/form-data' } });
};

export const getBroadcastRecipients = (id: string, status: 'sent' | 'failed') =>
  api.get<{ data: BroadcastRecipient[] }>(`/broadcasts/${id}/recipients`, { params: { status } });

export const previewBroadcast = (data: { channel: string; sources?: BroadcastSource[]; client_ids?: string[]; contact_phones?: string[] }) =>
  api.post<BroadcastPreviewResponse>('/broadcasts/preview', data);

export const getMosmsContacts = () =>
  api.get<{ data: MosmsContact[] }>('/broadcasts/mosms-contacts');

export const resendFailedBroadcast = (id: string) =>
  api.post<{ message: string; broadcast_id: string; total_recipients: number }>(`/broadcasts/${id}/resend-failed`);

export interface BroadcastDeliveryMessage {
  id: string;
  recipient: string;
  client_name: string | null;
  status: string;
  error: string | null;
  delivery_status: string | null;
  delivered_at: string | null;
  delivery_error: string | null;
}

export interface BroadcastDeliveryReport {
  broadcast: { id: string; channel: string; subject: string | null; created_at: string };
  summary: {
    total: number;
    api_sent: number;
    api_failed: number;
    delivery_tracked: number;
    delivered: number;
    delivery_failed: number;
    delivery_pending: number;
  };
  messages: BroadcastDeliveryMessage[];
}

export const getBroadcastDeliveryReport = (id: string) =>
  api.get<BroadcastDeliveryReport>(`/broadcasts/${id}/delivery-report`);
