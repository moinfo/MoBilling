import api from './axios';

export interface TicketReplyRow {
  id: string;
  author_type: 'staff' | 'client';
  author_name: string;
  message: string;
  created_at: string;
}

export interface TicketRow {
  id: string;
  ticket_number: string;
  subject: string;
  status: 'open' | 'answered' | 'customer_reply' | 'closed';
  priority: 'low' | 'medium' | 'high';
  client: { id: string; name: string } | null;
  assignee: { id: string; name: string } | null;
  replies_count: number | null;
  last_reply_at: string | null;
  created_at: string;
  replies?: TicketReplyRow[];
}

export const TICKET_STATUS_META: Record<TicketRow['status'], { label: string; color: string }> = {
  open:           { label: 'Open',           color: 'green' },
  answered:       { label: 'Answered',       color: 'blue' },
  customer_reply: { label: 'Customer Reply', color: 'orange' },
  closed:         { label: 'Closed',         color: 'gray' },
};

export const PRIORITY_COLORS: Record<string, string> = { low: 'gray', medium: 'blue', high: 'red' };

// Staff
export const getTickets = (params?: Record<string, string>) => api.get('/tickets', { params });
export const getTicketStats = () => api.get<{ awaiting_reply: number; answered: number; closed: number }>('/tickets/stats');
export const getTicket = (id: string) => api.get<{ data: TicketRow }>(`/tickets/${id}`);
export const replyTicket = (id: string, message: string) => api.post<{ data: TicketRow }>(`/tickets/${id}/reply`, { message });
export const setTicketStatus = (id: string, status: 'open' | 'closed') => api.post<{ data: TicketRow }>(`/tickets/${id}/status`, { status });
export const assignTicket = (id: string, userId: string | null) => api.post<{ data: TicketRow }>(`/tickets/${id}/assign`, { user_id: userId });
