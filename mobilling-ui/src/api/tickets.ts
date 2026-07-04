import api from './axios';

export interface TicketAttachment {
  id: string;
  original_name: string;
  mime: string | null;
  size: number;
  download_url: string;
}

export interface TicketReplyRow {
  id: string;
  author_type: 'staff' | 'client';
  author_name: string;
  message: string;
  created_at: string;
  attachments?: TicketAttachment[];
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

export const replyTicket = (id: string, message: string, files: File[] = []) => {
  if (files.length === 0) {
    return api.post<{ data: TicketRow }>(`/tickets/${id}/reply`, { message });
  }
  const fd = new FormData();
  fd.append('message', message);
  files.forEach((f) => fd.append('attachments[]', f));
  return api.post<{ data: TicketRow }>(`/tickets/${id}/reply`, fd, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};

// Streams an attachment through the authenticated endpoint and triggers a browser download.
export const downloadTicketAttachment = async (att: TicketAttachment) => {
  const res = await api.get(att.download_url, { responseType: 'blob' });
  const url = window.URL.createObjectURL(new Blob([res.data], { type: att.mime || 'application/octet-stream' }));
  const link = document.createElement('a');
  link.href = url;
  link.setAttribute('download', att.original_name);
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(url);
};
export const setTicketStatus = (id: string, status: 'open' | 'closed') => api.post<{ data: TicketRow }>(`/tickets/${id}/status`, { status });
export const assignTicket = (id: string, userId: string | null) => api.post<{ data: TicketRow }>(`/tickets/${id}/assign`, { user_id: userId });
