import api from './axios';

export interface AppNotification {
  id: string;
  type: string;
  data: {
    type: string;
    title: string;
    message: string;
    url?: string;
  };
  read_at: string | null;
  created_at: string;
}

export const getNotifications = (params?: { page?: number; per_page?: number }) =>
  api.get<{ data: AppNotification[]; meta: { current_page: number; last_page: number } }>(
    '/notifications',
    { params }
  );

export const getUnreadCount = () =>
  api.get<{ count: number }>('/notifications/unread-count');

export const markAsRead = (id: string) =>
  api.patch(`/notifications/${id}/read`);

export const markAllAsRead = () =>
  api.post('/notifications/mark-all-read');
