import api from './axios';

export interface Broadcast {
  id: string;
  channel: 'email' | 'sms' | 'both';
  subject: string | null;
  body: string | null;
  sms_body: string | null;
  total_recipients: number;
  sent_count: number;
  failed_count: number;
  sender?: { id: string; name: string };
  created_at: string;
}

export interface SendBroadcastPayload {
  channel: 'email' | 'sms' | 'both';
  subject?: string;
  body?: string;
  sms_body?: string;
  client_ids?: string[];
}

export const getBroadcasts = (params?: { page?: number; per_page?: number }) =>
  api.get('/broadcasts', { params });

export const sendBroadcast = (data: SendBroadcastPayload) =>
  api.post('/broadcasts', data);
