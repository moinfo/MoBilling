import api from './axios';

export interface CannedReply {
  id: string;
  title: string;
  body: string;
  created_at?: string;
  updated_at?: string;
}

export const getCannedReplies = () =>
  api.get<{ data: CannedReply[] }>('/canned-replies');

export const createCannedReply = (data: { title: string; body: string }) =>
  api.post<{ data: CannedReply }>('/canned-replies', data);

export const updateCannedReply = (id: string, data: { title: string; body: string }) =>
  api.put<{ data: CannedReply }>(`/canned-replies/${id}`, data);

export const deleteCannedReply = (id: string) =>
  api.delete(`/canned-replies/${id}`);
