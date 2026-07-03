import api from './axios';

export interface AnnouncementRow {
  id: string;
  title: string;
  body: string;
  is_published: boolean;
  published_at: string | null;
  created_at: string;
}

export const getAnnouncements = () => api.get<{ data: AnnouncementRow[] }>('/announcements');
export const createAnnouncement = (data: { title: string; body: string; is_published: boolean }) =>
  api.post('/announcements', data);
export const updateAnnouncement = (id: string, data: Partial<{ title: string; body: string; is_published: boolean }>) =>
  api.put(`/announcements/${id}`, data);
export const deleteAnnouncement = (id: string) => api.delete(`/announcements/${id}`);
