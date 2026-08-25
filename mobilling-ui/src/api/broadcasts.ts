import api from './axios';

export interface Broadcast {
  id: string;
  channel: 'email' | 'sms' | 'whatsapp' | 'both';
  subject: string | null;
  body: string | null;
  sms_body: string | null;
  whatsapp_body: string | null;
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

export interface SendBroadcastPayload {
  channel: 'email' | 'sms' | 'whatsapp' | 'both';
  subject?: string;
  body?: string;
  sms_body?: string;
  whatsapp_body?: string;
  client_ids?: string[];
}

export interface BroadcastRecipient {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
}

export const getBroadcasts = (params?: { page?: number; per_page?: number }) =>
  api.get('/broadcasts', { params });

export const sendBroadcast = (data: SendBroadcastPayload) =>
  api.post('/broadcasts', data);

export const getBroadcastRecipients = (id: string, status: 'sent' | 'failed') =>
  api.get<{ data: BroadcastRecipient[] }>(`/broadcasts/${id}/recipients`, { params: { status } });

export const resendFailedBroadcast = (id: string) =>
  api.post<{ message: string; broadcast_id: string; total_recipients: number }>(`/broadcasts/${id}/resend-failed`);
